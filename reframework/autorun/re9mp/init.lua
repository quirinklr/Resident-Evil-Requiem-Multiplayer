-- RE9MP runtime entrypoint.
-- This keeps REFramework autorun stable while the old monolith is split into modules.

local M = {}

local function write_init_error(message)
    pcall(function()
        json.dump_file("re9mp/bootstrap_error.json", {
            ok = false,
            message = tostring(message or ""),
            phase = "init",
            time_ms = math.floor((os.clock() or 0) * 1000.0),
        })
    end)
end

local function script_dir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*[\\/])[^\\/]*$") or ""
end

local function load_legacy_runtime()
    local dir = script_dir()
    local candidates = {
        dir .. "legacy_runtime.lua",
        "reframework/autorun/re9mp/legacy_runtime.lua",
        "autorun/re9mp/legacy_runtime.lua",
        "re9mp/legacy_runtime.lua",
    }
    local last_error = ""
    for _, path in ipairs(candidates) do
        local ok, result = pcall(function()
            return dofile(path)
        end)
        if ok then
            pcall(function()
                json.dump_file("re9mp/bootstrap_error.json", {
                    ok = true,
                    loaded = path,
                    phase = "init",
                    time_ms = math.floor((os.clock() or 0) * 1000.0),
                })
            end)
            return true, result
        end
        last_error = tostring(result)
    end
    return false, last_error
end

local ok, result = load_legacy_runtime()
if not ok then
    write_init_error(result)
    error("RE9MP init failed: " .. tostring(result))
end

M.loaded = true
return M
