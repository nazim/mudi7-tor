-- Re-reads and re-parses a file only when its size or mtime changed.
-- stat(path) -> size, mtime (or nil when missing); read(path) -> contents.
-- One cache per nginx worker; apply() invalidates its own worker at once and
-- the others notice the changed stat on their next request.
local M = {}

function M.new(stat, read)
    local entries = {}
    local cache = {}

    function cache.get(path, parse)
        local size, mtime = stat(path)
        if not size then
            entries[path] = nil
            return nil
        end
        local e = entries[path]
        if e and e.size == size and e.mtime == mtime then return e.value end
        local data = read(path)
        if not data then
            entries[path] = nil
            return nil
        end
        local value = data
        if parse then value = parse(data) end
        entries[path] = {size = size, mtime = mtime, value = value}
        return value
    end

    function cache.forget(path)
        entries[path] = nil
    end

    return cache
end

return M
