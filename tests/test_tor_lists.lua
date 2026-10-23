-- Run: lua tests/test_tor_lists.lua (Lua 5.1 / LuaJIT and newer)
package.path = './router/?.lua;' .. package.path
local L = require('tor-lists')

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then print('ok   ' .. name) else failures = failures + 1; print('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or '') .. ' expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end
end

local COUNTRIES = {
    {code = 'AT', name = {en = 'Austria'}},
    {code = 'DE', name = {en = 'Germany'}},
    {code = 'TR', name = {en = 'Turkey'}},
}
local FP1 = 'AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555'
local FP2 = '0123456789ABCDEF0123456789ABCDEF01234567'
local TORRC = table.concat({
    'User root',
    'UseBridges 1',
    'ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy',
    'Bridge obfs4 192.0.2.10:443 ' .. FP1 .. ' cert=abc iat-mode=0',
    'Bridge obfs4 198.51.100.20:8443 ' .. FP2 .. ' cert=def iat-mode=0',
    'Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72',
    'StrictNodes 1',
}, '\n') .. '\n'

test('country ids are stable, distinct and in range', function()
    eq(L.country_id('AA'), 920028); eq(L.country_id('ZZ'), 920728)
    eq(L.country_id('de'), L.country_id('DE'))
    local seen = {}
    for a = 65, 90 do for b = 65, 90 do
        local id = L.country_id(string.char(a, b))
        if seen[id] then error('collision ' .. id) end
        seen[id] = true
    end end
end)

test('bridge ids never overlap country ids', function()
    eq(L.bridge_id('00000' .. FP1:sub(6)), 1000000)
    eq(L.bridge_id('FFFFF' .. FP1:sub(6)), 2048575)
end)

test('exit peers check only the selected countries in manual mode', function()
    local peers, ids = L.exit_peers(COUNTRIES, '1', 'at tr')
    eq(#peers, 3); eq(peers[2].name, 'Germany'); eq(peers[2].location, 'DE')
    eq(#ids, 2); eq(ids[1], L.country_id('AT')); eq(ids[2], L.country_id('TR'))
end)

test('no check marks when all exits are allowed', function()
    local _, ids = L.exit_peers(COUNTRIES, '0', 'at tr')
    eq(#ids, 0)
end)

test('countries_for_ids keeps list order, drops unknown ids, nil for none', function()
    eq(L.countries_for_ids(COUNTRIES, {L.country_id('TR'), 5, L.country_id('AT')}), 'at tr')
    eq(L.countries_for_ids(COUNTRIES, {}), nil)
    eq(L.countries_for_ids(COUNTRIES, {12345}), nil)
end)

test('parse_bridges lists obfs4 lines only, enabled and disabled', function()
    local off = TORRC:gsub('Bridge obfs4 198', '#mudi7-tor-off Bridge obfs4 198')
    local b = L.parse_bridges(off)
    eq(#b, 2)
    eq(b[1].enabled, true); eq(b[1].ip, '192.0.2.10'); eq(b[1].port, 443)
    eq(b[2].enabled, false); eq(b[2].id, L.bridge_id(FP2))
end)

test('proc_tcp_key matches the kernel little-endian format', function()
    eq(L.proc_tcp_key('127.0.0.1', 8080), '0100007F:1F90')
    eq(L.proc_tcp_key('192.0.2.10', 443), '0A0200C0:01BB')
end)

test('bridge peers report Connected, Idle and Off', function()
    local proc = table.concat({
        '  sl  local_address rem_address   st tx_queue rx_queue',
        '   0: C601A8C0:D8AC 0A0200C0:01BB 01 00000000:00000000',
        '   1: C601A8C0:DBC0 146433C6:20FB 06 00000000:00000000',
    }, '\n')
    local peers, ids = L.bridge_peers(TORRC, proc)
    eq(peers[1].name, '(Bridge) 192.0.2.10')
    eq(peers[1].location, 'obfs4 :443 - Connected'); eq(peers[2].location, 'obfs4 :8443 - Idle')
    eq(#ids, 2)
    peers, ids = L.bridge_peers(TORRC:gsub('Bridge obfs4 198', '#mudi7-tor-off Bridge obfs4 198'), proc)
    eq(peers[2].location, 'obfs4 :8443 - Off'); eq(#ids, 1)
end)

test('apply_bridges disables unselected bridges and keeps other lines', function()
    local out, active = L.apply_bridges(TORRC, {L.bridge_id(FP1)})
    eq(active, 1)
    assert(out:find('\nBridge obfs4 192.0.2.10', 1, true), 'first bridge stays active')
    assert(out:find('\n#mudi7-tor-off Bridge obfs4 198.51.100.20', 1, true), 'second bridge disabled')
    assert(out:find('\nBridge snowflake ', 1, true), 'non-obfs4 line untouched')
    assert(out:find('\nUseBridges 1\n', 1, true))
    eq(select(2, out:gsub('\n', '')), select(2, TORRC:gsub('\n', '')), 'line count')
end)

test('apply_bridges re-enables a disabled bridge', function()
    local off = L.apply_bridges(TORRC, {L.bridge_id(FP1)})
    local on = L.apply_bridges(off, {L.bridge_id(FP1), L.bridge_id(FP2)})
    eq(on, TORRC)
end)

test('no selected bridge turns UseBridges off', function()
    local out, active = L.apply_bridges(TORRC, {})
    eq(active, 0)
    assert(out:find('\nUseBridges 0\n', 1, true))
    assert(not out:find('\nBridge obfs4', 1, true))
end)

test('UseBridges is added when torrc has none', function()
    local out = L.apply_bridges(TORRC:gsub('UseBridges 1\n', ''), {L.bridge_id(FP2)})
    assert(out:find('\nUseBridges 1\n$'), out)
end)

test('one list: bridges first, then countries, with both check marks', function()
    local peers, ids = L.peers(COUNTRIES, '1', 'de', TORRC, '')
    eq(#peers, 5)
    eq(peers[1].peer_id, L.bridge_id(FP1)); eq(peers[3].name, 'Austria')
    eq(#ids, 3); eq(ids[3], L.country_id('DE'))
end)

test('bridge names sort before every country name', function()
    local peers = L.peers(COUNTRIES, '0', '', TORRC, '')
    for i = 3, #peers do assert(peers[1].name < peers[i].name and peers[2].name < peers[i].name) end
end)

test('selection_ids matches the ids of the full list without proc_tcp', function()
    local bridges = L.parse_bridges(TORRC)
    local _, full = L.peers(COUNTRIES, '1', 'de', TORRC, '')
    local ids = L.selection_ids(COUNTRIES, '1', 'de', bridges)
    eq(#ids, #full)
    for i = 1, #full do eq(ids[i], full[i]) end
    eq(#L.enabled_bridge_ids(L.parse_bridges(TORRC:gsub('Bridge obfs4 198', '#mudi7-tor-off Bridge obfs4 198'))), 1)
end)

test('split_ids separates bridges from countries', function()
    local b, c = L.split_ids({L.country_id('AT'), L.bridge_id(FP2), L.country_id('ZZ')})
    eq(#b, 1); eq(b[1], L.bridge_id(FP2))
    eq(#c, 2); eq(c[2], 920728)
end)

print(string.format('%d/%d passed', count - failures, count))
os.exit(failures == 0 and 0 or 1)
