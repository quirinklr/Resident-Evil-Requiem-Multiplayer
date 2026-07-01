-- Transitional loader for the split RE9MP Lua runtime.
--
-- The legacy runtime still relies on top-level local scope shared across the
-- original file. To avoid a risky semantic rewrite, the extracted chunks are
-- concatenated and executed as one Lua chunk. New cleanup work should continue
-- moving focused subsystems from these chunks into real modules.

local chunk_paths = {
    "core/legacy_00_state_and_snapshots.lua",
    "tracing/legacy_10_trace_hooks.lua",
    "tracing/legacy_20_diagnostics_helpers.lua",
    "tracing/legacy_21_character_and_visual_probes.lua",
    "spawn/legacy_30_context_and_controller_helpers.lua",
    "spawn/legacy_40_load_phase_injection.lua",
    "spawn/legacy_50_visual_foundation.lua",
    "spawn/legacy_51_mesh_copy_and_registration.lua",
    "spawn/legacy_52_lit_control_clone.lua",
    "tracing/legacy_60_ownership_recipe.lua",
    "archive/legacy_70_archived_prefab_and_spawn_probes.lua",
    "runtime/legacy_80_commands_ui_callbacks.lua",
}

local base_paths = {
    "reframework/autorun/re9mp/",
    "autorun/re9mp/",
    "re9mp/",
}

local function read_all(path)
    local file, open_err = io.open(path, "rb")
    if not file then return nil, open_err end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_loader_error(message)
    pcall(function()
        json.dump_file("re9mp/bootstrap_error.json", {
            ok = false,
            phase = "legacy_runtime_loader",
            message = tostring(message or ""),
            time_ms = math.floor((os.clock() or 0) * 1000.0),
        })
    end)
end

local function load_from_base(base)
    local parts = {}
    for _, path in ipairs(chunk_paths) do
        local full_path = base .. path
        local content, err = read_all(full_path)
        if not content then
            return nil, "failed to read " .. full_path .. ": " .. tostring(err)
        end
        parts[#parts + 1] = "\n-- chunk: " .. path .. "\n"
        parts[#parts + 1] = content
    end
    return table.concat(parts, "\n")
end

local source = nil
local selected_base = nil
local last_error = ""
for _, base in ipairs(base_paths) do
    local content, err = load_from_base(base)
    if content then
        source = content
        selected_base = base
        break
    end
    last_error = err
end

if not source then
    write_loader_error(last_error)
    error("RE9MP legacy runtime chunks not found: " .. tostring(last_error))
end

local loader = load or loadstring
if not loader then
    write_loader_error("Lua load/loadstring unavailable")
    error("RE9MP legacy runtime loader requires load or loadstring")
end

local chunk, compile_err = loader(source, "@" .. selected_base .. "legacy_runtime_concat.lua")
if not chunk then
    write_loader_error(compile_err)
    error("RE9MP legacy runtime compile failed: " .. tostring(compile_err))
end

local ok, result = pcall(chunk)
if not ok then
    write_loader_error(result)
    error("RE9MP legacy runtime execution failed: " .. tostring(result))
end

return result
