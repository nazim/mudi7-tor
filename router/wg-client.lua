-- Installed as /usr/lib/oui-httpd/rpc/wg-client by install.sh.
-- GL.iNet's wg-client is a C module (wg-client.so). oui/rpc.lua loads this
-- Lua file first and sends every method it does not define to the C module,
-- so only the two list methods the touchscreen reads are defined here.
local cjson = require('cjson')
local rpc = require('oui.rpc')
local state = dofile('/usr/lib/mudi7-tor/tor-state.lua')

-- Same request oui/rpc.lua's glc_call makes; calling rpc.call() instead
-- would load this file again.
local function glc(method, args)
    local res = ngx.location.capture('/cgi-bin/glc', {
        method = ngx.HTTP_POST,
        body = cjson.encode({object = 'wg-client', method = method, args = args or {}})
    })
    if res.status ~= ngx.HTTP_OK then return rpc.ERROR_CODE_INTERNAL_ERROR end
    local code = tonumber(res.body:match('(-?%d+)'))
    if code ~= rpc.ERROR_CODE_NONE then return code end
    return cjson.decode(res.body:match('%d+ (.*)'))
end

local M = {}

function M.get_group_list(p)
    local result = glc('get_group_list', p)
    if not state.is_screen() or type(result) ~= 'table' or type(result.groups) ~= 'table' then
        return result
    end
    -- gl_screen hides groups whose peer_count is 0 and fails the whole list
    -- when a group has no integer peer_count (FUN_00205790).
    table.insert(result.groups, {group_name = 'Tor', group_id = state.group,
                                 group_type = 2, peer_count = state.count(), show = true})
    return result
end

function M.get_config_list(p)
    local group = type(p) == 'table' and tonumber(p.group_id)
    if state.is_screen() and group == state.group then
        return {peers = state.array((state.peers()))}
    end
    return glc('get_config_list', p)
end

return M
