-- Bridges and exit countries shown as one WireGuard-style group on the
-- touchscreen. gl_screen keeps check marks for a single group per card (it
-- only fetches the last via.configs group), so both share one list.
-- Pure functions: callers pass file contents and uci values.
local M = {}

M.GROUP = 919102
local DISABLED = '#mudi7-tor-off '
local DISABLED_PAT = DISABLED:gsub('%-', '%%-')

-- Stable ids derived from the data itself, so a reordered countries.json or
-- torrc never moves a check mark to another row. Ranges stay apart:
-- countries 920028..920728, bridges 1000000..2048575.
function M.country_id(code)
    local a, b = code:upper():byte(1, 2)
    return 920000 + (a - 64) * 27 + (b - 64)
end

function M.bridge_id(fingerprint)
    return 1000000 + tonumber(fingerprint:sub(1, 5), 16)
end

function M.is_bridge_id(id)
    return id >= 1000000
end

-- countries: decoded countries.json ({code=, name={en=}} list)
-- manual, selected: uci tor.global.manual / tor.global.countries
function M.exit_peers(countries, manual, selected)
    local chosen = {}
    if manual == '1' then
        for code in (selected or ''):gmatch('%S+') do chosen[code:lower()] = true end
    end
    local peers, ids = {}, {}
    for _, c in ipairs(countries) do
        local id = M.country_id(c.code)
        table.insert(peers, {peer_id = id, name = c.name and c.name.en or c.code, location = c.code})
        if chosen[c.code:lower()] then table.insert(ids, id) end
    end
    return peers, ids
end

-- Returns the uci countries value for the given ids; nil means "all exits".
function M.countries_for_ids(countries, ids)
    local wanted = {}
    for _, id in ipairs(ids) do wanted[id] = true end
    local codes = {}
    for _, c in ipairs(countries) do
        if wanted[M.country_id(c.code)] then table.insert(codes, c.code:lower()) end
    end
    if #codes == 0 then return nil end
    return table.concat(codes, ' ')
end

-- obfs4 bridge lines, enabled or disabled by this tool. Other lines are
-- never listed and never rewritten.
function M.parse_bridges(torrc)
    local bridges = {}
    for line in (torrc .. '\n'):gmatch('([^\n]*)\n') do
        local off, rest = false, line:match('^Bridge%s+(.*)$')
        if not rest then
            rest = line:match('^' .. DISABLED_PAT .. 'Bridge%s+(.*)$')
            off = rest ~= nil
        end
        local ip, port, fp = (rest or ''):match('^obfs4%s+(%d+%.%d+%.%d+%.%d+):(%d+)%s+(%x+)')
        if ip and #fp == 40 then
            table.insert(bridges, {id = M.bridge_id(fp), enabled = not off,
                                   ip = ip, port = tonumber(port)})
        end
    end
    return bridges
end

-- /proc/net/tcp stores the remote IPv4 address as little-endian hex.
function M.proc_tcp_key(ip, port)
    local a, b, c, d = ip:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    return string.format('%02X%02X%02X%02X:%04X', d, c, b, a, port)
end

function M.established(proc_tcp)
    local set = {}
    for line in (proc_tcp or ''):gmatch('[^\n]+') do
        local remote, state = line:match('^%s*%d+:%s+%x+:%x+%s+(%x+:%x+)%s+(%x+)')
        if state == '01' then set[remote:upper()] = true end
    end
    return set
end

function M.enabled_bridge_ids(bridges)
    local ids = {}
    for _, b in ipairs(bridges) do
        if b.enabled then table.insert(ids, b.id) end
    end
    return ids
end

-- Rows for parsed bridges; proc_tcp is read only here, when the list is open.
function M.bridge_rows(bridges, proc_tcp)
    local up = M.established(proc_tcp)
    local peers, ids = {}, {}
    for _, b in ipairs(bridges) do
        local status = 'Off'
        if b.enabled then
            status = up[M.proc_tcp_key(b.ip, b.port)] and 'Connected' or 'Idle'
            table.insert(ids, b.id)
        end
        -- gl_screen sorts rows by name; '(' sorts before every letter, so
        -- bridges stay above the countries. The port moves to the second
        -- line so the name fits the 240 px row without scrolling.
        table.insert(peers, {peer_id = b.id, name = '(Bridge) ' .. b.ip,
                             location = 'obfs4 :' .. b.port .. ' - ' .. status})
    end
    return peers, ids
end

function M.bridge_peers(torrc, proc_tcp)
    return M.bridge_rows(M.parse_bridges(torrc), proc_tcp)
end

-- The one list the screen shows: bridges first, then exit countries.
function M.peers_from(countries, manual, selected, bridges, proc_tcp)
    local peers, ids = M.bridge_rows(bridges, proc_tcp)
    local cpeers, cids = M.exit_peers(countries, manual, selected)
    for _, p in ipairs(cpeers) do table.insert(peers, p) end
    for _, id in ipairs(cids) do table.insert(ids, id) end
    return peers, ids
end

function M.peers(countries, manual, selected, torrc, proc_tcp)
    return M.peers_from(countries, manual, selected, M.parse_bridges(torrc), proc_tcp)
end

-- Check marks only: no /proc/net/tcp read for the dashboard polls.
function M.selection_ids(countries, manual, selected, bridges)
    local ids = M.enabled_bridge_ids(bridges)
    local _, cids = M.exit_peers(countries, manual, selected)
    for _, id in ipairs(cids) do table.insert(ids, id) end
    return ids
end

function M.split_ids(ids)
    local bridges, countries = {}, {}
    for _, id in ipairs(ids) do
        table.insert(M.is_bridge_id(id) and bridges or countries, id)
    end
    return bridges, countries
end

-- Rewrites torrc so exactly the given bridge ids are active. UseBridges
-- follows: no active bridge means Tor connects directly.
function M.apply_bridges(torrc, ids)
    local wanted = {}
    for _, id in ipairs(ids) do wanted[id] = true end
    local known = {}
    for _, b in ipairs(M.parse_bridges(torrc)) do known[b.id] = true end
    local out, active, use_seen = {}, 0, false
    for raw in (torrc .. '\n'):gmatch('([^\n]*)\n') do
        local line = raw
        local body = line:match('^' .. DISABLED_PAT .. '(Bridge%s+.*)$') or line:match('^(Bridge%s+.*)$')
        local fp = body and body:match('^Bridge%s+obfs4%s+%d+%.%d+%.%d+%.%d+:%d+%s+(%x+)')
        if fp and #fp == 40 and known[M.bridge_id(fp)] then
            if wanted[M.bridge_id(fp)] then
                line = body
                active = active + 1
            else
                line = DISABLED .. body
            end
        elseif line:match('^UseBridges%s') then
            use_seen = #out + 1
        end
        table.insert(out, line)
    end
    if out[#out] == '' then table.remove(out) end
    local use = 'UseBridges ' .. (active > 0 and '1' or '0')
    if use_seen then out[use_seen] = use else table.insert(out, use) end
    return table.concat(out, '\n') .. '\n', active
end

return M
