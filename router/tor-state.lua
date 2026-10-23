-- Router-side reads and writes shared by the vpn-client and wg-client
-- handlers. Pure list logic lives in tor-lists.lua. Files are re-read only
-- when their size or mtime changed (filecache.lua), because the touchscreen
-- polls the VPN handlers every few seconds.
local uci = require('uci')
local cjson = require('cjson')

local lib = '/usr/lib/mudi7-tor/'
local lists = dofile(lib .. 'tor-lists.lua')
local filecache = dofile(lib .. 'filecache.lua')

local M = {lists = lists}
M.group = lists.GROUP

local TORRC = '/etc/tor/torrc'
local TOR_CONFIG = '/etc/config/tor'
local CONTROL_LOG = '/var/lib/tor/control.log'
local COUNTRIES = '/etc/gl_screen/countries.json'

local function read(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

-- Same directory as the target, so the final rename is atomic.
local function write_atomic(path, data)
    local tmp = path .. '.mudi7-tor'
    local f, err = io.open(tmp, 'w')
    if not f then return nil, err end
    local ok, werr = f:write(data)
    f:close()
    if not ok then os.remove(tmp); return nil, werr end
    local renamed, rerr = os.rename(tmp, path)
    if not renamed then os.remove(tmp); return nil, rerr end
    return true
end

-- nixio ships with GL.iNet's Lua; without it every call re-reads.
local has_nixio, nixio = pcall(require, 'nixio')
local uncached = 0
local function stat(path)
    if has_nixio and nixio.fs then
        local s = nixio.fs.stat(path)
        if s then return s.size, s.mtime end
        return nil
    end
    uncached = uncached + 1
    return uncached, uncached
end

local cache = filecache.new(stat, read)

local function parse_cfg()
    local c = uci.cursor()
    return {
        enable = c:get('tor', 'global', 'enable'),
        manual = c:get('tor', 'global', 'manual'),
        countries = c:get('tor', 'global', 'countries'),
    }
end

local function parse_percent(log)
    local last
    for p in log:gmatch('Bootstrapped (%d+)%%') do last = tonumber(p) end
    return last or false
end

-- The touchscreen calls http://127.0.0.1/rpc with "glinet: 1" (gl_screen
-- strings); the web admin arrives from a LAN address.
function M.is_screen()
    if not ngx then return false end
    local addr = ngx.var.remote_addr
    return (addr == '127.0.0.1' or addr == '::1') and ngx.req.get_headers()['glinet'] ~= nil
end

local countries
function M.countries()
    if not countries then
        local ok, list = pcall(cjson.decode, read(COUNTRIES) or '[]')
        countries = ok and type(list) == 'table' and list or {}
    end
    return countries
end

function M.cfg()
    return cache.get(TOR_CONFIG, parse_cfg) or {}
end

function M.bridges()
    return cache.get(TORRC, lists.parse_bridges) or {}
end

function M.tor_enabled()
    return M.cfg().enable == '1'
end

-- Same rule as GL's tor.get_status: the last "Bootstrapped" line in Tor's
-- control log reads 100% once Tor is connected.
function M.tor_status()
    return cache.get(CONTROL_LOG, parse_percent) == 100 and 1 or 2
end

function M.label()
    local cfg = M.cfg()
    local bridge = #lists.enabled_bridge_ids(M.bridges()) > 0 and 'obfs4 bridge' or 'no bridge'
    local exits = 'all exits'
    if cfg.manual == '1' then
        local n = 0
        for _ in (cfg.countries or ''):gmatch('%S+') do n = n + 1 end
        exits = n .. ' exit countries'
    end
    return bridge .. ' · ' .. exits
end

function M.selection()
    local cfg = M.cfg()
    return lists.selection_ids(M.countries(), cfg.manual, cfg.countries, M.bridges())
end

function M.count()
    return #M.bridges() + #M.countries()
end

-- Full rows for the Use screen; /proc/net/tcp is read only here.
function M.peers()
    local cfg = M.cfg()
    return lists.peers_from(M.countries(), cfg.manual, cfg.countries, M.bridges(),
                            read('/proc/net/tcp'))
end

-- torrc first: if it cannot be written, the exit setting stays unchanged too.
function M.apply(ids)
    local bridges, exits = lists.split_ids(ids)
    local torrc = read(TORRC)
    if not torrc then return nil, 'torrc not found' end
    local ok, err = write_atomic(TORRC, (lists.apply_bridges(torrc, bridges)))
    if not ok then return nil, err end
    local value = lists.countries_for_ids(M.countries(), exits)
    local c = uci.cursor()
    c:set('tor', 'global', 'manual', value and '1' or '0')
    if value then c:set('tor', 'global', 'countries', value) end
    c:commit('tor')
    cache.forget(TORRC)
    cache.forget(TOR_CONFIG)
    return true
end

function M.array(t)
    if #t == 0 then return cjson.empty_array end
    return t
end

return M
