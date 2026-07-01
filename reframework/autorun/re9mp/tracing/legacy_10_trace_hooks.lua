-- Trace hook helpers extracted from pre-split runtime lines 629-1610.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function collect_clone_candidates(go)
    local names = {}
    pcall(function()
        local td = go:get_type_definition()
        if not td then return end
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name()
            if name and (name:find("clone") or name:find("Clone")
                    or name:find("copy") or name:find("Copy")
                    or name:find("instantiate") or name:find("Instantiate")
                    or name:find("create") or name:find("Create")) then
                table.insert(names, name)
            end
        end
    end)
    state.clone_candidates = table.concat(names, ", ")
end

local function collect_methods_from_type(type_name, patterns, limit)
    local names = {}
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then return end
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name()
            if name then
                for _, pattern in ipairs(patterns) do
                    if name:find(pattern) then
                        table.insert(names, name)
                        break
                    end
                end
            end
            if #names >= limit then break end
        end
    end)
    return names
end

local function method_signature(method)
    local parts = {}
    local ok = pcall(function()
        local ret = method:get_return_type()
        local ret_name = ret and ret:get_full_name() or "?"
        table.insert(parts, ret_name .. " " .. method:get_name() .. "(")
        local ptxt = {}
        local param_types = method:get_param_types()
        local param_names = method:get_param_names()
        if param_types then
            for i, ptype in ipairs(param_types) do
                local type_name = ptype and ptype:get_full_name() or "?"
                local pname = (param_names and param_names[i]) or ("arg" .. tostring(i))
                table.insert(ptxt, type_name .. " " .. pname)
            end
        end
        table.insert(parts, table.concat(ptxt, ", "))
        table.insert(parts, ")")
    end)
    if not ok then
        return method:get_name() .. "(?)"
    end
    return table.concat(parts, "")
end

local function collect_method_signatures()
    local targets = {
        {"app.CharacterManager", {
            "requestSpawn", "requestInstantiateMontage", "getSpawnDataRef", "getSpawnedContextRefList",
            "getSpawnableContextList", "getPlayerContextID", "getPlayerContextRef", "getPlayerContextRefFast",
            "getContextRef", "getManagedContextID", "readyContext", "registerPlayerContextIDList",
            "registerSpawnData", "unregisterSpawnData", "registerSpawnGroup", "unregisterSpawnGroup",
            "storeContext", "restoreContext", "unregisterContext", "clearContext", "getCharacterContextFactory",
            "getAndRequestSpawnOwner", "clearSpawnOwner", "makeSpawnControlBackupData", "getSpawnControlBackup",
        }},
        {"app.CharacterSpawnData", {".ctor", "duplicate"}},
        {"app.PlayerSpawnData", {".ctor", "duplicate"}},
        {"app.CharacterContext", {"get_GameObject", "get_Transform", "get_ContextID", "get_CharacterKindID"}},
        {"app.PlayerContext", {"get_GameObject", "get_Transform", "get_ContextID", "get_CharacterKindID", "get_Updater", "set_Updater", "onCreateContext", "onUpdateStructureData"}},
        {"app.CharacterPoolInfo", {
            "get_GameObjectFinalized", "set_GameObjectFinalized", "get_Updater", "set_Updater",
            "get_Reserved", "set_Reserved", "get_Used", "set_Used",
        }},
        {"app.CharacterUpdaterBase", {"get_GameObject", "get_Transform", "get_Context", "set_Context", "get_Owner", "set_Owner"}},
        {"app.PlayerUpdaterBase", {"get_GameObject", "get_Transform", "get_Context", "set_Context", "get_Owner", "set_Owner"}},
        {"app.Cp_A100Updater", {"get_GameObject", "get_Transform", "get_Context", "set_Context", "get_Owner", "set_Owner"}},
        {"app.LevelPlayerCreateController", {
            "setupControlCharacter", "setupCommonMessageKind", "createControlCharacter",
            "suspendChapterInitControlCharacter", "destroyControlCharacter",
            "app.ICharacterSpawnControl.requestSpawn", "app.ICharacterSpawnControl.requestResume",
            "app.ICharacterSpawnControl.get_SpawnID", "app.ICharacterSpawnControl.get_ManagedContextID",
            "app.ICharacterSpawnControl.getAllManagedContextID",
        }},
        {"app.LevelPlayerCreateController.CreateSetting", {".ctor"}},
        {"via.Prefab", {"instantiate"}},
        {"via.GameObject", {"create", "createComponent"}},
        {"via.Scene", {"findGameObject", "findGameObjects", "findGameObjectsWithTag"}},
        {"via.SceneManager", {"get_MainScene", "get_CurrentScene"}},
    }
    local lines = {}
    for _, target in ipairs(targets) do
        local type_name = target[1]
        local wanted = target[2]
        pcall(function()
            local td = sdk.find_type_definition(type_name)
            if not td then return end
            for _, method in ipairs(td:get_methods()) do
                local name = method:get_name()
                for _, want in ipairs(wanted) do
                    if name == want then
                        table.insert(lines, type_name .. "." .. method_signature(method))
                        break
                    end
                end
            end
        end)
    end
    state.method_signatures = table.concat(lines, "\n")
end

local function hook_parent_type_definition(td)
    if not td then return nil end
    local parent = nil
    local ok_parent = pcall(function() parent = td:get_parent_type() end)
    if not ok_parent or not parent then
        ok_parent = pcall(function() parent = td:get_parent_type_definition() end)
    end
    if not ok_parent then return nil end
    return parent
end

local function describe_hook_arg(arg)
    local out = {}
    pcall(function() out.i64 = safe_string(sdk.to_int64(arg)) end)
    pcall(function()
        local obj = sdk.to_managed_object(arg)
        if not obj then return end
        out.managed = true
        pcall(function()
            local td = obj:get_type_definition()
            out.type = td and td:get_full_name() or ""
        end)
        pcall(function()
            local text = obj:call("ToString")
            if text then out.text = safe_string(text) end
        end)
        pcall(function()
            local td = obj:get_type_definition()
            local type_name = td and td:get_full_name() or ""
            if not type_name:find("SpawnData")
                and not type_name:find("CharacterContext")
                and not type_name:find("PlayerContext")
                and not type_name:find("LevelPlayerCreateController")
                and not type_name:find("CreateSetting")
                and not type_name:find("ContextID")
                and not type_name:find("CharacterKindID") then
                return
            end

            out.fields = {}
            local n = 0
            local depth = 0
            local seen = {}
            local include_all_spawn_fields = type_name:find("SpawnData") ~= nil
            while td and depth < 8 and n < 80 do
                local level_name = td:get_full_name() or "?"
                if seen[level_name] then break end
                seen[level_name] = true

                for _, field in ipairs(td:get_fields()) do
                    local name = field:get_name() or ""
                    local ftype = field:get_type()
                    local field_type = ftype and ftype:get_full_name() or ""
                    local interesting = include_all_spawn_fields
                        or name:find("Context") or name:find("Kind") or name:find("Spawn")
                        or name:find("Montage") or name:find("Purpose") or name:find("GameObject")
                        or name:find("Transform") or name:find("Player") or name:find("Create")
                        or name:find("Setting") or name:find("Default") or name:find("Init")
                        or name:find("Enable") or name:find("Pose") or name:find("Position")
                        or name:find("Rotation") or name:find("Chapter") or name:find("Message")
                        or name:find("Prefab") or name:find("Resource") or name:find("Path")
                        or field_type:find("Context") or field_type:find("Kind")
                        or field_type:find("CreateSetting") or field_type:find("Spawn")
                    if interesting then
                        local value = nil
                        pcall(function() value = obj:get_field(name) end)
                        table.insert(out.fields, {
                            declaring_type = level_name,
                            name = name,
                            type = field_type,
                            value = safe_string(value),
                        })
                        n = n + 1
                        if n >= 80 then break end
                    end
                end

                td = hook_parent_type_definition(td)
                depth = depth + 1
            end
        end)
    end)
    return out
end

local function hook_arg_to_managed(arg)
    local obj = nil
    pcall(function() obj = sdk.to_managed_object(arg) end)
    return obj
end

local function reset_level_trace(reason)
    state.level_trace_events = {}
    state.level_trace_dirty = true
    state.level_trace_started_ms = now_ms()
    state.level_trace_last_scene = get_current_scene()
    state.level_trace_status = "recording: " .. safe_string(reason or "manual")
end

local function push_level_trace_event(method_name, args, phase, retval, max_args)
    if not state.level_trace_enabled then return end
    local event = {
        time_ms = now_ms(),
        dt_ms = math.max(0, now_ms() - (state.level_trace_started_ms or 0)),
        scene = get_current_scene(),
        phase = phase or "pre",
        method = method_name,
        args = {},
    }
    if args then
        local limit = max_args or 2
        for i = 2, limit do
            local arg = args[i]
            if arg == nil then break end
            event.args[i] = describe_hook_arg(arg)
        end
    end
    if retval ~= nil then
        event.retval = describe_hook_arg(retval)
    end
    table.insert(state.level_trace_events, event)
    while #state.level_trace_events > 3000 do
        table.remove(state.level_trace_events, 1)
    end
    state.level_trace_dirty = true
    state.level_trace_status = "recording events=" .. tostring(#state.level_trace_events)
end

local function push_level_trace_note(note)
    if not state.level_trace_enabled then return end
    table.insert(state.level_trace_events, {
        time_ms = now_ms(),
        dt_ms = math.max(0, now_ms() - (state.level_trace_started_ms or 0)),
        scene = get_current_scene(),
        phase = "note",
        method = safe_string(note),
        args = {},
    })
    while #state.level_trace_events > 3000 do
        table.remove(state.level_trace_events, 1)
    end
    state.level_trace_dirty = true
    state.level_trace_status = "recording events=" .. tostring(#state.level_trace_events)
end

local function dump_level_trace(force)
    if not force and not state.level_trace_dirty then return end
    state.level_trace_dirty = false
    pcall(function()
        json.dump_file(LEVEL_TRACE_FILE, {
            time_ms = now_ms(),
            active = state.level_trace_enabled,
            status = state.level_trace_status,
            scene = get_current_scene(),
            started_ms = state.level_trace_started_ms,
            events = state.level_trace_events,
        })
    end)
end

local function trace_type_name(obj)
    local type_name = ""
    pcall(function()
        if obj and obj.get_type_definition then
            local td = obj:get_type_definition()
            type_name = td and td:get_full_name() or ""
        end
    end)
    return type_name
end

local function trace_call(obj, method_name)
    local value = nil
    pcall(function()
        if obj then value = obj:call(method_name) end
    end)
    return value
end

function re9mp_trace_value(obj, methods, fields)
    if not obj then return nil end
    for _, method_name in ipairs(methods or {}) do
        local value = nil
        pcall(function() value = obj:call(method_name) end)
        if value ~= nil then return value end
    end
    for _, field_name in ipairs(fields or {}) do
        local value = nil
        pcall(function() value = obj:get_field(field_name) end)
        if value ~= nil then return value end
    end
    return nil
end

local function trace_count(obj)
    local count = nil
    pcall(function() if obj then count = obj:call("get_Count") end end)
    if count == nil then
        pcall(function() if obj then count = obj:get_size() end end)
    end
    return tonumber(count) or 0
end

local function trace_item(obj, index)
    local item = nil
    local ok_item = pcall(function()
        if obj then item = obj:call("get_Item", index) end
    end)
    if not ok_item or item == nil then
        pcall(function()
            if obj then item = obj:get_element(index) end
        end)
    end
    return item
end

local function trace_context_summary(ctx, index)
    local row = {
        index = index,
        ref = safe_string(ctx),
        type = trace_type_name(ctx),
    }
    if not ctx then return row end

    local go = trace_call(ctx, "get_GameObject")
    local updater = trace_call(ctx, "get_Updater")
    row.game_object = safe_string(go)
    row.updater = safe_string(updater)
    row.updater_type = trace_type_name(updater)
    row.transform = safe_string(trace_call(ctx, "get_Transform"))
    row.context_id = safe_string(re9mp_trace_value(ctx, {"get_ContextID"}, {
        "<ContextID>k__BackingField", "_ContextID", "ContextID",
    }))
    row.character_kind_id = safe_string(re9mp_trace_value(ctx, {"get_CharacterKindID"}, {
        "<CharacterKindID>k__BackingField", "_CharacterKindID", "CharacterKindID",
    }))
    row.active = trace_call(ctx, "get_IsActivePlayer")
    row.tps = trace_call(ctx, "get_IsTPSCharacter")
    row.fps = trace_call(ctx, "get_IsFPSCharacter")
    row.cp_a1 = trace_call(ctx, "get_IsCp_A1Character")
    return row
end

local function trace_pool_summary(pool, index)
    local row = {
        index = index,
        ref = safe_string(pool),
        type = trace_type_name(pool),
    }
    if not pool then return row end

    local updater = nil
    local used = nil
    local reserved = nil
    local finalized = nil
    pcall(function() updater = pool:get_field("<Updater>k__BackingField") end)
    pcall(function() used = pool:get_field("<Used>k__BackingField") end)
    pcall(function() reserved = pool:get_field("<Reserved>k__BackingField") end)
    pcall(function() finalized = pool:get_field("<GameObjectFinalized>k__BackingField") end)

    row.used = used
    row.reserved = reserved
    row.finalized = finalized
    row.updater = safe_string(updater)
    row.updater_type = trace_type_name(updater)
    row.updater_game_object = safe_string(trace_call(updater, "get_GameObject"))
    row.updater_transform = safe_string(trace_call(updater, "get_Transform"))
    row.updater_context = safe_string(trace_call(updater, "get_Context"))
    row.updater_owner = safe_string(trace_call(updater, "get_Owner"))
    row.context_id = safe_string(re9mp_trace_value(updater, {"get_ContextID"}, {
        "<ContextID>k__BackingField", "_ContextID", "ContextID",
    }))
    row.character_kind_id = safe_string(re9mp_trace_value(updater, {"get_CharacterKindID"}, {
        "<CharacterKindID>k__BackingField", "_CharacterKindID", "CharacterKindID",
    }))
    return row
end

function re9mp_trace_mesh_controller_summary(controller, label)
    local row = {
        label = safe_string(label or ""),
        ref = safe_string(controller),
        type = trace_type_name(controller),
        counts = {},
    }
    if not controller then return row end

    local go = trace_call(controller, "get_GameObject")
    local dict = nil
    local mesh_list = nil
    local mesh_parts = nil
    local property_values = nil
    pcall(function() dict = controller:get_field("<MeshUnitDictionary>k__BackingField") end)
    pcall(function() mesh_list = controller:get_field("_MeshList") end)
    pcall(function() mesh_parts = controller:get_field("_MeshPartsDictionary") end)
    pcall(function() property_values = controller:get_field("_PropertyValueContainers") end)

    row.game_object = safe_string(go)
    row.game_object_name = safe_string(trace_call(go, "get_Name"))
    row.transform = safe_string(trace_call(go, "get_Transform"))
    row.counts.mesh_unit_dictionary = trace_count(dict)
    row.counts.mesh_list = trace_count(mesh_list)
    row.counts.mesh_parts_dictionary = trace_count(mesh_parts)
    row.counts.property_value_containers = trace_count(property_values)
    row.mesh_unit_dictionary = safe_string(dict)
    row.mesh_list = safe_string(mesh_list)
    row.mesh_parts_dictionary = safe_string(mesh_parts)
    row.property_value_containers = safe_string(property_values)
    return row
end

function re9mp_trace_mesh_unit_summary(unit, index)
    local row = {
        index = index,
        ref = safe_string(unit),
        type = trace_type_name(unit),
    }
    if not unit then return row end

    local go = trace_call(unit, "get_GameObject")
    local mesh = trace_call(unit, "get_Mesh")
    local mesh_go = trace_call(mesh, "get_GameObject")
    row.mesh_type = safe_string(trace_call(unit, "get_MeshType"))
    row.game_object = safe_string(go)
    row.game_object_name = safe_string(trace_call(go, "get_Name"))
    row.transform = safe_string(trace_call(go, "get_Transform"))
    row.position = read_position(trace_call(go, "get_Transform"))
    row.mesh = safe_string(mesh)
    row.mesh_type_name = trace_type_name(mesh)
    row.mesh_game_object = safe_string(mesh_go)
    row.mesh_game_object_name = safe_string(trace_call(mesh_go, "get_Name"))
    row.mesh_controller = safe_string(trace_call(unit, "get_MeshController"))
    row.parent_mesh_controller = safe_string(trace_call(unit, "get_ParentMeshController"))
    return row
end

local function build_pool_trace_snapshot(reason)
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    local event = {
        time_ms = now_ms(),
        dt_ms = math.max(0, now_ms() - (state.pool_trace_started_ms or 0)),
        scene = get_current_scene(),
        reason = safe_string(reason or "sample"),
        character_manager = safe_string(char_mgr),
        player_contexts = {},
        pool = {},
        counts = {},
    }
    if not char_mgr then
        event.signature = "no-character-manager"
        return event
    end

    local player_list = nil
    local spawnable_list = nil
    local pool_list = nil
    local spawn_data_db = nil
    local context_db = nil
    local spawn_owner = nil
    pcall(function() player_list = char_mgr:get_field("<PlayerContextList>k__BackingField") end)
    pcall(function() spawnable_list = char_mgr:get_field("<SpawnableContextList>k__BackingField") end)
    pcall(function() pool_list = char_mgr:get_field("<CharacterPool>k__BackingField") end)
    pcall(function() spawn_data_db = char_mgr:get_field("<CharacterSpawnDataDB>k__BackingField") end)
    pcall(function() context_db = char_mgr:get_field("<CharacterContextDB>k__BackingField") end)
    pcall(function() spawn_owner = char_mgr:get_field("<SpawnOwnerDictionary>k__BackingField") end)

    event.counts.player_contexts = trace_count(player_list)
    event.counts.spawnable_contexts = trace_count(spawnable_list)
    event.counts.character_pool = trace_count(pool_list)
    event.counts.spawn_data_db = trace_count(spawn_data_db)
    event.counts.context_db = trace_count(context_db)
    event.counts.spawn_owner = trace_count(spawn_owner)

    for i = 0, math.min(event.counts.player_contexts - 1, 5) do
        table.insert(event.player_contexts, trace_context_summary(trace_item(player_list, i), i))
    end

    for i = 0, math.min(event.counts.character_pool - 1, 63) do
        local row = trace_pool_summary(trace_item(pool_list, i), i)
        if row.updater ~= "" or row.used ~= nil or row.reserved ~= nil or row.finalized ~= nil then
            table.insert(event.pool, row)
        end
    end

    local sig_parts = {
        "pc=" .. tostring(event.counts.player_contexts),
        "sp=" .. tostring(event.counts.spawnable_contexts),
        "pool=" .. tostring(event.counts.character_pool),
        "sdb=" .. tostring(event.counts.spawn_data_db),
        "cdb=" .. tostring(event.counts.context_db),
        "owner=" .. tostring(event.counts.spawn_owner),
    }
    for _, ctx in ipairs(event.player_contexts) do
        table.insert(sig_parts, "ctx" .. tostring(ctx.index) .. ":" .. safe_string(ctx.updater_type) .. ":" .. safe_string(ctx.game_object))
    end
    for _, row in ipairs(event.pool) do
        table.insert(sig_parts, "p" .. tostring(row.index) .. ":" .. safe_string(row.used) .. ":" .. safe_string(row.reserved) .. ":" .. safe_string(row.finalized) .. ":" .. safe_string(row.updater_type) .. ":" .. safe_string(row.updater_game_object))
    end
    event.signature = table.concat(sig_parts, "|")
    return event
end

local function reset_pool_trace(reason)
    state.pool_trace_events = {}
    state.pool_trace_dirty = true
    state.pool_trace_started_ms = now_ms()
    state.pool_trace_last_scene = get_current_scene()
    state.pool_trace_last_signature = ""
    state.pool_trace_status = "recording: " .. safe_string(reason or "manual")
end

local function push_pool_trace_event(reason, force)
    if not state.pool_trace_enabled then return end
    local event = build_pool_trace_snapshot(reason)
    if not force and event.signature == state.pool_trace_last_signature then
        return
    end
    state.pool_trace_last_signature = event.signature
    table.insert(state.pool_trace_events, event)
    while #state.pool_trace_events > 500 do
        table.remove(state.pool_trace_events, 1)
    end
    state.pool_trace_dirty = true
    state.pool_trace_status = "recording events=" .. tostring(#state.pool_trace_events)
end

local function dump_pool_trace(force)
    if not force and not state.pool_trace_dirty then return end
    state.pool_trace_dirty = false
    pcall(function()
        json.dump_file(POOL_TRACE_FILE, {
            time_ms = now_ms(),
            active = state.pool_trace_enabled,
            status = state.pool_trace_status,
            scene = get_current_scene(),
            started_ms = state.pool_trace_started_ms,
            events = state.pool_trace_events,
        })
    end)
end

local function reset_bind_trace(reason)
    state.bind_trace_events = {}
    state.bind_trace_errors = {}
    state.bind_trace_dirty = true
    state.bind_trace_started_ms = now_ms()
    state.bind_trace_status = "recording: " .. safe_string(reason or "manual")
end

local function describe_bind_object(obj)
    local row = {
        ref = safe_string(obj),
        type = trace_type_name(obj),
    }
    if not obj then return row end

    if row.type:find("CharacterPoolInfo", 1, true) then
        row.pool = trace_pool_summary(obj, -1)
    elseif row.type:find("MeshUnit", 1, true) then
        row.mesh_unit = re9mp_trace_mesh_unit_summary(obj, -1)
    elseif row.type:find("MeshController", 1, true) then
        row.mesh_controller = re9mp_trace_mesh_controller_summary(obj, "bind_arg")
    elseif row.type:find("via.render.Mesh", 1, true) then
        local go = trace_call(obj, "get_GameObject")
        row.mesh = {
            game_object = safe_string(go),
            game_object_name = safe_string(trace_call(go, "get_Name")),
            transform = safe_string(trace_call(go, "get_Transform")),
        }
    elseif row.type:find("Updater", 1, true) then
        row.game_object = safe_string(trace_call(obj, "get_GameObject"))
        row.transform = safe_string(trace_call(obj, "get_Transform"))
        row.context = safe_string(trace_call(obj, "get_Context"))
        row.owner = safe_string(trace_call(obj, "get_Owner"))
    elseif row.type:find("CharacterContext", 1, true) or row.type:find("PlayerContext", 1, true) then
        row.context_summary = trace_context_summary(obj, -1)
    end

    return row
end

local function push_bind_trace_event(method_name, args, max_args, phase, retval)
    if not state.bind_trace_enabled then return end

    local event = {
        time_ms = now_ms(),
        dt_ms = math.max(0, now_ms() - (state.bind_trace_started_ms or 0)),
        scene = get_current_scene(),
        phase = phase or "pre",
        method = method_name,
        args = {},
        counts = {},
    }

    pcall(function()
        local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
        if not char_mgr then return end

        local player_list = nil
        local pool_list = nil
        local spawn_data_db = nil
        local context_db = nil
        pcall(function() player_list = char_mgr:get_field("<PlayerContextList>k__BackingField") end)
        pcall(function() pool_list = char_mgr:get_field("<CharacterPool>k__BackingField") end)
        pcall(function() spawn_data_db = char_mgr:get_field("<CharacterSpawnDataDB>k__BackingField") end)
        pcall(function() context_db = char_mgr:get_field("<CharacterContextDB>k__BackingField") end)

        event.counts.player_contexts = trace_count(player_list)
        event.counts.character_pool = trace_count(pool_list)
        event.counts.spawn_data_db = trace_count(spawn_data_db)
        event.counts.context_db = trace_count(context_db)
    end)

    local limit = max_args or 2
    for i = 2, limit do
        local raw = args and args[i]
        if raw == nil then break end

        local arg = {
            slot = i,
            i64 = "",
        }
        pcall(function() arg.i64 = safe_string(sdk.to_int64(raw)) end)
        pcall(function()
            local obj = sdk.to_managed_object(raw)
            if obj then
                arg.object = describe_bind_object(obj)
            end
        end)
        table.insert(event.args, arg)
    end
    if retval ~= nil then
        event.retval = describe_hook_arg(retval)
        pcall(function()
            local obj = sdk.to_managed_object(retval)
            if obj then event.retval.object = describe_bind_object(obj) end
        end)
    end

    table.insert(state.bind_trace_events, event)
    while #state.bind_trace_events > 5000 do
        table.remove(state.bind_trace_events, 1)
    end
    state.bind_trace_dirty = true
    state.bind_trace_status = "recording events=" .. tostring(#state.bind_trace_events)
end

local function dump_bind_trace(force)
    if not force and not state.bind_trace_dirty then return end
    state.bind_trace_dirty = false
    pcall(function()
        json.dump_file(BIND_TRACE_FILE, {
            time_ms = now_ms(),
            active = state.bind_trace_enabled,
            status = state.bind_trace_status,
            scene = get_current_scene(),
            started_ms = state.bind_trace_started_ms,
            events = state.bind_trace_events,
            errors = state.bind_trace_errors or {},
        })
    end)
end

local function install_bind_trace_hooks()
    if state.bind_trace_attempted then return end
    state.bind_trace_attempted = true

    local ok, err = pcall(function()
        local installed = 0
        local hooked = {}
        local hook_errors = {}
        local targets = {
            {"app.CharacterPoolInfo", {
                set_GameObjectFinalized = true,
                set_Updater = true,
                set_Reserved = true,
                set_Used = true,
            }},
            {"app.PlayerContext", {
                set_Updater = true,
                onCreateContext = true,
            }},
            {"app.CharacterUpdaterBase", {
                set_Context = true,
                set_Owner = true,
            }},
            {"app.PlayerUpdaterBase", {
                set_Context = true,
                set_Owner = true,
            }},
            {"app.Cp_A100Updater", {
                set_Context = true,
                set_Owner = true,
            }},
            {"app.CharacterMeshControllerBase", {
                registerMeshUnit = true,
                registerMeshUnitOnSubMontage = true,
                unregisterMeshUnit = true,
                searchInitMeshUnits = true,
                setupMeshUnit = true,
                setupMeshUnits = true,
                initialize = true,
                onInitialize = true,
            }},
            {"app.PlayerMeshController", {
                registerMeshUnit = true,
                registerMeshUnitOnSubMontage = true,
                unregisterMeshUnit = true,
                searchInitMeshUnits = true,
                setupMeshUnit = true,
                setupMeshUnits = true,
                initialize = true,
                onInitialize = true,
            }},
            {"app.ActorPlayerMeshController", {
                registerMeshUnit = true,
                registerMeshUnitOnSubMontage = true,
                unregisterMeshUnit = true,
                searchInitMeshUnits = true,
                setupMeshUnit = true,
                setupMeshUnits = true,
                initialize = true,
                onInitialize = true,
            }},
            {"app.MeshUnit", {
                [".ctor"] = true,
                setDrawAndUpdate = true,
                setDrawDefault = true,
                setDrawShadow = true,
                changeMeshType = true,
            }},
        }

        for _, target in ipairs(targets) do
            local type_name = target[1]
            local observe = target[2]
            local td = sdk.find_type_definition(type_name)
            if td then
                for _, method in ipairs(td:get_methods()) do
                    local name = method:get_name()
                    if observe[name] then
                        local label = type_name .. "." .. name
                        local arg_limit = 2
                        pcall(function() label = type_name .. "." .. method_signature(method) end)
                        pcall(function()
                            local param_types = method:get_param_types()
                            arg_limit = (param_types and #param_types or 0) + 2
                        end)
                        local hook_key = safe_string(method)
                        if hook_key == "" then hook_key = label end
                        if not hooked[hook_key] then
                            hooked[hook_key] = true
                            local hook_ok, hook_err = pcall(function()
                                sdk.hook(method, function(args)
                                    pcall(function() push_bind_trace_event(label, args, arg_limit, "pre", nil) end)
                                end, function(retval)
                                    pcall(function() push_bind_trace_event(label, nil, 0, "post", retval) end)
                                    return retval
                                end)
                            end)
                            if hook_ok then
                                installed = installed + 1
                            else
                                table.insert(hook_errors, label .. ": " .. safe_string(hook_err))
                            end
                        end
                    end
                end
            end
        end

        state.bind_trace_errors = hook_errors
        state.bind_trace_status = "installed " .. tostring(installed) .. " bind hooks"
            .. (#hook_errors > 0 and (" errors=" .. tostring(#hook_errors)) or "")
        dump_bind_trace(true)
    end)

    if not ok then
        state.bind_trace_status = "hook install failed: " .. safe_string(err)
        dump_bind_trace(true)
    end
end

local function push_spawn_hook_event(method_name, args, max_args)
    if not state.spawn_hook_enabled and not state.level_trace_enabled then return end
    local event = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        method = method_name,
        args = {},
    }
    local limit = max_args or 2
    for i = 2, limit do
        local arg = args[i]
        if arg == nil then break end
        event.args[i] = describe_hook_arg(arg)
    end
    table.insert(state.spawn_hook_events, event)
    while #state.spawn_hook_events > 1500 do
        table.remove(state.spawn_hook_events, 1)
    end
    state.spawn_hook_dirty = true
    state.spawn_hook_status = "captured " .. method_name
end

local function dump_spawn_hook_log(force)
    if not force and not state.spawn_hook_dirty then return end
    state.spawn_hook_dirty = false
    pcall(function()
        json.dump_file(SPAWN_HOOK_FILE, {
            time_ms = now_ms(),
            status = state.spawn_hook_status,
            events = state.spawn_hook_events,
        })
    end)
end

local function install_spawn_observer_hooks()
    if state.spawn_hook_attempted then return end
    state.spawn_hook_attempted = true

    local ok, err = pcall(function()
        local td = sdk.find_type_definition("app.CharacterManager")
        if not td then
            state.spawn_hook_status = "CharacterManager type not found"
            return
        end

        local installed = 0
        local observe = {
            requestSpawn = true,
            requestInstantiateMontage = true,
            getAndRequestSpawnOwner = true,
            clearSpawnOwner = true,
            makeSpawnControlBackupData = true,
            getSpawnControlBackup = true,
            registerSpawnData = true,
            unregisterSpawnData = true,
            readyContext = true,
            storeContext = true,
            restoreContext = true,
            unregisterContext = true,
            clearContext = true,
            registerSpawnGroup = true,
            unregisterSpawnGroup = true,
            registerPlayerContextIDList = true,
            unregisterPlayerContextIDList = true,
            getCharacterContextFactory = true,
            notifyPlayerInitialized = true,
            setPlayerInitializeNum = true,
            notifyStartPlayerContinuousChapter = true,
            notifyEndPlayerContinuousChapter = true,
            onChangeActivePlayer = true,
        }
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name()
            if observe[name] then
                local label = name
                local arg_limit = 2
                pcall(function() label = method_signature(method) end)
                pcall(function()
                    local param_types = method:get_param_types()
                    arg_limit = (param_types and #param_types or 0) + 2
                end)
                sdk.hook(method, function(args)
                    pcall(function() push_spawn_hook_event(label, args, arg_limit) end)
                    pcall(function() push_level_trace_event(label, args, "pre", nil, arg_limit) end)
                end, function(retval)
                    pcall(function()
                        if name == "readyContext" or name == "restoreContext" or name == "getCharacterContextFactory" then
                            push_level_trace_event(label, nil, "post", retval, 0)
                        end
                    end)
                    return retval
                end)
                installed = installed + 1
            end
        end
        local controller_td = cfg.controller_trace_enabled and sdk.find_type_definition("app.LevelPlayerCreateController") or nil
        if controller_td then
            for _, method in ipairs(controller_td:get_methods()) do
                local name = method:get_name()
                local observe_controller = name == "setupControlCharacter"
                    or name == "setupCommonMessageKind"
                    or name == "createControlCharacter"
                    or name == "suspendChapterInitControlCharacter"
                    or name == "destroyControlCharacter"
                    or name:find("makeSpawnControlBackup", 1, true) ~= nil
                if observe_controller then
                    local label = "LevelPlayerCreateController." .. name
                    local arg_limit = 2
                    pcall(function() label = "LevelPlayerCreateController." .. method_signature(method) end)
                    pcall(function()
                        local param_types = method:get_param_types()
                        arg_limit = (param_types and #param_types or 0) + 2
                    end)
                    sdk.hook(method, function(args)
                        if name == "setupControlCharacter"
                            and state.load_phase_injection_armed
                            and not state.load_phase_injection_done
                            and not state.load_phase_injection_guard then
                            local pending_control = args and hook_arg_to_managed(args[2]) or nil
                            local pending_setting = args and hook_arg_to_managed(args[3]) or nil
                            pcall(function()
                                if pending_control and pending_control.add_ref then
                                    pending_control = pending_control:add_ref()
                                end
                            end)
                            pcall(function()
                                if pending_setting and pending_setting.add_ref then
                                    pending_setting = pending_setting:add_ref()
                                end
                            end)
                            state.load_phase_injection_pending_control = pending_control
                            state.load_phase_injection_pending_setting = pending_setting
                            state.load_phase_injection_pre_lines = {}
                            pcall(function()
                                re9mp_append_spawn_control_identity_summary(
                                    state.load_phase_injection_pre_lines,
                                    "Control.real_pre_setup",
                                    pending_control,
                                    140
                                )
                            end)
                        end
                        pcall(function() push_spawn_hook_event(label, args, arg_limit) end)
                        pcall(function() push_level_trace_event(label, args, "pre", nil, arg_limit) end)
                    end, function(retval)
                        pcall(function()
                            push_level_trace_event(label, nil, "post", retval, 0)
                        end)
                        if name == "setupControlCharacter" then
                            pcall(function()
                                re9mp_maybe_run_load_phase_player_clone_injection(
                                    state.load_phase_injection_pending_control,
                                    state.load_phase_injection_pending_setting,
                                    "post_setupControlCharacter"
                                )
                            end)
                        end
                        return retval
                    end)
                    installed = installed + 1
                end
            end
        elseif cfg.controller_trace_enabled then
            push_level_trace_note("LevelPlayerCreateController type not found")
        end

        state.spawn_hook_status = "installed " .. tostring(installed) .. " observer hooks"
        if state.level_trace_enabled and state.level_trace_started_ms == 0 then
            reset_level_trace("script load")
        end
        dump_spawn_hook_log(true)
        dump_level_trace(true)
    end)

    if not ok then
        state.spawn_hook_status = "hook install failed: " .. safe_string(err)
        dump_spawn_hook_log(true)
    end
end

function re9mp_install_load_phase_controller_minimal_hook()
    if state.load_phase_minimal_controller_hook_attempted then return end
    state.load_phase_minimal_controller_hook_attempted = true

    local ok, err = pcall(function()
        local controller_td = sdk.find_type_definition("app.LevelPlayerCreateController")
        if not controller_td then
            state.load_phase_injection_status = "minimal hook failed: LevelPlayerCreateController type not found"
            return
        end

        local installed = 0
        for _, method in ipairs(controller_td:get_methods()) do
            local name = method:get_name()
            if name == "setupControlCharacter" then
                sdk.hook(method, function(args)
                    if state.load_phase_injection_armed
                        and not state.load_phase_injection_done
                        and not state.load_phase_injection_guard then
                        local pending_control = args and hook_arg_to_managed(args[2]) or nil
                        local pending_setting = args and hook_arg_to_managed(args[3]) or nil
                        pcall(function()
                            if pending_control and pending_control.add_ref then
                                pending_control = pending_control:add_ref()
                            end
                        end)
                        pcall(function()
                            if pending_setting and pending_setting.add_ref then
                                pending_setting = pending_setting:add_ref()
                            end
                        end)
                        state.load_phase_injection_pending_control = pending_control
                        state.load_phase_injection_pending_setting = pending_setting
                        state.load_phase_injection_pre_lines = {}
                        pcall(function()
                            re9mp_append_spawn_control_identity_summary(
                                state.load_phase_injection_pre_lines,
                                "Control.real_pre_setup",
                                pending_control,
                                140
                            )
                        end)
                    end
                end, function(retval)
                    if state.load_phase_injection_armed
                        and not state.load_phase_injection_done
                        and not state.load_phase_injection_guard then
                        pcall(function()
                            re9mp_maybe_run_load_phase_player_clone_injection(
                                state.load_phase_injection_pending_control,
                                state.load_phase_injection_pending_setting,
                                "minimal_post_setupControlCharacter"
                            )
                        end)
                    end
                    return retval
                end)
                installed = installed + 1
            end
        end
        state.spawn_hook_status = "minimal controller hooks installed=" .. tostring(installed)
    end)

    if not ok then
        state.spawn_hook_status = "minimal controller hook error: " .. safe_string(err)
    end
end
