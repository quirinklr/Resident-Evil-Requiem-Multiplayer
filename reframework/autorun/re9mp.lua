-- RE9 Multiplayer MVP bootstrap.
-- Keep this file small: runtime code lives under re9mp/.

local function write_bootstrap_error(message)
    pcall(function()
        json.dump_file("re9mp/bootstrap_error.json", {
            ok = false,
            message = tostring(message or ""),
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

local function run_first_existing(paths)
    local last_error = ""
    for _, path in ipairs(paths) do
        local ok, result = pcall(function()
            return dofile(path)
        end)
        if ok then
            return true, result
        end
        last_error = tostring(result)
    end
    return false, last_error
end

local dir = script_dir()
local ok, err = run_first_existing({
    dir .. "re9mp/init.lua",
    "reframework/autorun/re9mp/init.lua",
    "autorun/re9mp/init.lua",
    "re9mp/init.lua",
})

if not ok then
    write_bootstrap_error(err)
    error("RE9MP bootstrap failed: " .. tostring(err))
end
