-- Diagnostics helpers extracted from pre-split runtime lines 1611-2713.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function collect_player_fields(player)
    local lines = {}
    pcall(function()
        local td = player:get_type_definition()
        if not td then return end
        for _, field in ipairs(td:get_fields()) do
            local name = field:get_name()
            local ftype = field:get_type()
            local type_name = ftype and ftype:get_full_name() or "?"
            if name and (name:find("Spawn") or name:find("spawn")
                    or name:find("Context") or name:find("context")
                    or name:find("ID") or name:find("Id")
                    or name:find("User") or name:find("user")
                    or name:find("Character") or name:find("character")) then
                table.insert(lines, type_name .. " " .. name)
            end
        end
    end)
    state.player_fields = table.concat(lines, "\n")
end

local function collect_player_methods(player)
    local lines = {}
    pcall(function()
        local td = player and player:get_type_definition()
        if not td then return end
        local n = 0
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name() or ""
            if name:find("Context") or name:find("ID") or name:find("Id")
                or name:find("Kind") or name:find("Character") or name:find("Spawn")
                or name:find("Player") then
                table.insert(lines, method_signature(method))
                n = n + 1
                if n >= 50 then break end
            end
        end
    end)
    state.player_methods = table.concat(lines, "\n")
end

local function collect_scene_candidates()
    local patterns = {
        "create", "Create", "spawn", "Spawn", "instantiate", "Instantiate",
        "GameObject", "Prefab", "Resource", "add", "Add",
    }
    local names = {}

    local function append(label, list)
        if #list == 0 then return end
        table.insert(names, label .. ": " .. table.concat(list, ", "))
    end

    append("via.SceneManager", collect_methods_from_type("via.SceneManager", patterns, 30))
    append("via.Scene", collect_methods_from_type("via.Scene", patterns, 30))
    append("via.GameObject", collect_methods_from_type("via.GameObject", patterns, 40))
    append("app.CharacterManager", collect_methods_from_type("app.CharacterManager", patterns, 40))

    state.scene_candidates = table.concat(names, " | ")
end

local function collect_component_summary(go)
    local counts = {}
    local names = {}
    pcall(function()
        local components = go:call("get_Components")
        if not components then return end
        local count = components:call("get_Count") or 0
        for i = 0, math.min(count - 1, 80) do
            pcall(function()
                local comp = components:call("get_Item", i)
                if not comp then return end
                local td = comp:get_type_definition()
                local tname = td and td:get_full_name() or "unknown"
                if not counts[tname] then
                    counts[tname] = true
                    table.insert(names, tname)
                end
            end)
        end
    end)
    state.component_summary = table.concat(names, ", ")
end

local function add_unique(list, value, limit)
    if not value or value == "" then return false end
    value = tostring(value)
    for _, existing in ipairs(list) do
        if existing == value then return false end
    end
    if #list < (limit or 40) then
        table.insert(list, value)
        return true
    end
    return false
end

local function normalize_prefab_path(text)
    if not text or text == "" then return nil end
    text = tostring(text):gsub("\\", "/")
    local bracket = text:match("%[@?([^%]]+%.pfb)%]")
    local direct = text:match("([%w%p%s_%-/]+%.pfb)")
    local path = bracket or direct
    if not path then return nil end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    path = path:gsub("^natives/%w%w%w/", "")
    return path
end

local DEFAULT_GRACE_PREFAB_PATHS = {
    "character/ch/ch01/0100/01/ch0100_01_000.pfb",
    "character/ch/ch01/0100/01/ch0100_01_001.pfb",
    "character/ch/ch01/0100/01/ch0100_01_003.pfb",
    "character/ch/ch01/0100/01/ch0100_01_004.pfb",
    "character/ch/ch01/0100/01/ch0100_01_005.pfb",
    "character/ch/ch01/0100/01/ch0100_01_006.pfb",
    "character/ch/ch01/0100/01/ch0100_01_007.pfb",
    "character/ch/ch01/0100/01/ch0100_01_008.pfb",
    "character/ch/ch01/0100/01/ch0100_01_009.pfb",
    "character/ch/ch01/0100/01/ch0100_01_010.pfb",
    "character/ch/ch01/0100/01/ch0100_01_100.pfb",
    "character/ch/ch01/0100/01/ch0100_01_102.pfb",
}

local DEFAULT_GRACE_RESOURCE_PATHS = {
    "natives/stm/character/ch/ch01/0100/01/ch0100_01_000.pfb.18",
    "natives/stm/character/ch/ch01/0100/01/ch0100_01_001.pfb.18",
    "natives/stm/character/ch/ch01/0100/01/ch0100_01_010.pfb.18",
    "natives/stm/character/ch/ch01/0100/01/ch0100_01_100.pfb.18",
    "natives/stm/character/ch/ch01/0100/01/ch0100_01_102.pfb.18",
    "natives/stm/character/ch/ch01/0100/01/00/ch0100_01_00.mesh.250925211",
    "natives/stm/character/ch/ch01/0100/01/00/ch0100_01_00_00.mdf2.51",
    "natives/stm/character/ch/ch01/0100/01/01/ch0100_01_01.mesh.250925211",
    "natives/stm/character/ch/ch01/0100/01/01/ch0100_01_01_00.mdf2.51",
    "natives/stm/animation/ch/ch01/ch0100/motbank/ch0100.motbank.4",
    "natives/stm/animation/ch/ch01/ch0100/motbank/ch0100fps.motbank.4",
}

local function resource_path_variants(path)
    local variants = {}
    local function add(value)
        if not value or value == "" then return end
        value = tostring(value):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
        add_unique(variants, value, 32)
    end

    local raw = tostring(path or "")
    local no_native = raw:gsub("\\", "/"):gsub("^natives/%w%w%w/", "")
    local no_version = no_native:gsub("%.pfb%.%d+%.x64$", ".pfb"):gsub("%.pfb%.%d+$", ".pfb")
    local no_ext = no_version:gsub("%.pfb$", "")

    add(raw)
    add(no_native)
    add(no_version)
    add("natives/stm/" .. no_version)
    add(no_version .. ".18")
    add("natives/stm/" .. no_version .. ".18")
    add(no_ext)
    add("natives/stm/" .. no_ext)

    local lower_count = #variants
    for i = 1, lower_count do
        add(tostring(variants[i]):lower())
    end
    return variants
end

local function generic_resource_path_variants(path)
    local variants = {}
    local function add(value)
        if not value or value == "" then return end
        value = tostring(value):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
        add_unique(variants, value, 48)
    end

    local raw = tostring(path or ""):gsub("\\", "/")
    local no_native = raw:gsub("^natives/%w%w%w/", "")
    local no_version = no_native:gsub("%.%d+%.x64$", ""):gsub("%.%d+$", "")

    add(raw)
    add(no_native)
    add(no_version)
    add("natives/stm/" .. no_version)
    add("natives/stm/" .. no_native)

    local lower_count = #variants
    for i = 1, lower_count do
        add(tostring(variants[i]):lower())
    end
    return variants
end

local function normalize_resource_path(text)
    if not text or text == "" then return nil end
    text = tostring(text):gsub("\\", "/")
    for _, ext in ipairs({"pfb", "mesh", "mdf2", "motbank", "user", "chain", "rcol", "tex"}) do
        local p = text:match("([%w_%-/%.]+%." .. ext .. "%.%d+)")
        if p then return p:gsub("^natives/%w%w%w/", "") end
        p = text:match("([%w_%-/%.]+%." .. ext .. ")")
        if p then return p:gsub("^natives/%w%w%w/", "") end
    end
    return nil
end

local function resource_extension(path)
    local lower = tostring(path or ""):lower()
    for _, ext in ipairs({"pfb", "mesh", "mdf2", "motbank", "user", "chain", "rcol", "tex"}) do
        if lower:find("%." .. ext, 1, false) then return ext end
    end
    return ""
end

local RESOURCE_TYPE_CANDIDATES = {
    pfb = {"via.Prefab"},
    mesh = {"via.render.Mesh", "via.render.MeshResource"},
    mdf2 = {"via.render.Material", "via.render.MaterialResource"},
    motbank = {"via.motion.MotionBank", "via.motion.MotionBankResource"},
    user = {"via.UserData", "via.userdata.UserData"},
    chain = {"via.physics.ChainResource", "via.ChainResource"},
    rcol = {"via.physics.RcolResource", "via.physics.RCOLResource"},
    tex = {"via.render.Texture", "via.render.TextureResource"},
}

local function try_create_resource_matrix(paths, max_paths)
    local rows = {}
    for _, input in ipairs(paths or {}) do
        if #rows >= (max_paths or 12) then break end
        local ext = resource_extension(input)
        local type_candidates = RESOURCE_TYPE_CANDIDATES[ext] or {"via.Resource"}
        local row = {
            input = safe_string(input),
            extension = ext,
            ok = false,
            found_type = "",
            found_path = "",
            attempts = {},
        }
        for _, type_name in ipairs(type_candidates) do
            local type_exists = false
            pcall(function() type_exists = sdk.find_type_definition(type_name) ~= nil end)
            for _, candidate_path in ipairs(generic_resource_path_variants(input)) do
                local attempt = {
                    type = type_name,
                    type_exists = type_exists,
                    path = candidate_path,
                    ok = false,
                    error = type_exists and "" or "type not found",
                }
                if type_exists then
                    local resource = nil
                    local ok_create, err_create = pcall(function()
                        resource = sdk.create_resource(type_name, candidate_path)
                    end)
                    attempt.ok = ok_create and resource ~= nil
                    attempt.error = ok_create and (resource and "" or "nil") or safe_string(err_create)
                    attempt.value = safe_string(resource)
                    attempt.value_type = trace_type_name(resource)
                    if attempt.ok then
                        row.ok = true
                        row.found_type = type_name
                        row.found_path = candidate_path
                        table.insert(row.attempts, attempt)
                        break
                    end
                end
                table.insert(row.attempts, attempt)
                if #row.attempts >= 18 then break end
            end
            if row.ok or #row.attempts >= 18 then break end
        end
        table.insert(rows, row)
    end
    return rows
end

local function is_effect_prefab_path(path)
    if not path then return false end
    local lower = tostring(path):lower():gsub("\\", "/")
    return lower:find("^vfx/")
        or lower:find("/vfx/")
        or lower:find("epv_")
        or lower:find("epvc")
        or lower:find("effect")
end

local function is_character_prefab_path(path)
    if not path or is_effect_prefab_path(path) then return false end
    local lower = tostring(path):lower():gsub("\\", "/")
    return lower:find("cp_a100")
        or lower:find("a100")
        or lower:find("player")
        or lower:find("character")
        or lower:find("chara")
end

local function path_from_managed_value(value)
    if value == nil then return nil end
    if type(value) == "string" then
        return normalize_prefab_path(value)
    end
    if type(value) ~= "userdata" and type(value) ~= "table" then return nil end

    local text = nil
    for _, method in ipairs({"get_Path", "ToString", "get_Name"}) do
        pcall(function()
            if not text and value.call then
                local result = value:call(method)
                if result then text = tostring(result) end
            end
        end)
        local path = normalize_prefab_path(text)
        if path then return path end
    end
    return nil
end

local function is_prefab_object(value)
    if not value or (type(value) ~= "userdata" and type(value) ~= "table") then return false end
    local ok, result = pcall(function()
        if not value.get_type_definition then return false end
        local td = value:get_type_definition()
        if not td then return false end
        local name = td:get_full_name()
        return name == "via.Prefab"
    end)
    return ok and result
end

local function collect_prefab_hints_from_object(label, obj, lines, paths, objects)
    if not obj or not obj.get_type_definition then return end

    pcall(function()
        local td = obj:get_type_definition()
        if not td then return end
        for _, field in ipairs(td:get_fields()) do
            local fname = field:get_name() or ""
            local ftype = field:get_type()
            local tname = ftype and ftype:get_full_name() or ""
            local interesting = fname:find("Prefab") or fname:find("prefab")
                or fname:find("Pfb") or fname:find("pfb")
                or fname:find("Resource") or fname:find("resource")
                or tname:find("Prefab") or tname:find("Resource")
            if interesting then
                local value = nil
                pcall(function() value = obj:get_field(fname) end)
                local path = path_from_managed_value(value)
                if path then
                    local prefix = is_effect_prefab_path(path) and "effect-only " or ""
                    if is_character_prefab_path(path) then
                        add_unique(paths, path, 24)
                    end
                    add_unique(lines, prefix .. label .. "." .. fname .. " -> " .. path, 24)
                end
                if is_prefab_object(value) and not is_effect_prefab_path(path) then
                    table.insert(objects, { label = label .. "." .. fname, prefab = value })
                end
            end
        end
    end)

    pcall(function()
        local td = obj:get_type_definition()
        if not td then return end
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name() or ""
            local ret = method:get_return_type()
            local ret_name = ret and ret:get_full_name() or ""
            local interesting = name:find("get_") == 1
                and (name:find("Prefab") or name:find("prefab") or name:find("Resource") or ret_name:find("Prefab"))
                and method:get_num_params() == 0
            if interesting then
                local value = nil
                pcall(function() value = obj:call(name) end)
                local path = path_from_managed_value(value)
                if path then
                    local prefix = is_effect_prefab_path(path) and "effect-only " or ""
                    if is_character_prefab_path(path) then
                        add_unique(paths, path, 24)
                    end
                    add_unique(lines, prefix .. label .. ":" .. name .. "() -> " .. path, 24)
                end
                if is_prefab_object(value) and not is_effect_prefab_path(path) then
                    table.insert(objects, { label = label .. ":" .. name .. "()", prefab = value })
                end
            end
        end
    end)
end

local function collect_prefab_hints(refs)
    local lines, paths, objects = {}, {}, {}
    if refs and refs.valid then
        collect_prefab_hints_from_object("PlayerContext", refs.player, lines, paths, objects)
        collect_prefab_hints_from_object("PlayerGO", refs.go, lines, paths, objects)
        pcall(function()
            local components = refs.go:call("get_Components")
            if not components then return end
            local count = components:call("get_Count") or 0
            for i = 0, math.min(count - 1, 90) do
                pcall(function()
                    local comp = components:call("get_Item", i)
                    if not comp then return end
                    local td = comp:get_type_definition()
                    local label = td and td:get_full_name() or ("Component" .. tostring(i))
                    collect_prefab_hints_from_object(label, comp, lines, paths, objects)
                end)
            end
        end)
    end

    state.prefab_hint_paths = paths
    state.prefab_hint_objects = objects
    state.prefab_hints = table.concat(lines, "\n")
end

local function type_static_lines(type_name, limit)
    local lines = {}
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then
            table.insert(lines, type_name .. ": type not found")
            return
        end
        local n = 0
        for _, field in ipairs(td:get_fields()) do
            if field:is_static() then
                local name = field:get_name()
                local value = nil
                pcall(function() value = field:get_data(nil) end)
                if value ~= nil then
                    table.insert(lines, type_name .. "." .. safe_string(name) .. "=" .. safe_string(value))
                    n = n + 1
                end
                if n >= (limit or 16) then break end
            end
        end
        if n == 0 then table.insert(lines, type_name .. ": no static enum fields visible") end
    end)
    return lines
end

local function get_static_field_value(type_name, names)
    local value = nil
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then return end
        for _, field in ipairs(td:get_fields()) do
            if not field:is_static() then goto continue end
            local fname = field:get_name() or ""
            for _, want in ipairs(names) do
                if fname == want or fname == ("<" .. want .. ">k__BackingField") then
                    pcall(function() value = field:get_data(nil) end)
                    return
                end
            end
            ::continue::
        end
    end)
    return value
end

local function describe_value_for_probe(label, value)
    local parts = { label .. "=" .. safe_string(value) }
    pcall(function()
        if value and value.get_type_definition then
            local td = value:get_type_definition()
            table.insert(parts, "type=" .. (td and td:get_full_name() or "?"))
        end
    end)
    return table.concat(parts, " ")
end

local function get_parent_type_definition(td)
    if not td then return nil end
    local parent = nil
    local ok_parent = pcall(function() parent = td:get_parent_type() end)
    if not ok_parent or not parent then
        ok_parent = pcall(function() parent = td:get_parent_type_definition() end)
    end
    if not ok_parent then return nil end
    return parent
end

local function object_field_summary(label, obj, limit)
    local lines = {}
    if not obj or not obj.get_type_definition then return lines end
    pcall(function()
        local td = obj:get_type_definition()
        table.insert(lines, label .. " type=" .. (td and td:get_full_name() or "?"))
        if not td then return end
        local n = 0
        for _, field in ipairs(td:get_fields()) do
            local name = field:get_name() or ""
            local ftype = field:get_type()
            local type_name = ftype and ftype:get_full_name() or "?"
            local interesting = name:find("Context") or name:find("Kind") or name:find("Character")
                or name:find("Chara") or name:find("Player") or name:find("Montage")
                or name:find("Spawn") or name:find("Prefab") or name:find("Resource")
                or type_name:find("Context") or type_name:find("Kind") or type_name:find("Prefab")
            if interesting then
                local value = nil
                pcall(function() value = obj:get_field(name) end)
                local path = path_from_managed_value(value)
                local text = path or safe_string(value)
                table.insert(lines, "  " .. type_name .. " " .. name .. " = " .. text)
                n = n + 1
                if n >= (limit or 28) then break end
            end
        end
    end)
    return lines
end

local function object_all_field_summary(label, obj, limit)
    local lines = {}
    if not obj or not obj.get_type_definition then return lines end
    pcall(function()
        local td = obj:get_type_definition()
        table.insert(lines, label .. " all-fields type=" .. (td and td:get_full_name() or "?"))
        local n = 0
        local depth = 0
        local seen = {}
        while td and depth < 8 do
            local type_name_for_level = td:get_full_name() or "?"
            if seen[type_name_for_level] then break end
            seen[type_name_for_level] = true
            if depth > 0 then
                table.insert(lines, label .. " base-fields type=" .. type_name_for_level)
            end
            for _, field in ipairs(td:get_fields()) do
                local name = field:get_name() or ""
                local ftype = field:get_type()
                local type_name = ftype and ftype:get_full_name() or "?"
                local value = nil
                pcall(function() value = obj:get_field(name) end)
                table.insert(lines, "  " .. type_name .. " " .. name .. " = " .. safe_string(value))
                n = n + 1
                if n >= (limit or 32) then return end
            end

            local parent = get_parent_type_definition(td)
            if not parent then break end
            td = parent
            depth = depth + 1
        end
    end)
    return lines
end

local function set_fields_by_type_or_name(obj, target_type_name, name_markers, value, label, lines)
    if not obj or not obj.get_type_definition then return 0 end
    local changed = 0
    pcall(function()
        local td = obj:get_type_definition()
        local depth = 0
        local seen = {}
        while td and depth < 8 do
            local level_name = td:get_full_name() or "?"
            if seen[level_name] then break end
            seen[level_name] = true

            for _, field in ipairs(td:get_fields()) do
                local name = field:get_name() or ""
                local ftype = field:get_type()
                local type_name = ftype and ftype:get_full_name() or ""
                local matches = type_name == target_type_name
                if not matches then
                    for _, marker in ipairs(name_markers or {}) do
                        if name:find(marker, 1, true) then
                            matches = true
                            break
                        end
                    end
                end

                if matches then
                    local before = nil
                    pcall(function() before = obj:get_field(name) end)
                    local ok_set, err = pcall(function() obj:set_field(name, value) end)
                    local after = nil
                    pcall(function() after = obj:get_field(name) end)
                    table.insert(lines, label .. " set " .. level_name .. "." .. name .. " [" .. type_name .. "] " .. safe_string(before) .. " -> " .. safe_string(after) .. " = " .. (ok_set and "ok" or ("ERR " .. safe_string(err))))
                    if ok_set then changed = changed + 1 end
                end
            end

            td = get_parent_type_definition(td)
            depth = depth + 1
        end
    end)
    table.insert(lines, label .. " changed_fields=" .. tostring(changed))
    return changed
end

local function set_named_field_for_probe(obj, name, value, label, lines)
    if not obj then
        table.insert(lines, label .. " set " .. name .. " skipped: object nil")
        return false
    end

    local before = nil
    pcall(function() before = obj:get_field(name) end)
    local ok_set, err_set = pcall(function() obj:set_field(name, value) end)
    local after = nil
    pcall(function() after = obj:get_field(name) end)
    table.insert(lines, label .. " set " .. name .. " " .. safe_string(before) .. " -> " .. safe_string(after) .. " = " .. (ok_set and "ok" or ("ERR " .. safe_string(err_set))))
    return ok_set
end

local function object_method_summary(label, obj, patterns, limit)
    local lines = {}
    pcall(function()
        local td = obj and obj:get_type_definition()
        if not td then return end
        local n = 0
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name() or ""
            for _, pattern in ipairs(patterns or {}) do
                if name:find(pattern) then
                    table.insert(lines, label .. "." .. method_signature(method))
                    n = n + 1
                    break
                end
            end
            if n >= (limit or 32) then break end
        end
    end)
    return lines
end

local function object_all_method_summary(label, obj, limit)
    local lines = {}
    pcall(function()
        local td = obj and obj:get_type_definition()
        if not td then return end
        local n = 0
        for _, method in ipairs(td:get_methods()) do
            table.insert(lines, label .. "." .. method_signature(method))
            n = n + 1
            if n >= (limit or 48) then break end
        end
    end)
    return lines
end

local function collect_character_spawn_diagnostics(refs)
    local lines = {}
    for _, type_name in ipairs({
        "app.ContextID",
        "app.CharacterKindID",
        "app.MontageID",
        "app.CharacterUsePurposeFlag",
    }) do
        for _, line in ipairs(type_static_lines(type_name, 20)) do
            table.insert(lines, line)
        end
    end

    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_diagnostics = table.concat(lines, "\n")
        return
    end

    if refs and refs.player then
        for _, line in ipairs(object_field_summary("PlayerContext", refs.player, 40)) do
            table.insert(lines, line)
        end
    end
    state.character_spawn_diagnostics = table.concat(lines, "\n")
end

local function dump_runtime_diagnostics()
    if now() < state.last_diagnostic_dump + 2.0 then return end
    state.last_diagnostic_dump = now()

    local refs = get_local_player_refs()
    if refs.valid and refs.go then
        collect_clone_candidates(refs.go)
        collect_component_summary(refs.go)
        collect_player_fields(refs.player)
        collect_player_methods(refs.player)
    end
    collect_prefab_hints(refs)
    collect_character_spawn_diagnostics(refs)
    collect_scene_candidates()
    collect_method_signatures()

    pcall(function()
        json.dump_file(DATA_PREFIX .. "runtime_diagnostics.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            player_valid = refs.valid,
            player_name = refs.name or "",
            clone_candidates = state.clone_candidates,
            scene_candidates = state.scene_candidates,
            component_summary = state.component_summary,
            method_signatures = state.method_signatures,
            player_fields = state.player_fields,
            player_methods = state.player_methods,
            prefab_hints = state.prefab_hints,
            prefab_hint_paths = state.prefab_hint_paths,
            character_spawn_status = state.character_spawn_status,
            character_spawn_diagnostics = state.character_spawn_diagnostics,
            last_spawn_components = state.last_spawn_components,
        })
    end)
end

local function append_iterable_summary(lines, label, obj, limit)
    table.insert(lines, label .. "=" .. safe_string(obj))
    if not obj then return end

    local type_name = ""
    pcall(function()
        if obj.get_type_definition then
            local td = obj:get_type_definition()
            type_name = td and td:get_full_name() or "?"
            table.insert(lines, label .. " type=" .. type_name)
        end
    end)

    local count = nil
    pcall(function() count = obj:call("get_Count") end)
    if count == nil then
        pcall(function() count = obj:get_size() end)
    end
    if count then table.insert(lines, label .. " count=" .. tostring(count)) end

    -- RE Engine dictionary get_Item expects a key, not a numeric index. Do not
    -- probe it as an array; invalid key types can throw noisy native errors.
    if type_name:find("Dictionary", 1, true) then
        return
    end

    local numeric_index_ok = count and not type_name:find("HashSet", 1, true)
    if numeric_index_ok then
        for i = 0, math.min((tonumber(count) or 0) - 1, (limit or 8) - 1) do
            pcall(function()
                local item = nil
                local ok_item = pcall(function()
                    item = obj:call("get_Item", i)
                end)
                if not ok_item or item == nil then
                    pcall(function()
                        item = obj:get_element(i)
                    end)
                end
                table.insert(lines, label .. "[" .. tostring(i) .. "]=" .. probe_summary_text(item))
                for _, line in ipairs(object_field_summary(label .. "[" .. tostring(i) .. "]", item, 18)) do
                    table.insert(lines, line)
                end
            end)
        end
        return
    end

    local direct_iterated = false
    pcall(function()
        for i = 0, (limit or 8) - 1 do
            local moved = obj:call("MoveNext")
            if not moved then break end
            direct_iterated = true
            local item = obj:call("get_Current")
            table.insert(lines, label .. "[" .. tostring(i) .. "]=" .. probe_summary_text(item))
            for _, line in ipairs(object_field_summary(label .. "[" .. tostring(i) .. "]", item, 18)) do
                table.insert(lines, line)
            end
        end
    end)
    if direct_iterated then return end

    pcall(function()
        local iter = obj:call("GetEnumerator")
        if not iter then return end
        for i = 0, (limit or 8) - 1 do
            local moved = iter:call("MoveNext")
            if not moved then break end
            local item = iter:call("get_Current")
            table.insert(lines, label .. "[" .. tostring(i) .. "]=" .. probe_summary_text(item))
            for _, line in ipairs(object_field_summary(label .. "[" .. tostring(i) .. "]", item, 18)) do
                table.insert(lines, line)
            end
        end
    end)
end

local function collect_iterable_values(obj, limit)
    local values = {}
    if not obj then return values end

    pcall(function()
        local iter = obj:call("GetEnumerator")
        if not iter then return end
        for _ = 1, (limit or 16) do
            local moved = iter:call("MoveNext")
            if not moved then break end
            local item = iter:call("get_Current")
            if item ~= nil then
                pcall(function()
                    if item.add_ref then item = item:add_ref() end
                end)
                table.insert(values, item)
            end
        end
    end)
    if #values > 0 then return values end

    local type_name = trace_type_name(obj)
    if type_name:find("Dictionary", 1, true) or type_name:find("HashSet", 1, true) then
        return values
    end

    local count = trace_count(obj)
    for i = 0, math.min(count - 1, (limit or 16) - 1) do
        local item = trace_item(obj, i)
        if item ~= nil then
            pcall(function()
                if item.add_ref then item = item:add_ref() end
            end)
            table.insert(values, item)
        end
    end
    return values
end

local function append_safe_call_summary(lines, label, obj, call_names)
    if not obj then return end
    for _, call_name in ipairs(call_names or {}) do
        local ok, result = pcall(function()
            return obj:call(call_name)
        end)
        local text = ok
            and ((type(re9mp_probe_value_text) == "function" and re9mp_probe_value_text(result)) or safe_string(result))
            or ("ERR " .. safe_string(result))
        table.insert(lines, label .. ":" .. call_name .. " -> " .. text)
    end
end

function probe_summary_text(value)
    if type(re9mp_probe_value_text) == "function" then
        return re9mp_probe_value_text(value)
    end
    return safe_string(value)
end

function re9mp_probe_value_text(value)
    if value == nil then return "" end
    local path = path_from_managed_value(value)
    if path then return path end

    local type_name = trace_type_name(value)
    local text = nil
    pcall(function()
        if value and value.call then
            local result = value:call("ToString")
            if result ~= nil then text = tostring(result) end
        end
    end)
    if not text or text == "" then
        pcall(function()
            if value and value.call then
                local result = value:call("get_Name")
                if result ~= nil then text = tostring(result) end
            end
        end)
    end
    if not text or text == "" then text = safe_string(value) end
    if type_name ~= "" and text ~= type_name then
        return text .. " [" .. type_name .. "]"
    end
    return text
end

function re9mp_append_targeted_field_summary(lines, label, obj, markers, limit)
    if not obj or not obj.get_type_definition then
        table.insert(lines, label .. " targeted-fields skipped: nil or unmanaged")
        return
    end

    local inserted = 0
    pcall(function()
        local td = obj:get_type_definition()
        local depth = 0
        local seen = {}
        while td and depth < 8 do
            local owner_type = td:get_full_name() or "?"
            if seen[owner_type] then break end
            seen[owner_type] = true

            for _, field in ipairs(td:get_fields()) do
                local name = field:get_name() or ""
                local ftype = field:get_type()
                local type_name = ftype and ftype:get_full_name() or "?"
                local matched = false
                for _, marker in ipairs(markers or {}) do
                    if name:find(marker, 1, true) or type_name:find(marker, 1, true) then
                        matched = true
                        break
                    end
                end

                if matched then
                    local value = nil
                    pcall(function() value = obj:get_field(name) end)
                    table.insert(lines, label .. "." .. owner_type .. "." .. name
                        .. " [" .. type_name .. "] = " .. re9mp_probe_value_text(value))
                    inserted = inserted + 1
                    if inserted >= (limit or 96) then return end
                end
            end

            td = get_parent_type_definition(td)
            depth = depth + 1
        end
    end)
    table.insert(lines, label .. " targeted_fields=" .. tostring(inserted))
end

function re9mp_append_spawn_control_identity_summary(lines, label, control, limit)
    table.insert(lines, label .. "=" .. safe_string(control) .. " type=" .. trace_type_name(control))
    append_safe_call_summary(lines, label, control, {
        "app.ICharacterSpawnControl.get_SpawnID()",
        "app.ICharacterSpawnControl.get_ManagedContextID()",
        "app.ICharacterSpawnControl.getAllManagedContextID()",
        "get_HasPermittedSpawn",
    })
    local spawn_id = nil
    local managed_ids = nil
    pcall(function() spawn_id = control and control:call("app.ICharacterSpawnControl.get_SpawnID()") end)
    pcall(function() managed_ids = control and control:call("app.ICharacterSpawnControl.getAllManagedContextID()") end)
    append_iterable_summary(lines, label .. ".ManagedContextIDs", managed_ids, 12)
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if char_mgr and spawn_id then
        for _, call_name in ipairs({
            "isUsedContext(app.ContextID)",
            "getManagedContextID(app.ContextID)",
            "getContextRef(app.ContextID)",
            "getPlayerContextRef(app.ContextID)",
        }) do
            local ok, result = pcall(function()
                return char_mgr:call(call_name, spawn_id)
            end)
            table.insert(lines, label .. ".CharacterManager:" .. call_name
                .. "(" .. probe_summary_text(spawn_id) .. ") -> "
                .. (ok and probe_summary_text(result) or ("ERR " .. safe_string(result))))
        end
    end
    re9mp_append_targeted_field_summary(lines, label, control, {
        "Context", "Managed", "Spawn", "Player", "Control", "Chara", "Character", "ID", "Guid",
    }, limit or 120)
end

local function append_player_context_deep_summary(lines, label, player_context)
    if not player_context then return end
    table.insert(lines, label .. " deep=" .. safe_string(player_context))
    append_safe_call_summary(lines, label, player_context, {
        "get_GameObject",
        "get_Transform",
        "get_Updater",
        "get_IsActivePlayer",
        "get_IsTPSCharacter",
        "get_IsFPSCharacter",
        "get_IsCp_A1Character",
    })

    for _, field_name in ipairs({
        "<Common>k__BackingField",
        "<TPSUnit>k__BackingField",
        "<FPSUnit>k__BackingField",
        "<Cp_A1Unit>k__BackingField",
        "<ContextUnitArray>k__BackingField",
    }) do
        local value = nil
        pcall(function() value = player_context:get_field(field_name) end)
        local unit_label = label .. "." .. field_name
        table.insert(lines, unit_label .. "=" .. safe_string(value))
        append_safe_call_summary(lines, unit_label, value, {
            "get_GameObject",
            "get_Transform",
            "get_Updater",
            "get_Owner",
            "get_Context",
            "get_Parent",
        })
        for _, line in ipairs(object_field_summary(unit_label, value, 32)) do
            table.insert(lines, line)
        end
        for _, line in ipairs(object_method_summary(unit_label, value, {
            "GameObject", "Transform", "Updater", "Owner", "Context", "Parent", "Create", "Initialize", "Setup", "Spawn", "Mesh", "Motion",
        }, 80)) do
            table.insert(lines, line)
        end
    end

    local updater = nil
    pcall(function() updater = player_context:call("get_Updater") end)
    if updater then
        for _, line in ipairs(object_field_summary(label .. ".Updater", updater, 48)) do
            table.insert(lines, line)
        end
        for _, line in ipairs(object_method_summary(label .. ".Updater", updater, {
            "GameObject", "Transform", "Context", "Owner", "Create", "Initialize", "Setup", "Spawn", "Start", "Update", "Mesh", "Motion",
        }, 100)) do
            table.insert(lines, line)
        end
    end
end

local function append_create_setting_summary(lines, label, setting)
    table.insert(lines, label .. "=" .. safe_string(setting))
    if not setting then return end

    for _, line in ipairs(object_all_field_summary(label, setting, 120)) do
        table.insert(lines, line)
    end
    for _, line in ipairs(object_method_summary(label, setting, {
        "Context", "Kind", "Character", "Player", "Spawn", "Pose", "Position", "Rotation", "Chapter", "Create", "Default", "Enable",
    }, 120)) do
        table.insert(lines, line)
    end
end

local function append_level_player_create_controller_summary(lines, label, control)
    if not control then return end

    append_safe_call_summary(lines, label, control, {
        "app.ICharacterSpawnControl.get_SpawnID()",
        "app.ICharacterSpawnControl.get_ManagedContextID()",
        "get_HasPermittedSpawn",
        "app.ICharacterSpawnControl.getAllManagedContextID()",
    })

    for _, field_name in ipairs({
        "_SpawnContextID",
        "_InitControlPlayer",
        "_DefaultPlayer",
        "_OtherInitPlayerArray",
        "EnableOtherInitPlayerArray",
    }) do
        local value = nil
        pcall(function() value = control:get_field(field_name) end)
        local field_label = label .. "." .. field_name
        if tostring(field_name):find("Array", 1, true) then
            append_iterable_summary(lines, field_label, value, 8)
            local count = nil
            if value then
                pcall(function() count = value:call("get_Count") end)
                if count == nil then
                    pcall(function() count = value:get_size() end)
                end
            end
            for i = 0, math.min((tonumber(count) or 0) - 1, 7) do
                local item = nil
                local ok_item = pcall(function() item = value:call("get_Item", i) end)
                if not ok_item or item == nil then
                    pcall(function() item = value:get_element(i) end)
                end
                append_create_setting_summary(lines, field_label .. "[" .. tostring(i) .. "].deep", item)
            end
        else
            append_create_setting_summary(lines, field_label, value)
        end
    end
end

local function append_spawn_data_deep_summary(lines, label, spawn_data)
    if not spawn_data then return end
    table.insert(lines, label .. " deep=" .. safe_string(spawn_data))
    for _, line in ipairs(object_all_field_summary(label, spawn_data, 80)) do
        table.insert(lines, line)
    end
    for _, line in ipairs(object_method_summary(label, spawn_data, {
        "Context", "Kind", "Spawn", "Control", "Group", "Setting", "Transform", "Position", "Rotation", "Resume", "Duplicate", "Owner",
    }, 100)) do
        table.insert(lines, line)
    end

    for _, field_name in ipairs({
        "<SpawnControl>k__BackingField",
        "<SpawnGroup>k__BackingField",
        "_CharacterSettings",
        "<ContextID>k__BackingField",
        "<KindID>k__BackingField",
    }) do
        local value = nil
        pcall(function() value = spawn_data:get_field(field_name) end)
        local nested_label = label .. "." .. field_name
        table.insert(lines, nested_label .. "=" .. safe_string(value))
        for _, line in ipairs(object_all_field_summary(nested_label, value, 80)) do
            table.insert(lines, line)
        end
        for _, line in ipairs(object_method_summary(nested_label, value, {
            "Context", "Kind", "Spawn", "Control", "Group", "Owner", "Request", "Execute", "Create", "Setup", "Initialize", "Update", "Enable",
        }, 120)) do
            table.insert(lines, line)
        end
        if field_name == "<SpawnControl>k__BackingField" then
            append_level_player_create_controller_summary(lines, nested_label, value)
        end
    end
end
