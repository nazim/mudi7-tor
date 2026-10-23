-- Run by /etc/init.d/mudi7-tor-sig (procd). While Tor is enabled, shows
-- its state on the lock screen through the "Personalised Signature" line.
-- Writes only gl_screen's RAM copy (/tmp/gl_screen/config/generic); the
-- user's own signature stays in uci and returns when Tor is turned off.
local uci = require('uci')
local L = dofile('/usr/lib/mudi7-tor/lockscreen.lua')

local GENERIC = '/tmp/gl_screen/config/generic'
local INTERVAL = 30
-- One request through Tor per 5 minutes is enough to follow exit changes.
local IP_MAX_AGE = 300
local BACKLIGHT = {'/sys/class/backlight/soc:backlight/bl_power',
                   '/sys/class/backlight/backlight/bl_power'}

local function read(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function write_atomic(path, data)
    local tmp = path .. '.mudi7-tor'
    local f = io.open(tmp, 'w')
    if not f then return false end
    f:write(data)
    f:close()
    return os.rename(tmp, path)
end

local function screen_off()
    for _, path in ipairs(BACKLIGHT) do
        local v = read(path)
        if v then return v:match('^%s*0%s*$') == nil end
    end
    return false
end

local function reload()
    os.execute([[ubus call gl_screen set '{"method":"reload"}' >/dev/null 2>&1]])
end

-- GL's own regeneration from uci brings the user's signature back.
local function restore()
    os.execute('. /etc/gl_screen/scripts/common.sh && gen_screen_config')
    reload()
end

-- The geoip file has ~170k lines; scan it only when the exit changes.
local last_ip, last_cc
local function fetch_exit()
    local p = io.popen('curl -s -m 20 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2>/dev/null')
    local body = p:read('*a')
    p:close()
    local ip = L.exit_ip(body)
    if not ip then return nil end
    if ip ~= last_ip then
        local f = io.open('/usr/share/tor/geoip', 'r') or io.open('/rom/usr/share/tor/geoip', 'r')
        last_ip, last_cc = ip, nil
        if f then
            last_cc = L.country(f:lines(), ip)
            f:close()
        end
    end
    return ip, last_cc
end

-- A RAM copy left by an earlier run still shows Tor text.
local shown = (read(GENERIC) or ''):find('\nSIGNATURE "TOR Conn', 1, true) ~= nil
local ip, cc, checked, state = nil, nil, 0, nil

while true do
    if uci.cursor():get('tor', 'global', 'enable') ~= '1' then
        if shown then restore() end
        shown, ip, cc, checked, state = false, nil, nil, 0, nil
    else
        local percent = L.bootstrap_percent(read('/var/lib/tor/control.log'))
        local off = screen_off()
        if percent == 100 then
            -- Nobody reads the lock screen while the backlight is off, so no
            -- request goes through Tor until the screen is on again.
            if not off and (not ip or os.time() - checked >= IP_MAX_AGE) then
                checked = os.time()
                local new_ip, new_cc = fetch_exit()
                if new_ip then ip, cc = new_ip, new_cc end
            end
        else
            ip, cc = nil, nil
        end
        local current = read(GENERIC)
        local text = L.text(percent, cc, ip)
        -- The first exit address counts as a state change; later ones do not.
        local new_state = percent ~= 100 and 'connecting' or (ip and 'exit-known' or 'connected')
        if current then
            local wanted = L.with_signature(current, text)
            -- State changes show at once; a new exit address waits for the
            -- screen to sleep, because reload redraws the open page.
            if wanted ~= current and (new_state ~= state or not shown or off) then
                if write_atomic(GENERIC, wanted) then
                    reload()
                    shown, state = true, new_state
                end
            end
        end
    end
    os.execute('sleep ' .. INTERVAL)
end
