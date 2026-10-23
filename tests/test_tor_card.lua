-- Run: lua tests/test_tor_card.lua (Lua 5.1 / LuaJIT and newer)
package.path = './router/?.lua;' .. package.path
local card = require('tor-card')
local ID = card.TUNNEL_ID

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then print('ok   ' .. name) else failures = failures + 1; print('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or '') .. ' expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end
end

local GROUP = 919102

local function fixture(opts)
    opts = opts or {}
    local calls = {spawned = {}, set_tunnel = {}, applied = {}}
    local original = {
        get_tunnel = function() return {tunnels = {{tunnel_id = 6489, name = 'Tunnel 1', enabled = false}}} end,
        get_status = function() return {status_list = {{tunnel_id = 6489, name = 'Tunnel 1'}}, mode = 0} end,
        set_tunnel = function(p) table.insert(calls.set_tunnel, p); return {tunnel_id = p and p.tunnel_id} end,
        get_other = function() return 'untouched' end,
    }
    local deps = {
        group = GROUP,
        is_screen = function() return opts.web ~= true end,
        selection = function() return {1000001, 920100, 920200} end,
        apply = function(ids)
            table.insert(calls.applied, {ids = ids})
            if opts.apply_fails then return nil, 'disk full' end
            return true
        end,
        tor_enabled = function() return opts.enabled or false end,
        tor_status = function() return opts.status end,
        label = function() return 'obfs4 · 31 countries' end,
        pending = function() return opts.pending end,
        spawn = function(action, id)
            table.insert(calls.spawned, {action = action, id = id})
            return not opts.busy
        end,
    }
    return card.wrap(original, deps), calls
end

local function last(t) return t[#t] end

test('other methods pass through unchanged', function()
    local w = fixture()
    eq(w.get_other(), 'untouched')
end)

test('get_tunnel appends one Tor card after real tunnels', function()
    local r = fixture().get_tunnel({})
    eq(#r.tunnels, 2)
    eq(r.tunnels[1].tunnel_id, 6489)
    eq(last(r.tunnels).tunnel_id, ID)
    eq(last(r.tunnels).name, 'Tor')
    eq(last(r.tunnels).via.type, 'wireguard')
    eq(last(r.tunnels).killswitch, true)
end)

test('get_tunnel leaves error results alone', function()
    local w = card.wrap({get_tunnel = function() return {err_code = 1} end},
        {group = GROUP, is_screen = function() return true end})
    eq(w.get_tunnel({}).err_code, 1)
end)

test('web admin requests never see the Tor card', function()
    local w = fixture({web = true, enabled = true, status = 1})
    eq(#w.get_tunnel({}).tunnels, 1)
    eq(#w.get_status({}).status_list, 1)
end)

test('card via carries the single Tor list with its check marks', function()
    local cfg = last(fixture().get_tunnel({}).tunnels).via.configs
    eq(#cfg, 1, 'gl_screen keeps one group per card')
    eq(cfg[1].group_id, GROUP); eq(#cfg[1].id_list, 3); eq(cfg[1].id_list[1], 1000001)
end)

local function submit(group, ids)
    return {tunnel_id = ID, via = {type = 'wireguard', configs = {{group_id = group, id_list = ids}}}}
end

test('submitting the list saves it and restarts a running Tor', function()
    local w, calls = fixture({enabled = true, status = 1})
    eq(w.set_tunnel(submit(GROUP, {1000001, 920100, '920200'})).tunnel_id, ID)
    eq(#calls.applied[1].ids, 3); eq(calls.applied[1].ids[3], 920200)
    eq(calls.spawned[1].action, 'tor-restart')
end)

test('submitting an empty list while Tor is off saves without a restart', function()
    local w, calls = fixture({enabled = false})
    w.set_tunnel(submit(GROUP, {}))
    eq(#calls.applied[1].ids, 0)
    eq(#calls.spawned, 0)
end)

test('Tor card rejects foreign groups and malformed lists', function()
    local w, calls = fixture()
    eq(w.set_tunnel(submit(10003, {2001})).err_code, -32602)
    eq(w.set_tunnel(submit(919103, {})).err_code, -32602)
    eq(w.set_tunnel(submit(GROUP, {'x'})).err_code, -32602)
    eq(w.set_tunnel(submit(GROUP, {1.5})).err_code, -32602)
    local two = submit(GROUP, {})
    table.insert(two.via.configs, {group_id = GROUP, id_list = {}})
    eq(w.set_tunnel(two).err_code, -32602)
    local extra = submit(GROUP, {}); extra.name = 'x'
    eq(w.set_tunnel(extra).err_code, -32602)
    eq(w.set_tunnel({tunnel_id = ID, via = {type = 'novpn'}}).err_code, -32602)
    eq(#calls.applied, 0)
end)

test('a failed save is reported, not hidden', function()
    local w = fixture({apply_fails = true})
    local r = w.set_tunnel(submit(GROUP, {920100}))
    eq(r.err_code, -32000); eq(r.err_msg, 'disk full')
end)

test('real tunnels cannot use the Tor lists but keep their own', function()
    local w, calls = fixture()
    local bad = {tunnel_id = 6489, via = {type = 'wireguard', configs = {{group_id = GROUP, id_list = {920100}}}}}
    eq(w.set_tunnel(bad).err_code, -32602)
    w.set_tunnel({tunnel_id = 6489, via = {type = 'wireguard', configs = {{group_id = 10003, id_list = {2001}}}}})
    eq(#calls.set_tunnel, 1)
end)

test('web admin VPN switches keep GL behaviour while Tor runs', function()
    local w, calls = fixture({web = true, enabled = true, status = 1})
    w.set_tunnel({tunnel_id = 6489, enabled = true})
    eq(#calls.spawned, 0); eq(#calls.set_tunnel, 1)
end)

test('card is off with status 0 when Tor is disabled', function()
    local w = fixture({enabled = false, status = 1})
    eq(last(w.get_tunnel({}).tunnels).enabled, false)
    eq(last(w.get_status({}).status_list).status, 0)
end)

test('card shows connected when Tor is enabled and bootstrapped', function()
    local w = fixture({enabled = true, status = 1})
    eq(last(w.get_tunnel({}).tunnels).enabled, true)
    local row = last(w.get_status({}).status_list)
    eq(row.status, 1)
    eq(row.peer_name, 'obfs4 · 31 countries')
end)

test('status row never counts towards the VPN status-bar badge', function()
    for _, o in ipairs({{enabled = true, status = 1}, {enabled = false}, {pending = 'on'}}) do
        eq(last(fixture(o).get_status({}).status_list).enabled, false)
    end
end)

test('card shows connecting while Tor is enabled but not connected', function()
    eq(last(fixture({enabled = true, status = 0}).get_status({}).status_list).status, 2)
    eq(last(fixture({enabled = true, status = nil}).get_status({}).status_list).status, 2)
end)

test('tor_status returning no value shows connecting instead of crashing', function()
    local w = card.wrap({get_status = function() return {status_list = {}} end}, {
        group = GROUP,
        is_screen = function() return true end,
        tor_enabled = function() return true end,
        tor_status = function() end,
        label = function() return '' end,
        pending = function() end,
    })
    eq(last(w.get_status({}).status_list).status, 2)
end)

test('pending switch overrides the observed state', function()
    local w = fixture({enabled = false, pending = 'on'})
    eq(last(w.get_tunnel({}).tunnels).enabled, true)
    eq(last(w.get_status({}).status_list).status, 2)
    w = fixture({enabled = true, status = 1, pending = 'off'})
    eq(last(w.get_tunnel({}).tunnels).enabled, false)
    eq(last(w.get_status({}).status_list).status, 2)
end)

test('toggling the Tor card spawns tor-on / tor-off', function()
    local w, calls = fixture()
    eq(w.set_tunnel({tunnel_id = ID, enabled = true}).tunnel_id, ID)
    eq(calls.spawned[1].action, 'tor-on')
    w.set_tunnel({tunnel_id = tostring(ID), enabled = false})
    eq(calls.spawned[2].action, 'tor-off')
    eq(#calls.set_tunnel, 0, 'GL handler must not see the virtual card')
end)

test('Tor card rejects anything but on/off', function()
    local w, calls = fixture()
    eq(w.set_tunnel({tunnel_id = ID, enabled = true, name = 'x'}).err_code, -32602)
    eq(w.set_tunnel({tunnel_id = ID, enabled = 'yes'}).err_code, -32602)
    eq(#calls.spawned, 0)
end)

test('busy switch reports an error instead of success', function()
    local w = fixture({busy = true})
    eq(w.set_tunnel({tunnel_id = ID, enabled = true}).err_code, -32000)
end)

test('turning a VPN on while Tor runs hands off to the switch', function()
    local w, calls = fixture({enabled = true, status = 1})
    eq(w.set_tunnel({tunnel_id = 6489, enabled = true}).tunnel_id, 6489)
    eq(calls.spawned[1].action, 'vpn-on'); eq(calls.spawned[1].id, 6489)
    eq(#calls.set_tunnel, 0)
end)

test('VPN changes pass through when Tor is off', function()
    local w, calls = fixture({enabled = false})
    w.set_tunnel({tunnel_id = 6489, enabled = true})
    eq(#calls.set_tunnel, 1); eq(#calls.spawned, 0)
end)

test('VPN off and full tunnel edits pass through even with Tor on', function()
    local w, calls = fixture({enabled = true, status = 1})
    w.set_tunnel({tunnel_id = 6489, enabled = false})
    w.set_tunnel({tunnel_id = 6489, enabled = true, name = 'Tunnel 1'})
    eq(#calls.set_tunnel, 2); eq(#calls.spawned, 0)
end)

test('non-integer tunnel ids never reach the switch', function()
    local w, calls = fixture({enabled = true, status = 1})
    w.set_tunnel({tunnel_id = '6489; reboot', enabled = true})
    w.set_tunnel({tunnel_id = 1.5, enabled = true})
    eq(#calls.spawned, 0); eq(#calls.set_tunnel, 2)
end)

print(string.format('%d/%d passed', count - failures, count))
os.exit(failures == 0 and 0 or 1)
