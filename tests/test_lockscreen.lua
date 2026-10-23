-- Run: lua tests/test_lockscreen.lua (Lua 5.1 / LuaJIT and newer)
package.path = './router/?.lua;' .. package.path
local L = require('lockscreen')

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then print('ok   ' .. name) else failures = failures + 1; print('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or '') .. ' expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end
end

local GEOIP = {
    '# comment',
    '16777216,16777471,AU',
    '759309056,759309311,NL',
    '1000000000,1000000255,DE',
}
local function lines(t) local i = 0; return function() i = i + 1; return t[i] end end

test('valid_ipv4 rejects anything but a dotted quad', function()
    eq(L.valid_ipv4('45.66.35.46'), '45.66.35.46')
    eq(L.valid_ipv4('256.1.1.1'), nil)
    eq(L.valid_ipv4('1.2.3'), nil)
    eq(L.valid_ipv4('1.2.3.4"; reboot'), nil)
    eq(L.valid_ipv4(nil), nil)
end)

test('country finds the range and stops early', function()
    eq(L.ip_to_int('45.66.35.46'), 759309102)
    eq(L.country(lines(GEOIP), '45.66.35.46'), 'NL')
    eq(L.country(lines(GEOIP), '1.0.0.5'), 'AU')
    eq(L.country(lines(GEOIP), '20.0.0.1'), nil)
    eq(L.country(lines(GEOIP), '200.0.0.1'), nil)
end)

test('bootstrap_percent reads the last line', function()
    local log = 'Bootstrapped 10% (conn)\nBootstrapped 95% (circ)\nBootstrapped 100% (done): Done\n'
    eq(L.bootstrap_percent(log), 100)
    eq(L.bootstrap_percent('Bootstrapped 45% (x)'), 45)
    eq(L.bootstrap_percent(''), nil)
end)

test('exit_ip trusts only a Tor answer with a valid address', function()
    eq(L.exit_ip('{"IsTor":true,"IP":"45.66.35.46"}'), '45.66.35.46')
    eq(L.exit_ip('{"IsTor":false,"IP":"1.2.3.4"}'), nil)
    eq(L.exit_ip('{"IsTor":true,"IP":"x\\"y"}'), nil)
    eq(L.exit_ip(nil), nil)
end)

test('text covers connecting and connected states', function()
    eq(L.text(45), 'TOR Connecting 45%')
    eq(L.text(nil), 'TOR Connecting 0%')
    eq(L.text(100, 'NL', '45.66.35.46'), 'TOR Connected NL 45.66.35.46')
    eq(L.text(100, nil, nil), 'TOR Connected')
    eq(L.text(100, 'nl"', 'bad'), 'TOR Connected')
end)

test('with_signature replaces only the SIGNATURE line', function()
    local g = 'ALWAYS_ON 0\nPASSCODE "1234"\nSIGNATURE "Someone"\nWALLPAPER_PAIR 1\n'
    local out = L.with_signature(g, 'TOR Connected NL 45.66.35.46')
    eq(out, 'ALWAYS_ON 0\nPASSCODE "1234"\nSIGNATURE "TOR Connected NL 45.66.35.46"\nWALLPAPER_PAIR 1\n')
end)

test('with_signature appends when missing and refuses unsafe text', function()
    eq(L.with_signature('ALWAYS_ON 0\n', 'TOR'), 'ALWAYS_ON 0\nSIGNATURE "TOR"\n')
    assert(not pcall(L.with_signature, '', 'a"b'))
    assert(not pcall(L.with_signature, '', 'a\\nb'))
end)

print(string.format('%d/%d passed', count - failures, count))
os.exit(failures == 0 and 0 or 1)
