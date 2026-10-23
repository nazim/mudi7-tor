-- Adds a virtual "Tor" card to the touchscreen VPN Dashboard.
-- Pure logic: every side effect is injected through `deps`, so the
-- module runs unchanged on the router and in tests/test_tor_card.lua.
local M = {}

-- Far above GL.iNet's real tunnel IDs (observed: 100, 6489) and distinct
-- from mudi7-speedify-screen's 919001.
M.TUNNEL_ID = 919101
M.CARD_ID = 'mudi7-tor'

local function only_toggle_keys(p)
    for k in pairs(p) do
        if k ~= 'tunnel_id' and k ~= 'enabled' then return false end
    end
    return type(p.enabled) == 'boolean'
end

local function integer_id(v)
    local n = tonumber(v)
    if n and n > 0 and n == math.floor(n) then return n end
end

-- The screen submits one group per request (task at 0x21bec0 in gl_screen):
-- {tunnel_id, via = {type, configs = {{group_id, id_list}}}}.
local MAX_IDS = 300
local function submitted_group(via)
    if type(via) ~= 'table' or via.type ~= 'wireguard' or type(via.configs) ~= 'table' then return end
    local cfg = via.configs[1]
    if #via.configs ~= 1 or type(cfg) ~= 'table' or type(cfg.id_list) ~= 'table' then return end
    local ids = {}
    for _, v in ipairs(cfg.id_list) do
        local id = integer_id(v)
        if not id or #ids >= MAX_IDS then return end
        table.insert(ids, id)
    end
    return integer_id(cfg.group_id), ids
end

local function uses_tor_group(via, groups)
    if type(via) ~= 'table' or type(via.configs) ~= 'table' then return false end
    for _, cfg in ipairs(via.configs) do
        if type(cfg) == 'table' and groups[integer_id(cfg.group_id) or 0] then return true end
    end
    return false
end

-- deps:
--   is_screen()   -> boolean       request comes from the touchscreen
--   tor_enabled() -> boolean       uci tor.global.enable == '1'
--   tor_status()  -> 0|1|2|nil     1 once Tor has bootstrapped
--   label()       -> string        second line of the status row
--   pending()     -> 'on'|'off'|nil  switch still running
--   spawn(action, id) -> boolean   start the detached switch script
--   selection()   -> ids           checked bridges and exit countries
--   apply(ids)    -> true | nil, message   save a submitted list
--   array(list)   -> list encoded as a JSON array even when empty
--   group         -> group_id of the Tor list
function M.wrap(original, deps)
    local wrapped = {}
    for name, fn in pairs(original) do
        if type(fn) == 'function' then wrapped[name] = fn end
    end
    local array = deps.array or function(t) return t end
    local tor_groups = {[deps.group] = true}

    local function card_state()
        local pending = deps.pending()
        if pending == 'on' or pending == 'off' then
            return pending == 'on', 2
        end
        if not deps.tor_enabled() then return false, 0 end
        -- Extra parentheses: a call that returns no value must become nil,
        -- or Lua 5.1's tonumber() raises "value expected".
        local status = tonumber((deps.tor_status()))
        if status ~= 1 and status ~= 2 then status = 2 end
        return true, status
    end

    wrapped.get_tunnel = function(p)
        local result = original.get_tunnel(p)
        if not deps.is_screen() then return result end
        if type(result) ~= 'table' or type(result.tunnels) ~= 'table' then return result end
        local enabled = card_state()
        table.insert(result.tunnels, {
            id = M.CARD_ID, tunnel_id = M.TUNNEL_ID, name = 'Tor',
            -- GL's tor_on disables lan->wan forwarding while Tor is enabled,
            -- so nothing reaches the internet outside Tor (leak test 2026-10-23:
            -- UDP, ICMP blocked; DNS answered by Tor's DNSPort).
            enabled = enabled, killswitch = true,
            from = {type = 'default'},
            to = {type = 'default', manual = true, domain_list = '', domain_list_len = 0},
            -- The screen only renders WireGuard-shaped rows; no WG peer exists.
            via = {type = 'wireguard', via = 'tor', configs = {
                {group_id = deps.group, id_list = array(deps.selection())},
            }},
            options = {options_in_used = false, masq = false, local_access = false, service_policy = false}
        })
        return result
    end

    wrapped.get_status = function(p)
        local result = original.get_status(p)
        if not deps.is_screen() then return result end
        if type(result) ~= 'table' or type(result.status_list) ~= 'table' then return result end
        local _, status = card_state()
        table.insert(result.status_list, {
            tunnel_id = M.TUNNEL_ID, name = 'Tor', peer_name = deps.label(),
            type = 'wireguard', via = 'tor', group_id = M.TUNNEL_ID, peer_id = M.TUNNEL_ID,
            -- gl_screen's status-bar VPN badge (task_get_vpn_client_link_status)
            -- skips rows whose enabled is false; Tor has its own badge.
            -- The card switch reads enabled from get_tunnel instead.
            enabled = false, status = status,
            rx_bytes = 0, tx_bytes = 0, ipv4 = '', ipv6 = {}, domain = {}, port = 0
        })
        return result
    end

    wrapped.set_tunnel = function(p)
        if type(p) ~= 'table' then return original.set_tunnel(p) end

        if integer_id(p.tunnel_id) == M.TUNNEL_ID then
            if p.via ~= nil and p.enabled == nil then
                for k in pairs(p) do
                    if k ~= 'tunnel_id' and k ~= 'via' then
                        return {err_code = -32602, err_msg = 'Tor card accepts only its own lists'}
                    end
                end
                local group, ids = submitted_group(p.via)
                if not group or not tor_groups[group] then
                    return {err_code = -32602, err_msg = 'Choose the Tor list'}
                end
                local ok, err = deps.apply(ids)
                if not ok then return {err_code = -32000, err_msg = err or 'Could not save'} end
                if deps.tor_enabled() then deps.spawn('tor-restart') end
                return {tunnel_id = M.TUNNEL_ID}
            end
            if not only_toggle_keys(p) then
                return {err_code = -32602, err_msg = 'Tor card supports only on/off'}
            end
            if not deps.spawn(p.enabled and 'tor-on' or 'tor-off') then
                return {err_code = -32000, err_msg = 'Tor switch is busy'}
            end
            return {tunnel_id = M.TUNNEL_ID}
        end

        -- The Use list is shared by every card, so a real tunnel can be
        -- pointed at a Tor list; it has no WireGuard peers behind it.
        if uses_tor_group(p.via, tor_groups) then
            return {err_code = -32602, err_msg = 'Tor lists belong to the Tor card'}
        end

        -- A VPN tunnel turned on from the screen while Tor runs: Tor goes off
        -- first. Web admin requests and full tunnel edits keep GL.iNet's own
        -- behaviour.
        local id = integer_id(p.tunnel_id)
        if id and p.enabled == true and only_toggle_keys(p) and deps.is_screen() and deps.tor_enabled() then
            if not deps.spawn('vpn-on', id) then
                return {err_code = -32000, err_msg = 'Tor switch is busy'}
            end
            return {tunnel_id = id}
        end

        return original.set_tunnel(p)
    end

    return wrapped
end

return M
