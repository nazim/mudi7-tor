-- Installed as /usr/lib/oui-httpd/rpc/vpn-client by install.sh.
-- GL.iNet's handler keeps every method; tor-card.lua only adds the Tor card.
local lib = '/usr/lib/mudi7-tor/'
local run = '/var/run/mudi7-tor/'
local switch = '/usr/libexec/mudi7-tor/switch'
-- A switch normally finishes in seconds; a stale marker must not lock the card.
local PENDING_MAX_AGE = 90

local original = assert(loadfile(lib .. 'vpn-client.original'))()
local card = dofile(lib .. 'tor-card.lua')
local state = dofile(lib .. 'tor-state.lua')

local function read_pending()
    local f = io.open(run .. 'pending', 'r')
    if not f then return nil end
    local action, stamp = (f:read('*l') or ''):match('^(%a+) (%d+)$')
    f:close()
    local age = os.time() - (tonumber(stamp) or 0)
    if action and age >= 0 and age <= PENDING_MAX_AGE then return action end
end

local ACTIONS = {['tor-on'] = 'on', ['tor-off'] = 'off', ['vpn-on'] = 'off', ['tor-restart'] = 'on'}

local function spawn(action, id)
    local shown = ACTIONS[action]
    if not shown or read_pending() then return false end
    os.execute('mkdir -p ' .. run)
    local f = io.open(run .. 'pending', 'w')
    if not f then return false end
    f:write(shown, ' ', os.time(), '\n')
    f:close()
    -- action comes from ACTIONS and id is formatted as an integer, so no
    -- RPC input reaches the shell as text.
    os.execute(string.format('%s %s %d </dev/null >/dev/null 2>&1 &', switch, action, id or 0))
    return true
end

return card.wrap(original, {
    group = state.group,
    is_screen = state.is_screen,
    selection = state.selection,
    apply = state.apply,
    array = state.array,
    tor_enabled = state.tor_enabled,
    tor_status = state.tor_status,
    label = state.label,
    pending = read_pending,
    spawn = spawn,
})
