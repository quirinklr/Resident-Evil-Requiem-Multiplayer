-- Character, component, visual, and mesh probes extracted from pre-split runtime lines 2714-3483.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function run_character_object_probe()
    local refs = get_local_player_refs()
    if refs.valid and refs.go then
        collect_player_fields(refs.player)
        collect_player_methods(refs.player)
        collect_component_summary(refs.go)
    end
    collect_method_signatures()

    local context_empty = get_static_field_value("app.ContextID", {"Empty"})
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
    local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
    local lines = {
        "local_player=" .. tostring(refs.valid),
        describe_value_for_probe("ContextID.Empty", context_empty),
        describe_value_for_probe("CharacterKindID.cp_A100", kind_grace),
        describe_value_for_probe("MontageID.Invalid", montage_invalid),
        describe_value_for_probe("CharacterUsePurposeFlag.Default", purpose_default),
    }
    for _, line in ipairs(object_all_field_summary("ContextID.Empty", context_empty, 32)) do
        table.insert(lines, line)
    end
    for _, line in ipairs(object_all_method_summary("ContextID.Empty", context_empty, 48)) do
        table.insert(lines, line)
    end

    local spawn_data_status = "not tried"
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if char_mgr and context_empty then
        local ok, result_or_err = pcall(function()
            return char_mgr:call("getSpawnDataRef(app.ContextID)", context_empty)
                or char_mgr:call("getSpawnDataRef", context_empty)
        end)
        if ok and result_or_err then
            spawn_data_status = "getSpawnDataRef(ContextID.Empty) returned " .. safe_string(result_or_err)
            for _, line in ipairs(object_field_summary("SpawnData.Empty", result_or_err, 28)) do
                table.insert(lines, line)
            end
        else
            spawn_data_status = ok and "getSpawnDataRef(ContextID.Empty) returned nil" or ("getSpawnDataRef failed: " .. safe_string(result_or_err))
        end
    end
    table.insert(lines, spawn_data_status)

    if char_mgr then
        if state.last_spawn_context then
            table.insert(lines, "LastSpawnContext=" .. safe_string(state.last_spawn_context_text))
            for _, call_name in ipairs({
                "isUsedContext(app.ContextID)",
                "isUsedContext",
                "getContextRef(app.ContextID)",
                "getContextRef",
                "getSpawnDataRef(app.ContextID)",
                "getSpawnDataRef",
            }) do
                local ok, result = pcall(function()
                    return char_mgr:call(call_name, state.last_spawn_context)
                end)
                table.insert(lines, call_name .. "(LastSpawnContext) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
                if ok and result and tostring(call_name):find("getContextRef") then
                    for _, line in ipairs(object_field_summary("LastSpawnContext.Context", result, 40)) do
                        table.insert(lines, line)
                    end
                    for _, line in ipairs(object_method_summary("LastSpawnContext.Context", result, {"GameObject", "Transform", "Context", "Update", "Spawn"}, 60)) do
                        table.insert(lines, line)
                    end
                end
            end
            local ok_last_spawn_data, last_spawn_data = pcall(function()
                return char_mgr:call("getSpawnDataRef(app.ContextID)", state.last_spawn_context)
                    or char_mgr:call("getSpawnDataRef", state.last_spawn_context)
            end)
            table.insert(lines, "LastSpawnContext.SpawnDataDeep -> " .. (ok_last_spawn_data and safe_string(last_spawn_data) or ("ERR " .. safe_string(last_spawn_data))))
            if ok_last_spawn_data and last_spawn_data then
                append_spawn_data_deep_summary(lines, "SpawnData.LastSpawnContext", last_spawn_data)
            end
        end

        table.insert(lines, "CharacterManager methods: " .. table.concat(collect_methods_from_type("app.CharacterManager", {"Player", "Context", "Spawn", "Montage", "Owner"}, 120), ", "))
        for _, line in ipairs(object_field_summary("CharacterManager", char_mgr, 80)) do
            table.insert(lines, line)
        end

        local player_context_id = nil
        if kind_grace then
            for _, call_name in ipairs({
                "getPlayerContextID(app.CharacterKindID)",
                "getPlayerContextID",
            }) do
                local ok, result = pcall(function()
                    return char_mgr:call(call_name, kind_grace)
                end)
                table.insert(lines, call_name .. "(cp_A100) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
                if ok and result and not player_context_id then player_context_id = result end
            end
        end
        if player_context_id then
            table.insert(lines, describe_value_for_probe("PlayerContextID.cp_A100", player_context_id))
            for _, context_probe in ipairs({
                {"PlayerContextID.cp_A100", player_context_id},
                {"ContextID.Empty", context_empty},
            }) do
                local ctx_label, ctx = context_probe[1], context_probe[2]
                if ctx then
                    for _, call_name in ipairs({
                        "isUsedContext(app.ContextID)",
                        "isUsedContext",
                        "getManagedContextID(app.ContextID)",
                        "getManagedContextID",
                        "getContextRef(app.ContextID)",
                        "getContextRef",
                        "getPlayerContextRef(app.ContextID)",
                        "getPlayerContextRef",
                    }) do
                        local ok, result = pcall(function()
                            return char_mgr:call(call_name, ctx)
                        end)
                        table.insert(lines, call_name .. "(" .. ctx_label .. ") -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
                    end
                end
            end
            local ok, result = pcall(function()
                return char_mgr:call("getSpawnDataRef(app.ContextID)", player_context_id)
                    or char_mgr:call("getSpawnDataRef", player_context_id)
            end)
            table.insert(lines, "getSpawnDataRef(PlayerContextID.cp_A100) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
            if ok and result then
                for _, line in ipairs(object_field_summary("SpawnData.Player.cp_A100", result, 40)) do
                    table.insert(lines, line)
                end
                for _, line in ipairs(object_all_field_summary("SpawnData.Player.cp_A100", result, 80)) do
                    table.insert(lines, line)
                end
                append_spawn_data_deep_summary(lines, "SpawnData.Player.cp_A100.Deep", result)
                for _, line in ipairs(object_all_method_summary("SpawnData.Player.cp_A100", result, 80)) do
                    table.insert(lines, line)
                end
            end
        end

        for _, field_info in ipairs({
            {"Field.PlayerContextList", "<PlayerContextList>k__BackingField"},
            {"Field.SpawnableContextList", "<SpawnableContextList>k__BackingField"},
            {"Field.PlayerContextIDHolder", "<PlayerContextIDHolder>k__BackingField"},
            {"Field.CharacterPool", "<CharacterPool>k__BackingField"},
            {"Field.CharacterSpawnDataDB", "<CharacterSpawnDataDB>k__BackingField"},
            {"Field.CharacterContextDB", "<CharacterContextDB>k__BackingField"},
        }) do
            pcall(function()
                local field_value = char_mgr:get_field(field_info[2])
                append_iterable_summary(lines, field_info[1], field_value, 12)
                if field_info[1] == "Field.PlayerContextList" and field_value then
                    local count = nil
                    pcall(function() count = field_value:call("get_Count") end)
                    if count then
                        for i = 0, math.min((tonumber(count) or 0) - 1, 2) do
                            local item = nil
                            pcall(function() item = field_value:call("get_Item", i) end)
                            append_player_context_deep_summary(lines, field_info[1] .. "[" .. tostring(i) .. "]", item)
                        end
                    end
                elseif field_info[1] == "Field.PlayerContextIDHolder" and field_value then
                    local count = nil
                    pcall(function() count = field_value:call("get_Count") end)
                    if count then
                        for i = 0, math.min((tonumber(count) or 0) - 1, 3) do
                            local item = nil
                            pcall(function() item = field_value:call("get_Item", i) end)
                            for _, line in ipairs(object_all_field_summary(field_info[1] .. "[" .. tostring(i) .. "]", item, 32)) do
                                table.insert(lines, line)
                            end
                            for _, line in ipairs(object_all_method_summary(field_info[1] .. "[" .. tostring(i) .. "]", item, 48)) do
                                table.insert(lines, line)
                            end
                            for _, line in ipairs(object_method_summary(field_info[1] .. "[" .. tostring(i) .. "]", item, {"Context", "ID", "Reserve", "Use", "Used", "Get", "Next", "Create"}, 36)) do
                                table.insert(lines, line)
                            end
                        end
                    end
                elseif field_info[1] == "Field.CharacterPool" and field_value then
                    local count = nil
                    pcall(function() count = field_value:call("get_Count") end)
                    if count then
                        for i = 0, math.min((tonumber(count) or 0) - 1, 5) do
                            local item = nil
                            pcall(function() item = field_value:call("get_Item", i) end)
                            for _, line in ipairs(object_all_field_summary(field_info[1] .. "[" .. tostring(i) .. "]", item, 24)) do
                                table.insert(lines, line)
                            end
                        end
                    end
                end
            end)
        end

        pcall(function()
            append_iterable_summary(lines, "SpawnedContextRefList", char_mgr:call("getSpawnedContextRefList"), 8)
        end)
        pcall(function()
            append_iterable_summary(lines, "SpawnableContextList", char_mgr:call("getSpawnableContextList"), 12)
        end)
    end

    state.character_object_probe = table.concat(lines, "\n")
    pcall(function()
        json.dump_file(DATA_PREFIX .. "character_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            local_ok = refs.valid,
            status = spawn_data_status,
            values = lines,
            player_fields = state.player_fields,
            player_methods = state.player_methods,
            component_summary = state.component_summary,
            method_signatures = state.method_signatures,
        })
    end)
    return true, spawn_data_status
end

local function is_resource_probe_name(name)
    name = tostring(name or "")
    return name:find("Prefab") or name:find("prefab")
        or name:find("Resource") or name:find("resource")
        or name:find("Mesh") or name:find("mesh")
        or name:find("Material") or name:find("material")
        or name:find("Motion") or name:find("motion")
        or name:find("Bank") or name:find("bank")
        or name:find("Model") or name:find("model")
        or name:find("Path") or name:find("path")
        or name:find("File") or name:find("file")
        or name:find("ch0100") or name:find("A100")
end

local function value_resource_info(value)
    local info = {
        value = safe_string(value),
        type = trace_type_name(value),
        path = normalize_resource_path(safe_string(value)) or "",
        text = "",
    }
    if value and (type(value) == "userdata" or type(value) == "table") then
        for _, method_name in ipairs({"ToString", "get_Path", "get_FilePath", "get_Name", "get_ResourcePath"}) do
            local ok, result = pcall(function()
                if value.call then return value:call(method_name) end
                return nil
            end)
            if ok and result then
                local text = safe_string(result)
                if info.text == "" then info.text = text end
                local path = normalize_resource_path(text)
                if path and info.path == "" then info.path = path end
            end
        end
    end
    return info
end

local function collect_resource_rows_from_object(label, obj, field_limit, method_limit)
    local out = {
        label = safe_string(label),
        value = safe_string(obj),
        type = trace_type_name(obj),
        fields = {},
        methods = {},
    }
    if not obj or not obj.get_type_definition then return out end

    pcall(function()
        local td = obj:get_type_definition()
        local seen = {}
        local depth = 0
        while td and depth < 8 and #out.fields < (field_limit or 48) do
            local declaring_type = td:get_full_name() or "?"
            if seen[declaring_type] then break end
            seen[declaring_type] = true
            for _, field in ipairs(td:get_fields()) do
                local field_name = field:get_name() or ""
                local field_type = ""
                pcall(function()
                    local ftype = field:get_type()
                    field_type = ftype and ftype:get_full_name() or ""
                end)
                if is_resource_probe_name(field_name) or is_resource_probe_name(field_type) then
                    local value = nil
                    pcall(function() value = obj:get_field(field_name) end)
                    local info = value_resource_info(value)
                    table.insert(out.fields, {
                        declaring_type = declaring_type,
                        name = field_name,
                        type = field_type,
                        value = info.value,
                        value_type = info.type,
                        text = info.text,
                        path = info.path,
                    })
                end
                if #out.fields >= (field_limit or 48) then break end
            end
            td = get_parent_type_definition(td)
            depth = depth + 1
        end
    end)

    pcall(function()
        local td = obj:get_type_definition()
        if not td then return end
        for _, method in ipairs(td:get_methods()) do
            if #out.methods >= (method_limit or 32) then break end
            local name = method:get_name() or ""
            local ret = method:get_return_type()
            local ret_name = ret and ret:get_full_name() or ""
            local params = 999
            pcall(function() params = method:get_num_params() end)
            local is_getter = name:find("get_", 1, true) == 1
            local returns_value = ret_name ~= "" and ret_name ~= "System.Void"
            if params == 0 and is_getter and returns_value
                and (is_resource_probe_name(name) or is_resource_probe_name(ret_name)) then
                local value = nil
                local ok_call, err_call = pcall(function() value = obj:call(name) end)
                local info = value_resource_info(value)
                table.insert(out.methods, {
                    signature = method_signature(method),
                    ok = ok_call,
                    error = ok_call and "" or safe_string(err_call),
                    value = info.value,
                    value_type = info.type,
                    text = info.text,
                    path = info.path,
                })
            end
        end
    end)

    return out
end

local function component_type_is_grace_relevant(type_name)
    type_name = tostring(type_name or "")
    return type_name:find("A100")
        or type_name:find("Player")
        or type_name:find("Mesh")
        or type_name:find("Motion")
        or type_name:find("Render")
        or type_name:find("Model")
        or type_name:find("Material")
        or type_name:find("Figure")
        or type_name:find("Chara")
        or type_name:find("Character")
        or type_name:find("Costume")
end

local function run_component_resource_probe()
    local refs = get_local_player_refs()
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        local_player = refs.valid and true or false,
        local_error = refs.error or "",
        player = safe_string(refs.player),
        player_go = safe_string(refs.go),
        player_go_name = safe_string(refs.name),
        objects = {},
        component_names = {},
        resource_load_attempts = try_create_resource_matrix(DEFAULT_GRACE_RESOURCE_PATHS, 12),
    }

    if not refs.valid or not refs.go then
        state.component_resource_status = "failed: " .. safe_string(refs.error)
        pcall(function() json.dump_file(COMPONENT_RESOURCE_PROBE_FILE, report) end)
        return false, state.component_resource_status
    end

    table.insert(report.objects, collect_resource_rows_from_object("PlayerContext", refs.player, 48, 32))
    table.insert(report.objects, collect_resource_rows_from_object("PlayerGameObject", refs.go, 48, 32))
    local updater = nil
    pcall(function() updater = refs.player:call("get_Updater") end)
    table.insert(report.objects, collect_resource_rows_from_object("PlayerUpdater", updater, 64, 40))

    pcall(function()
        local components = refs.go:call("get_Components")
        if not components then return end
        local count = components:call("get_Count") or 0
        report.component_count = count
        local added = 0
        for i = 0, math.min(count - 1, 120) do
            pcall(function()
                local comp = components:call("get_Item", i)
                local type_name = trace_type_name(comp)
                table.insert(report.component_names, { index = i, type = type_name, value = safe_string(comp) })
                if component_type_is_grace_relevant(type_name) and added < 28 then
                    table.insert(report.objects, collect_resource_rows_from_object("Component[" .. tostring(i) .. "] " .. type_name, comp, 40, 28))
                    added = added + 1
                end
            end)
        end
        report.relevant_component_objects = added
    end)

    local path_hits = {}
    for _, obj in ipairs(report.objects) do
        for _, field in ipairs(obj.fields or {}) do
            add_unique(path_hits, field.path, 80)
        end
        for _, method in ipairs(obj.methods or {}) do
            add_unique(path_hits, method.path, 80)
        end
    end
    report.path_hits = path_hits

    local load_ok = 0
    for _, row in ipairs(report.resource_load_attempts or {}) do
        if row.ok then load_ok = load_ok + 1 end
    end
    state.component_resource_status = "dumped objects=" .. tostring(#report.objects)
        .. " components=" .. tostring(#report.component_names)
        .. " path_hits=" .. tostring(#path_hits)
        .. " resource_ok=" .. tostring(load_ok)
    pcall(function() json.dump_file(COMPONENT_RESOURCE_PROBE_FILE, report) end)
    return true, state.component_resource_status
end

local function find_component_by_type_name(go, pattern)
    local found = nil
    pcall(function()
        local components = go and go:call("get_Components")
        if not components then return end
        local count = components:call("get_Count") or 0
        for i = 0, math.min(count - 1, 160) do
            local comp = nil
            pcall(function() comp = components:call("get_Item", i) end)
            local type_name = trace_type_name(comp)
            if type_name:find(pattern, 1, true) then
                found = comp
                return
            end
        end
    end)
    return found
end

local function summarize_for_visual(label, obj, field_limit, method_limit)
    return {
        label = safe_string(label),
        value = safe_string(obj),
        type = trace_type_name(obj),
        fields = object_all_field_summary(label, obj, field_limit or 80),
        methods = object_method_summary(label, obj, {
            "get_", "set_", "Mesh", "Material", "Resource", "Prefab", "GameObject", "Transform",
            "Draw", "Visible", "Motion", "Bank", "create", "Create", "instantiate", "Instantiate",
        }, method_limit or 140),
    }
end

local function safe_enumerator_items(collection, limit)
    local rows = {}
    if not collection then return rows end

    pcall(function()
        local iter = collection:call("GetEnumerator")
        if not iter then return end
        for i = 0, (limit or 12) - 1 do
            local moved = iter:call("MoveNext")
            if not moved then break end
            local current = iter:call("get_Current")
            local key, value = nil, nil
            pcall(function() key = current:call("get_Key") end)
            pcall(function() value = current:call("get_Value") end)
            table.insert(rows, {
                index = i,
                current = safe_string(current),
                current_type = trace_type_name(current),
                key = safe_string(key),
                key_type = trace_type_name(key),
                value = safe_string(value),
                value_type = trace_type_name(value),
            })
        end
    end)

    if #rows > 0 then return rows end

    local count = trace_count(collection)
    for i = 0, math.min(count - 1, (limit or 12) - 1) do
        local item = trace_item(collection, i)
        table.insert(rows, {
            index = i,
            current = safe_string(item),
            current_type = trace_type_name(item),
            key = "",
            key_type = "",
            value = safe_string(item),
            value_type = trace_type_name(item),
        })
    end
    return rows
end

local function collect_visual_collection(label, collection, limit)
    local row = {
        label = safe_string(label),
        value = safe_string(collection),
        type = trace_type_name(collection),
        count = trace_count(collection),
        items = safe_enumerator_items(collection, limit or 12),
        item_details = {},
    }

    for _, item in ipairs(row.items) do
        local target = nil
        if item.value ~= "" then
            target = nil
        end
        -- Re-read from the collection rather than trying to convert strings back
        -- into objects. The item rows above are for orientation; details below
        -- are populated by collection-specific callers when they still hold refs.
    end
    return row
end

local function append_mesh_details_from_collection(report, label, collection, limit)
    local row = collect_visual_collection(label, collection, limit or 12)
    row.item_details = {}

    pcall(function()
        local iter = collection and collection:call("GetEnumerator")
        if not iter then return end
        for i = 0, (limit or 12) - 1 do
            local moved = iter:call("MoveNext")
            if not moved then break end
            local current = iter:call("get_Current")
            local value = nil
            pcall(function() value = current:call("get_Value") end)
            if not value then value = current end
            local detail = summarize_for_visual(label .. "[" .. tostring(i) .. "]", value, 80, 140)
            detail.nested = {}
            if trace_type_name(value):find("app.MeshUnit", 1, true) then
                local mesh_go, mesh = nil, nil
                pcall(function() mesh_go = value:call("get_GameObject") end)
                pcall(function() mesh = value:call("get_Mesh") end)
                table.insert(detail.nested, summarize_for_visual(label .. "[" .. tostring(i) .. "].GameObject", mesh_go, 80, 120))
                table.insert(detail.nested, summarize_for_visual(label .. "[" .. tostring(i) .. "].Mesh", mesh, 140, 180))
            end
            table.insert(row.item_details, detail)
        end
    end)

    if #row.item_details == 0 then
        local count = trace_count(collection)
        for i = 0, math.min(count - 1, (limit or 12) - 1) do
            local item = trace_item(collection, i)
            local detail = summarize_for_visual(label .. "[" .. tostring(i) .. "]", item, 80, 140)
            detail.nested = {}
            if trace_type_name(item):find("app.MeshUnit", 1, true) then
                local mesh_go, mesh = nil, nil
                pcall(function() mesh_go = item:call("get_GameObject") end)
                pcall(function() mesh = item:call("get_Mesh") end)
                table.insert(detail.nested, summarize_for_visual(label .. "[" .. tostring(i) .. "].GameObject", mesh_go, 80, 120))
                table.insert(detail.nested, summarize_for_visual(label .. "[" .. tostring(i) .. "].Mesh", mesh, 140, 180))
            end
            table.insert(row.item_details, detail)
        end
    end

    table.insert(report.collections, row)
end

local function run_visual_component_probe()
    local refs = get_local_player_refs()
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        local_player = refs.valid and true or false,
        local_error = refs.error or "",
        player_go = safe_string(refs.go),
        player_go_name = safe_string(refs.name),
        objects = {},
        collections = {},
    }

    if not refs.valid or not refs.go then
        state.visual_probe_status = "failed: " .. safe_string(refs.error)
        pcall(function() json.dump_file(VISUAL_COMPONENT_PROBE_FILE, report) end)
        return false, state.visual_probe_status
    end

    local mesh_controller = find_component_by_type_name(refs.go, "app.PlayerMeshController")
    local actor_mesh_controller = find_component_by_type_name(refs.go, "app.ActorPlayerMeshController")
    local motion = find_component_by_type_name(refs.go, "via.motion.Motion")
    local actor_motion = find_component_by_type_name(refs.go, "via.motion.ActorMotion")
    local updater = nil
    pcall(function() updater = refs.player:call("get_Updater") end)

    table.insert(report.objects, summarize_for_visual("PlayerGameObject", refs.go, 80, 140))
    table.insert(report.objects, summarize_for_visual("PlayerContext", refs.player, 80, 140))
    table.insert(report.objects, summarize_for_visual("Cp_A100Updater", updater, 120, 160))
    table.insert(report.objects, summarize_for_visual("PlayerMeshController", mesh_controller, 140, 180))
    table.insert(report.objects, summarize_for_visual("ActorPlayerMeshController", actor_mesh_controller, 100, 140))
    table.insert(report.objects, summarize_for_visual("Motion", motion, 100, 180))
    table.insert(report.objects, summarize_for_visual("ActorMotion", actor_motion, 80, 140))

    local mesh_unit_dictionary = nil
    local mesh_list = nil
    local mesh_parts_dictionary = nil
    local property_value_containers = nil
    pcall(function() mesh_unit_dictionary = mesh_controller:get_field("<MeshUnitDictionary>k__BackingField") end)
    pcall(function() mesh_list = mesh_controller:get_field("_MeshList") end)
    pcall(function() mesh_parts_dictionary = mesh_controller:get_field("_MeshPartsDictionary") end)
    pcall(function() property_value_containers = mesh_controller:get_field("_PropertyValueContainers") end)

    append_mesh_details_from_collection(report, "PlayerMeshController.MeshUnitDictionary", mesh_unit_dictionary, 20)
    append_mesh_details_from_collection(report, "PlayerMeshController.MeshList", mesh_list, 20)
    append_mesh_details_from_collection(report, "PlayerMeshController.MeshPartsDictionary", mesh_parts_dictionary, 12)
    append_mesh_details_from_collection(report, "PlayerMeshController.PropertyValueContainers", property_value_containers, 12)

    local harness_mesh = nil
    pcall(function() harness_mesh = actor_mesh_controller:get_field("_HarnessHolsterMesh") end)
    if harness_mesh then
        table.insert(report.objects, summarize_for_visual("ActorPlayerMeshController._HarnessHolsterMesh", harness_mesh, 100, 160))
    end

    state.visual_probe_status = "dumped objects=" .. tostring(#report.objects)
        .. " collections=" .. tostring(#report.collections)
    pcall(function() json.dump_file(VISUAL_COMPONENT_PROBE_FILE, report) end)
    return true, state.visual_probe_status
end

function type_surface_for_type(type_name, method_limit, field_limit)
    local row = {
        type = safe_string(type_name),
        found = false,
        levels = {},
    }
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then return end
        row.found = true
        local seen = {}
        local depth = 0
        while td and depth < 10 do
            local level_name = td:get_full_name() or "?"
            if seen[level_name] then break end
            seen[level_name] = true
            local level = {
                type = level_name,
                fields = {},
                methods = {},
            }
            local f_count = 0
            for _, field in ipairs(td:get_fields()) do
                local ftype = nil
                pcall(function() ftype = field:get_type() end)
                table.insert(level.fields, {
                    name = field:get_name() or "",
                    type = ftype and ftype:get_full_name() or "",
                    static = field:is_static() and true or false,
                })
                f_count = f_count + 1
                if f_count >= (field_limit or 80) then break end
            end
            local m_count = 0
            for _, method in ipairs(td:get_methods()) do
                table.insert(level.methods, method_signature(method))
                m_count = m_count + 1
                if m_count >= (method_limit or 160) then break end
            end
            table.insert(row.levels, level)
            td = get_parent_type_definition(td)
            depth = depth + 1
        end
    end)
    return row
end

function object_surface(label, obj, method_limit, field_limit)
    local type_name = trace_type_name(obj)
    local row = type_surface_for_type(type_name, method_limit or 160, field_limit or 80)
    row.label = safe_string(label)
    row.value = safe_string(obj)
    return row
end

function run_mesh_registration_probe()
    local refs = get_local_player_refs()
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        local_player = refs.valid and true or false,
        local_error = refs.error or "",
        objects = {},
        type_surfaces = {},
        collection_counts = {},
    }

    if not refs.valid or not refs.go then
        pcall(function() json.dump_file(MESH_REGISTRATION_PROBE_FILE, report) end)
        return false, "mesh registration probe failed: " .. safe_string(refs.error)
    end

    local mesh_controller = find_component_by_type_name(refs.go, "app.PlayerMeshController")
    local actor_mesh_controller = find_component_by_type_name(refs.go, "app.ActorPlayerMeshController")
    local mesh_unit_dictionary = nil
    local mesh_list = nil
    local mesh_parts_dictionary = nil
    local property_value_containers = nil
    pcall(function() mesh_unit_dictionary = mesh_controller:get_field("<MeshUnitDictionary>k__BackingField") end)
    pcall(function() mesh_list = mesh_controller:get_field("_MeshList") end)
    pcall(function() mesh_parts_dictionary = mesh_controller:get_field("_MeshPartsDictionary") end)
    pcall(function() property_value_containers = mesh_controller:get_field("_PropertyValueContainers") end)

    local first_unit = nil
    pcall(function()
        local iter = mesh_unit_dictionary and mesh_unit_dictionary:call("GetEnumerator")
        if not iter then return end
        if iter:call("MoveNext") then
            local current = iter:call("get_Current")
            pcall(function() first_unit = current:call("get_Value") end)
            if not first_unit then first_unit = current end
        end
    end)
    local first_unit_go, first_unit_mesh, first_unit_mesh_controller, first_parent_mesh_controller = nil, nil, nil, nil
    pcall(function() first_unit_go = first_unit:call("get_GameObject") end)
    pcall(function() first_unit_mesh = first_unit:call("get_Mesh") end)
    pcall(function() first_unit_mesh_controller = first_unit:call("get_MeshController") end)
    pcall(function() first_parent_mesh_controller = first_unit:call("get_ParentMeshController") end)

    report.collection_counts.mesh_unit_dictionary = trace_count(mesh_unit_dictionary)
    report.collection_counts.mesh_list = trace_count(mesh_list)
    report.collection_counts.mesh_parts_dictionary = trace_count(mesh_parts_dictionary)
    report.collection_counts.property_value_containers = trace_count(property_value_containers)

    table.insert(report.objects, object_surface("PlayerGameObject", refs.go, 220, 100))
    table.insert(report.objects, object_surface("PlayerTransform", refs.xform, 220, 100))
    table.insert(report.objects, object_surface("PlayerMeshController", mesh_controller, 260, 120))
    table.insert(report.objects, object_surface("ActorPlayerMeshController", actor_mesh_controller, 220, 100))
    table.insert(report.objects, object_surface("MeshUnitDictionary", mesh_unit_dictionary, 180, 80))
    table.insert(report.objects, object_surface("MeshList", mesh_list, 180, 80))
    table.insert(report.objects, object_surface("MeshPartsDictionary", mesh_parts_dictionary, 180, 80))
    table.insert(report.objects, object_surface("PropertyValueContainers", property_value_containers, 180, 80))
    table.insert(report.objects, object_surface("FirstMeshUnit", first_unit, 220, 100))
    table.insert(report.objects, object_surface("FirstMeshUnitGameObject", first_unit_go, 220, 100))
    table.insert(report.objects, object_surface("FirstMeshUnitMesh", first_unit_mesh, 260, 120))
    table.insert(report.objects, object_surface("FirstMeshUnitMeshController", first_unit_mesh_controller, 260, 120))
    table.insert(report.objects, object_surface("FirstMeshUnitParentMeshController", first_parent_mesh_controller, 260, 120))

    for _, type_name in ipairs({
        "app.MeshController",
        "app.CharacterMeshControllerBase",
        "app.PlayerMeshController",
        "app.ActorPlayerMeshController",
        "app.MeshUnit",
        "app.MeshController.PropertyKey",
        "app.MeshController.PropertyMetadata",
        "app.MeshController.PropertyValueContainer",
        "via.render.Mesh",
        "via.GameObject",
        "via.Transform",
        "via.Component",
        "via.Folder",
        "System.Collections.Generic.Dictionary`2<System.UInt32,app.MeshUnit>",
        "System.Collections.Generic.LinkedList`1<via.render.Mesh>",
    }) do
        table.insert(report.type_surfaces, type_surface_for_type(type_name, 220, 100))
    end

    pcall(function() json.dump_file(MESH_REGISTRATION_PROBE_FILE, report) end)
    return true, "mesh registration probe dumped objects=" .. tostring(#report.objects)
end
