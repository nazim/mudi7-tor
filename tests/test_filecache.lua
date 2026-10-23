-- Run: lua tests/test_filecache.lua (Lua 5.1 / LuaJIT and newer)
package.path = './router/?.lua;' .. package.path
local F = require('filecache')

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then print('ok   ' .. name) else failures = failures + 1; print('FAIL ' .. name .. '\n     ' .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or '') .. ' expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end
end

local function fixture()
    local files = {a = {data = 'one', size = 3, mtime = 100}}
    local reads, parses = 0, 0
    local cache = F.new(
        function(p) local f = files[p]; if f then return f.size, f.mtime end end,
        function(p) reads = reads + 1; return files[p] and files[p].data end)
    local function parse(d) parses = parses + 1; return d:upper() end
    return cache, files, parse, function() return reads, parses end
end

test('first get reads and parses', function()
    local cache, _, parse, n = fixture()
    eq(cache.get('a', parse), 'ONE')
    local r, p = n(); eq(r, 1); eq(p, 1)
end)

test('unchanged file is served from the cache', function()
    local cache, _, parse, n = fixture()
    cache.get('a', parse); cache.get('a', parse); cache.get('a', parse)
    local r, p = n(); eq(r, 1); eq(p, 1)
end)

test('changed mtime or size triggers one re-read', function()
    local cache, files, parse, n = fixture()
    cache.get('a', parse)
    files.a.mtime = 101
    eq(cache.get('a', parse), 'ONE')
    files.a.data, files.a.size = 'four', 4
    eq(cache.get('a', parse), 'FOUR')
    local r, p = n(); eq(r, 3); eq(p, 3)
end)

test('missing file returns nil and drops the entry', function()
    local cache, files, parse = fixture()
    cache.get('a', parse)
    files.a = nil
    eq(cache.get('a', parse), nil)
    files.a = {data = 'x', size = 1, mtime = 5}
    eq(cache.get('a', parse), 'X')
end)

test('forget forces a re-read even when stat is unchanged', function()
    local cache, files, parse, n = fixture()
    cache.get('a', parse)
    files.a.data = 'new'
    eq(cache.get('a', parse), 'ONE', 'same stat, cached')
    cache.forget('a')
    eq(cache.get('a', parse), 'NEW')
    local r = n(); eq(r, 2)
end)

test('a parse result of false or nil is cached, not replaced by raw data', function()
    local cache, _, _, n = fixture()
    eq(cache.get('a', function() return false end), false)
    eq(cache.get('a', function() return false end), false)
    local r = n(); eq(r, 1)
end)

test('get without parse returns the raw contents', function()
    local cache = fixture()
    eq(cache.get('a'), 'one')
end)

print(string.format('%d/%d passed', count - failures, count))
os.exit(failures == 0 and 0 or 1)
