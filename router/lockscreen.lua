-- Tor status line for the lock-screen "Personalised Signature".
-- Pure functions; tor-sig.lua does the reading, writing and timing.
local M = {}

function M.valid_ipv4(ip)
    if type(ip) ~= 'string' then return nil end
    local a, b, c, d = ip:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    if not a then return nil end
    for _, n in ipairs({a, b, c, d}) do
        if tonumber(n) > 255 then return nil end
    end
    return ip
end

function M.ip_to_int(ip)
    local a, b, c, d = ip:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    return ((tonumber(a) * 256 + tonumber(b)) * 256 + tonumber(c)) * 256 + tonumber(d)
end

-- Tor's geoip file: "low,high,CC" lines sorted by low, both as integers.
function M.country(lines, ip)
    local n = M.ip_to_int(ip)
    for line in lines do
        local low, high, cc = line:match('^(%d+),(%d+),(%u%u)$')
        if low then
            low = tonumber(low)
            if low > n then return nil end
            if n <= tonumber(high) then return cc end
        end
    end
end

-- Last bootstrap percentage in Tor's control log, or nil before the first.
function M.bootstrap_percent(log)
    local last
    for p in (log or ''):gmatch('Bootstrapped (%d+)%%') do last = tonumber(p) end
    return last
end

-- check.torproject.org/api/ip answers {"IsTor":true,"IP":"a.b.c.d"}.
function M.exit_ip(body)
    if type(body) ~= 'string' or not body:find('"IsTor"%s*:%s*true') then return nil end
    return M.valid_ipv4(body:match('"IP"%s*:%s*"([^"]+)"'))
end

function M.text(percent, cc, ip)
    if percent ~= 100 then
        return 'TOR Connecting ' .. (percent or 0) .. '%'
    end
    local parts = {'TOR Connected'}
    if cc and cc:match('^%u%u$') then table.insert(parts, cc) end
    if M.valid_ipv4(ip) then table.insert(parts, ip) end
    return table.concat(parts, ' ')
end

-- /tmp/gl_screen/config/generic holds "KEY value" lines; gl_screen shows a
-- quoted value without the quotes and does not unescape "\n", so the text
-- stays on one line and must not contain quotes or backslashes.
function M.with_signature(generic, text)
    assert(not text:find('["\\\n]'), 'unsafe signature text')
    local line = 'SIGNATURE "' .. text .. '"'
    local out, seen = {}, false
    for l in (generic or ''):gmatch('[^\n]+') do
        if l:match('^SIGNATURE ') then
            table.insert(out, line)
            seen = true
        else
            table.insert(out, l)
        end
    end
    if not seen then table.insert(out, line) end
    return table.concat(out, '\n') .. '\n'
end

return M
