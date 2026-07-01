-- Active load-phase injection path extracted from pre-split runtime lines 4613-5419.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

function re9mp_dump_load_phase_injection_probe(reason)
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        reason = safe_string(reason or "dump"),
        injection = {
            armed = state.load_phase_injection_armed and true or false,
            done = state.load_phase_injection_done and true or false,
            mode = safe_string(state.load_phase_injection_mode),
            status = safe_string(state.load_phase_injection_status),
            context = safe_string(state.load_phase_injection_context_text),
            context_ref_source = safe_string(state.load_phase_injection_context_ref_source),
            request_spawn_ok = state.load_phase_injection_request_spawn_ok and true or false,
            lines = state.load_phase_injection_lines or {},
        },
        character_manager = {},
        injected_context = {},
        local_player_refs = {},
    }

    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    report.character_manager.ref = safe_string(char_mgr)
    if char_mgr then
        local player_list = nil
        local pool_list = nil
        local spawn_data_db = nil
        local context_db = nil
        pcall(function() player_list = char_mgr:get_field("<PlayerContextList>k__BackingField") end)
        pcall(function() pool_list = char_mgr:get_field("<CharacterPool>k__BackingField") end)
        pcall(function() spawn_data_db = char_mgr:get_field("<CharacterSpawnDataDB>k__BackingField") end)
        pcall(function() context_db = char_mgr:get_field("<CharacterContextDB>k__BackingField") end)
        report.character_manager.counts = {
            player_contexts = trace_count(player_list),
            character_pool = trace_count(pool_list),
            spawn_data_db = trace_count(spawn_data_db),
            context_db = trace_count(context_db),
        }
        report.character_manager.player_contexts = {}
        report.character_manager.pool_a100 = {}
        for i = 0, math.min((report.character_manager.counts.player_contexts or 0) - 1, 7) do
            table.insert(report.character_manager.player_contexts, trace_context_summary(trace_item(player_list, i), i))
        end
        for i = 0, math.min((report.character_manager.counts.character_pool or 0) - 1, 63) do
            local row = trace_pool_summary(trace_item(pool_list, i), i)
            if row.updater_type == "app.Cp_A100Updater" or row.updater_type == "app.PlayerUpdaterBase" then
                table.insert(report.character_manager.pool_a100, row)
            end
        end

        local ctx = state.load_phase_injection_context
        if ctx then
            report.injected_context.lookups = {}
            for _, call_name in ipairs({
                "getContextRef(app.ContextID)",
                "getPlayerContextRef(app.ContextID)",
                "getSpawnDataRef(app.ContextID)",
                "isUsedContext(app.ContextID)",
                "isReservedContext(app.ContextID)",
            }) do
                local ok_lookup, result_lookup = pcall(function()
                    return char_mgr:call(call_name, ctx)
                end)
                report.injected_context.lookups[call_name] = ok_lookup
                    and probe_summary_text(result_lookup)
                    or ("ERR " .. safe_string(result_lookup))
            end
            local context_ref = nil
            for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
                local ok_ref, result = pcall(function()
                    return char_mgr:call(call_name, ctx)
                end)
                report.injected_context[call_name] = ok_ref and safe_string(result) or ("ERR " .. safe_string(result))
                if ok_ref and result and not context_ref then
                    context_ref = result
                end
            end
            if context_ref then
                report.injected_context.summary = trace_context_summary(context_ref, -1)
                local go = nil
                local xform = nil
                pcall(function() go = context_ref:call("get_GameObject") end)
                pcall(function() xform = context_ref:call("get_Transform") end)
                report.injected_context.game_object = safe_string(go)
                report.injected_context.game_object_name = safe_string(trace_call(go, "get_Name"))
                report.injected_context.transform = safe_string(xform)
                report.injected_context.position = read_position(xform)
                report.injected_context.rotation = read_rotation(xform)
                report.injected_context.updater = safe_string(trace_call(context_ref, "get_Updater"))
                report.injected_context.updater_type = trace_type_name(trace_call(context_ref, "get_Updater"))
                if go then
                    pcall(function() state.puppet_go = go:add_ref() end)
                    pcall(function()
                        state.puppet_xform = go:call("get_Transform")
                        if state.puppet_xform and state.puppet_xform.add_ref then
                            state.puppet_xform = state.puppet_xform:add_ref()
                        end
                    end)
                end
            end
        end
    end

    local refs = get_local_player_refs()
    if refs and refs.valid then
        report.local_player_refs = {
            player = safe_string(refs.player),
            context_id = safe_string(re9mp_trace_value(refs.player, {"get_ContextID"}, {
                "_ContextID",
                "<ContextID>k__BackingField",
            })),
            game_object = safe_string(refs.go),
            game_object_name = safe_string(trace_call(refs.go, "get_Name")),
            transform = safe_string(refs.xform),
            position = read_position(refs.xform),
            rotation = read_rotation(refs.xform),
            updater = safe_string(trace_call(refs.player, "get_Updater")),
            updater_type = trace_type_name(trace_call(refs.player, "get_Updater")),
        }
    end

    pcall(function() json.dump_file(DATA_PREFIX .. "load_phase_injection_probe.json", report) end)
    return true, "load-phase injection probe dumped: " .. safe_string(state.load_phase_injection_status)
end

function re9mp_append_load_phase_context_lookup_summary(lines, char_mgr, ctx, kind_grace, label)
    if not char_mgr or not ctx then
        table.insert(lines, safe_string(label) .. " skipped: char_mgr/ctx nil")
        return
    end
    for _, call_name in ipairs({
        "getContextRef(app.ContextID)",
        "getPlayerContextRef(app.ContextID)",
        "getSpawnDataRef(app.ContextID)",
        "isUsedContext(app.ContextID)",
        "isReservedContext(app.ContextID)",
    }) do
        local ok_lookup, result_lookup = pcall(function()
            return char_mgr:call(call_name, ctx)
        end)
        table.insert(lines, safe_string(label) .. " " .. call_name .. " -> "
            .. (ok_lookup and probe_summary_text(result_lookup) or ("ERR " .. safe_string(result_lookup))))
    end
    if kind_grace then
        re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, safe_string(label) .. " playerContextID")
    end
end

function re9mp_context_reserver_type_names()
    return {
        "app.ContextIDReserverWithEnumeration`1<app.CharacterKindID>",
        "app.ContextIDReserverWithEnumeration`1[[app.CharacterKindID]]",
        "app.ContextIDReserverWithEnumeration`1",
    }
end

function re9mp_find_context_reserver_type(lines, label)
    for _, type_name in ipairs(re9mp_context_reserver_type_names()) do
        local ok_td, td = pcall(function() return sdk.find_type_definition(type_name) end)
        table.insert(lines, safe_string(label) .. " find_type " .. type_name .. " -> "
            .. (ok_td and safe_string(td) or ("ERR " .. safe_string(td))))
        if ok_td and td then return td, type_name end
    end
    return nil, ""
end

function re9mp_create_context_reserver_holder(kind, raw_guid, lines, label)
    local td, td_name = re9mp_find_context_reserver_type(lines, label)
    local holder = nil
    local holder_type_name = ""
    for _, type_name in ipairs(re9mp_context_reserver_type_names()) do
        local ok_obj, obj = pcall(function() return sdk.create_instance(type_name) end)
        table.insert(lines, safe_string(label) .. " create_instance " .. type_name .. " -> "
            .. (ok_obj and safe_string(obj) or ("ERR " .. safe_string(obj))))
        if ok_obj and obj then
            holder = obj
            holder_type_name = type_name
            break
        end
    end
    if not holder then return nil, td, td_name end

    pcall(function() holder = holder:add_ref() end)
    for _, ctor in ipairs({".ctor()", ".ctor"}) do
        local ok_ctor, err_ctor = pcall(function() holder:call(ctor) end)
        table.insert(lines, safe_string(label) .. ":" .. ctor .. " -> "
            .. (ok_ctor and "ok" or ("ERR " .. safe_string(err_ctor))))
        if ok_ctor then break end
    end

    if raw_guid then set_named_field_for_probe(holder, "_RawContextID", raw_guid, label, lines) end
    set_named_field_for_probe(holder, "_BindTarget", "cp_A100", label, lines)
    if kind then set_named_field_for_probe(holder, "_Cache", kind, label, lines) end
    table.insert(lines, safe_string(label) .. " holder_type=" .. safe_string(holder_type_name)
        .. " ref=" .. safe_string(holder))
    pcall(function()
        table.insert(lines, safe_string(label) .. ":get_BindTarget -> " .. probe_summary_text(holder:call("get_BindTarget")))
    end)
    pcall(function()
        table.insert(lines, safe_string(label) .. ":get_TypeFQNName -> " .. probe_summary_text(holder:call("get_TypeFQNName")))
    end)
    return holder, td, td_name
end

function re9mp_create_context_reserver_array(td, td_name, holder, lines, label)
    if not holder then
        table.insert(lines, safe_string(label) .. " skipped: holder nil")
        return nil
    end
    if not sdk.create_managed_array then
        table.insert(lines, safe_string(label) .. " skipped: sdk.create_managed_array unavailable")
        return nil
    end

    local array = nil
    local ok_arr, arr_or_err = pcall(function() return sdk.create_managed_array(td, 1) end)
    table.insert(lines, safe_string(label) .. " create_managed_array(td,1) -> "
        .. (ok_arr and safe_string(arr_or_err) or ("ERR " .. safe_string(arr_or_err))))
    if ok_arr and arr_or_err then array = arr_or_err end
    if not array and td_name and td_name ~= "" then
        ok_arr, arr_or_err = pcall(function() return sdk.create_managed_array(td_name, 1) end)
        table.insert(lines, safe_string(label) .. " create_managed_array(name,1) -> "
            .. (ok_arr and safe_string(arr_or_err) or ("ERR " .. safe_string(arr_or_err))))
        if ok_arr and arr_or_err then array = arr_or_err end
    end
    if not array then return nil end

    pcall(function() array = array:add_ref() end)
    local set_ok = false
    for _, call_name in ipairs({"set_element", "SetValue(System.Object, System.Int32)", "SetValue"}) do
        local ok_set, err_set = false, nil
        if call_name == "set_element" then
            ok_set, err_set = pcall(function() array:set_element(0, holder) end)
        else
            ok_set, err_set = pcall(function() array:call(call_name, holder, 0) end)
        end
        table.insert(lines, safe_string(label) .. " " .. call_name .. "[0] -> "
            .. (ok_set and "ok" or ("ERR " .. safe_string(err_set))))
        if ok_set then set_ok = true; break end
    end
    table.insert(lines, safe_string(label) .. " type=" .. trace_type_name(array)
        .. " count=" .. tostring(trace_count(array)))
    table.insert(lines, safe_string(label) .. "[0]=" .. probe_summary_text(trace_item(array, 0)))
    if not set_ok then return nil end
    return array
end

function re9mp_create_context_reserver_array_for_holder(holder, lines, label)
    local td = nil
    local td_name = ""
    pcall(function()
        td = holder and holder:get_type_definition()
        td_name = td and td:get_full_name() or ""
    end)
    table.insert(lines, safe_string(label) .. " holder td=" .. safe_string(td_name) .. " ref=" .. safe_string(td))
    return re9mp_create_context_reserver_array(td, td_name, holder, lines, label)
end

function re9mp_register_context_reserver_array(char_mgr, array, unregister, lines, label)
    if not char_mgr or not array then
        table.insert(lines, safe_string(label) .. " skipped: char_mgr/array nil")
        return false
    end
    local method_prefix = unregister and "unregisterPlayerContextIDList" or "registerPlayerContextIDList"
    local ok_any = false
    for _, call_name in ipairs({
        method_prefix .. "(app.ContextIDReserverWithEnumeration`1<app.CharacterKindID>[])",
        method_prefix,
    }) do
        local ok_call, err_call = pcall(function() char_mgr:call(call_name, array) end)
        table.insert(lines, safe_string(label) .. " " .. call_name .. " -> "
            .. (ok_call and "ok" or ("ERR " .. safe_string(err_call))))
        if ok_call then ok_any = true; break end
    end
    return ok_any
end

function re9mp_append_player_context_id_query(lines, char_mgr, kind, label)
    for _, call_name in ipairs({"getPlayerContextID(app.CharacterKindID)", "getPlayerContextID"}) do
        local ok_pc, result_pc = pcall(function()
            return char_mgr:call(call_name, kind)
        end)
        table.insert(lines, safe_string(label) .. " " .. call_name .. "(cp_A100) -> "
            .. (ok_pc and probe_summary_text(result_pc) or ("ERR " .. safe_string(result_pc))))
    end
end

function re9mp_append_holder_core_summary(lines, holder, label)
    if not holder then
        table.insert(lines, safe_string(label) .. " holder=nil")
        return
    end
    table.insert(lines, safe_string(label) .. " holder=" .. safe_string(holder) .. " type=" .. trace_type_name(holder))
    for _, field_name in ipairs({"_BindTarget", "_Cache", "_RawContextID"}) do
        local ok_field, value = pcall(function() return holder:get_field(field_name) end)
        table.insert(lines, safe_string(label) .. "." .. field_name .. " -> "
            .. (ok_field and probe_summary_text(value) or ("ERR " .. safe_string(value))))
    end
    pcall(function()
        table.insert(lines, safe_string(label) .. ":get_BindTarget -> " .. probe_summary_text(holder:call("get_BindTarget")))
    end)
    pcall(function()
        table.insert(lines, safe_string(label) .. ":get_TypeFQNName -> " .. probe_summary_text(holder:call("get_TypeFQNName")))
    end)
end

function re9mp_run_context_reserver_probe(mode)
    local lines = {
        "scene=" .. safe_string(get_current_scene()),
        "mode=" .. safe_string(mode or ""),
    }
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    if not char_mgr or not kind_grace then
        table.insert(lines, "missing CharacterManager or cp_A100 kind")
    else
        re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "before")
        local existing_holder = find_player_context_id_holder(char_mgr, kind_grace, "cp_A100", lines)
        local existing_holder_array = re9mp_create_context_reserver_array_for_holder(existing_holder, lines, "ExistingPlayerContextIDHolderArray")
        re9mp_append_holder_core_summary(lines, existing_holder, "ExistingPlayerContextIDHolder.before")
        local ctx, ctx_lines, raw_guid = create_new_context_id()
        for _, line in ipairs(ctx_lines or {}) do table.insert(lines, line) end
        local holder, td, td_name = re9mp_create_context_reserver_holder(kind_grace, raw_guid, lines, "NewPlayerContextIDHolder")
        local array = re9mp_create_context_reserver_array(td, td_name, holder, lines, "NewPlayerContextIDHolderArray")
        if safe_string(mode or ""):find("mutate_existing", 1, true) then
            local old_raw = nil
            pcall(function() old_raw = existing_holder and existing_holder:get_field("_RawContextID") end)
            table.insert(lines, "mutate_existing old_raw=" .. probe_summary_text(old_raw))
            re9mp_register_context_reserver_array(char_mgr, existing_holder_array, true, lines, "mutate_unregister_existing")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "mutate_after_unregister_existing")
            if existing_holder and raw_guid then
                set_named_field_for_probe(existing_holder, "_RawContextID", raw_guid, "ExistingPlayerContextIDHolder.mutate", lines)
                set_named_field_for_probe(existing_holder, "_BindTarget", "cp_A100", "ExistingPlayerContextIDHolder.mutate", lines)
                if kind_grace then
                    set_named_field_for_probe(existing_holder, "_Cache", kind_grace, "ExistingPlayerContextIDHolder.mutate", lines)
                end
                re9mp_append_holder_core_summary(lines, existing_holder, "ExistingPlayerContextIDHolder.after_raw_set")
            end
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "mutate_after_raw_set_before_register")
            re9mp_register_context_reserver_array(char_mgr, existing_holder_array, false, lines, "mutate_register_existing_new_raw")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "mutate_after_register_existing_new_raw")
            if ctx then
                for _, call_name in ipairs({"getContextRef(app.ContextID)", "getPlayerContextRef(app.ContextID)", "isUsedContext(app.ContextID)"}) do
                    local ok_ref, result = pcall(function() return char_mgr:call(call_name, ctx) end)
                    table.insert(lines, "mutate_after_register_existing_new_raw " .. call_name .. "(new ctx) -> "
                        .. (ok_ref and probe_summary_text(result) or ("ERR " .. safe_string(result))))
                end
            end
            re9mp_register_context_reserver_array(char_mgr, existing_holder_array, true, lines, "mutate_unregister_existing_new_raw")
            if existing_holder and old_raw then
                set_named_field_for_probe(existing_holder, "_RawContextID", old_raw, "ExistingPlayerContextIDHolder.restore", lines)
                re9mp_append_holder_core_summary(lines, existing_holder, "ExistingPlayerContextIDHolder.after_restore")
            end
            re9mp_register_context_reserver_array(char_mgr, existing_holder_array, false, lines, "mutate_reregister_existing_old_raw")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "mutate_after_reregister_existing_old_raw")
        elseif safe_string(mode or ""):find("swap", 1, true) then
            re9mp_register_context_reserver_array(char_mgr, existing_holder_array, true, lines, "probe_unregister_existing")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_unregister_existing")
            re9mp_register_context_reserver_array(char_mgr, array, false, lines, "probe_register_new")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_register_new")
            if ctx then
                for _, call_name in ipairs({"getContextRef(app.ContextID)", "getPlayerContextRef(app.ContextID)", "isUsedContext(app.ContextID)"}) do
                    local ok_ref, result = pcall(function() return char_mgr:call(call_name, ctx) end)
                    table.insert(lines, "after_register_new " .. call_name .. "(new ctx) -> "
                        .. (ok_ref and probe_summary_text(result) or ("ERR " .. safe_string(result))))
                end
            end
            re9mp_register_context_reserver_array(char_mgr, array, true, lines, "probe_unregister_new")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_unregister_new")
            re9mp_register_context_reserver_array(char_mgr, existing_holder_array, false, lines, "probe_reregister_existing")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_reregister_existing")
        elseif safe_string(mode or ""):find("register", 1, true) then
            re9mp_register_context_reserver_array(char_mgr, array, false, lines, "probe_register")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_register")
            if ctx then
                for _, call_name in ipairs({"getContextRef(app.ContextID)", "getPlayerContextRef(app.ContextID)", "isUsedContext(app.ContextID)"}) do
                    local ok_ref, result = pcall(function() return char_mgr:call(call_name, ctx) end)
                    table.insert(lines, "after_register " .. call_name .. "(new ctx) -> "
                        .. (ok_ref and probe_summary_text(result) or ("ERR " .. safe_string(result))))
                end
            end
            re9mp_register_context_reserver_array(char_mgr, array, true, lines, "probe_unregister")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_unregister")
        end
    end
    pcall(function()
        json.dump_file(DATA_PREFIX .. "context_reserver_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            mode = safe_string(mode or ""),
            lines = lines,
        })
    end)
    state.character_spawn_status = "context reserver probe dumped"
    return true, state.character_spawn_status
end

local function find_pending_player_context(char_mgr, lines)
    if not char_mgr then return nil end
    local player_list = nil
    pcall(function() player_list = char_mgr:get_field("<PlayerContextList>k__BackingField") end)
    local count = trace_count(player_list)
    table.insert(lines, "pending PlayerContextList count=" .. tostring(count))
    for i = count - 1, 0, -1 do
        local ctx = trace_item(player_list, i)
        if ctx then
            local go = nil
            local updater = nil
            local active = nil
            pcall(function() go = ctx:call("get_GameObject") end)
            pcall(function() updater = ctx:call("get_Updater") end)
            pcall(function() active = ctx:get_field("<Active>k__BackingField") end)
            table.insert(lines, "pending PlayerContext[" .. tostring(i) .. "] active=" .. safe_string(active)
                .. " go=" .. safe_string(go) .. " updater=" .. safe_string(updater))
            if not go and not updater then
                pcall(function() ctx = ctx:add_ref() end)
                return ctx
            end
        end
    end
    return nil
end

function find_player_context_id_holder(char_mgr, kind, bind_target, lines)
    if not char_mgr then return nil end
    local holder_list = nil
    pcall(function() holder_list = char_mgr:get_field("<PlayerContextIDHolder>k__BackingField") end)
    local count = trace_count(holder_list)
    table.insert(lines, "PlayerContextIDHolder count=" .. tostring(count))
    for i = 0, math.min(count - 1, 15) do
        local holder = trace_item(holder_list, i)
        if holder then
            local target = nil
            local bind = nil
            pcall(function() target = holder:call("get_BindTarget") end)
            pcall(function() bind = holder:get_field("_BindTarget") end)
            local target_text = probe_summary_text(target)
            local bind_text = safe_string(bind)
            table.insert(lines, "PlayerContextIDHolder[" .. tostring(i) .. "] bind=" .. bind_text
                .. " target=" .. target_text .. " ref=" .. safe_string(holder))
            if (bind_target and bind_text == bind_target)
                or (kind and target and safe_string(target) == safe_string(kind)) then
                pcall(function()
                    if holder.add_ref then holder = holder:add_ref() end
                end)
                return holder, i
            end
        end
    end
    return nil
end

function re9mp_maybe_run_load_phase_player_clone_injection(control, source_setting, trigger)
    if not state.load_phase_injection_armed
        or state.load_phase_injection_done
        or state.load_phase_injection_guard then
        return false, "load-phase injection not armed"
    end

    state.load_phase_injection_guard = true
    state.load_phase_injection_done = true
    state.load_phase_injection_armed = false
    state.load_phase_injection_pending_control = nil
    state.load_phase_injection_pending_setting = nil

    local lines = {
        "trigger=" .. safe_string(trigger),
        "scene=" .. safe_string(get_current_scene()),
        "mode=" .. safe_string(state.load_phase_injection_mode),
    }
    for _, line in ipairs(state.load_phase_injection_pre_lines or {}) do
        table.insert(lines, line)
    end
    state.load_phase_injection_lines = lines

    local ok_run, err_run = pcall(function()
        local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
        if not char_mgr then
            table.insert(lines, "CharacterManager not found")
            state.load_phase_injection_status = "failed: CharacterManager not found"
            return
        end
        if not control then
            table.insert(lines, "LevelPlayerCreateController not captured")
            state.load_phase_injection_status = "failed: controller not captured"
            return
        end

        local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
        local ctx, ctx_lines, raw_guid = create_new_context_id()
        for _, line in ipairs(ctx_lines or {}) do table.insert(lines, line) end
        if not kind_grace or not ctx then
            state.load_phase_injection_status = "failed: missing cp_A100 kind or ContextID"
            return
        end

        pcall(function() ctx = ctx:add_ref() end)
        state.load_phase_injection_context = ctx
        state.last_spawn_context = ctx
        pcall(function() state.load_phase_injection_context_text = safe_string(ctx:call("ToString")) end)
        state.last_spawn_context_text = state.load_phase_injection_context_text
        state.load_phase_injection_context_ref_source = ""
        state.load_phase_injection_request_spawn_ok = false

        local mode = safe_string(state.load_phase_injection_mode)
        local use_holder_register = mode == "holder_register_setup_create" or mode == "holder_swap_setup_create"
        local use_holder_swap = mode == "holder_swap_setup_create"
        re9mp_append_spawn_control_identity_summary(lines, "Control.real_post_setup", control, 140)

        local setting_source = source_setting
        if not setting_source then
            local _, _, default_setting, bundle_err = get_spawn_control_bundle(char_mgr, kind_grace, lines)
            table.insert(lines, "fallback bundle -> " .. safe_string(bundle_err))
            setting_source = default_setting
        end
        if not setting_source then
            state.load_phase_injection_status = "failed: source CreateSetting not captured"
            return
        end
        append_create_setting_summary(lines, "CreateSetting.real_arg", setting_source)

        if mode == "diagnose_only" then
            state.load_phase_injection_status = "diagnosed real setup control"
            state.character_spawn_status = "load-phase injection " .. state.load_phase_injection_status
            state.puppet_status = state.character_spawn_status
            return
        end

        local setting = make_controller_create_setting(setting_source, kind_grace, lines)
        append_create_setting_summary(lines, "CreateSetting.clone_initial", setting)
        set_fields_by_type_or_name(setting, "app.ContextID", {"SpawnContextID", "ContextID"}, ctx, "CreateSetting", lines)
        set_named_field_for_probe(setting, "_ControlCharaId", "cp_A100", "CreateSetting", lines)
        set_named_field_for_probe(setting, "_ControlCharaIdCache", kind_grace, "CreateSetting", lines)

        local old_spawn_context = nil
        local old_game_object_guid = nil
        local managed_context_ids = nil
        local old_managed_context_ids = {}
        local player_id_holder = nil
        local old_player_id_raw_guid = nil
        local old_request_end = nil
        local old_permitted = nil
        local old_init_suspended = nil
        local holder_register_array = nil
        local holder_register_registered = false
        local holder_original_array = nil
        local holder_original_unregistered = false
        pcall(function() old_spawn_context = control:get_field("_SpawnContextID") end)
        pcall(function() old_game_object_guid = control:get_field("_GameObjectGuid") end)
        pcall(function() managed_context_ids = control:call("app.ICharacterSpawnControl.getAllManagedContextID()") end)
        old_managed_context_ids = collect_iterable_values(managed_context_ids, 16)
        player_id_holder = find_player_context_id_holder(char_mgr, kind_grace, "cp_A100", lines)
        pcall(function() old_player_id_raw_guid = player_id_holder and player_id_holder:get_field("_RawContextID") end)
        pcall(function() old_request_end = control:get_field("IsSpawnRequestEnd") end)
        pcall(function() old_permitted = control:get_field("<HasPermittedSpawn>k__BackingField") end)
        pcall(function() old_init_suspended = control:get_field("_InitStateSuspended") end)
        table.insert(lines, "control old _SpawnContextID=" .. safe_string(old_spawn_context)
            .. " _GameObjectGuid=" .. safe_string(old_game_object_guid)
            .. " managed_ids=" .. tostring(#old_managed_context_ids)
            .. " holder=" .. safe_string(player_id_holder)
            .. " holderRaw=" .. safe_string(old_player_id_raw_guid)
            .. " IsSpawnRequestEnd=" .. safe_string(old_request_end)
            .. " HasPermitted=" .. safe_string(old_permitted)
            .. " InitSuspended=" .. safe_string(old_init_suspended))
        append_iterable_summary(lines, "Control.managed_ids.before_mutation", managed_context_ids, 16)

        if raw_guid then
            set_named_field_for_probe(control, "_GameObjectGuid", raw_guid, "Control", lines)
        else
            table.insert(lines, "Control set _GameObjectGuid skipped: raw guid nil")
        end
        if use_holder_register then
            table.insert(lines, "PlayerContextIDHolder.cp_A100 raw mutation skipped: using registered new holder")
            local new_holder, holder_td, holder_td_name = re9mp_create_context_reserver_holder(kind_grace, raw_guid, lines, "InjectedPlayerContextIDHolder")
            holder_register_array = re9mp_create_context_reserver_array(holder_td, holder_td_name, new_holder, lines, "InjectedPlayerContextIDHolderArray")
            if use_holder_swap and player_id_holder then
                holder_original_array = re9mp_create_context_reserver_array_for_holder(player_id_holder, lines, "OriginalPlayerContextIDHolderArray")
                holder_original_unregistered = re9mp_register_context_reserver_array(char_mgr, holder_original_array, true, lines, "injection_holder_unregister_original")
                re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_injection_holder_unregister_original")
            elseif use_holder_swap then
                table.insert(lines, "injection holder swap skipped original unregister: player_id_holder nil")
            end
            holder_register_registered = re9mp_register_context_reserver_array(char_mgr, holder_register_array, false, lines, "injection_holder_register")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_injection_holder_register")
        elseif player_id_holder and raw_guid then
            set_named_field_for_probe(player_id_holder, "_RawContextID", raw_guid, "PlayerContextIDHolder.cp_A100", lines)
            set_named_field_for_probe(player_id_holder, "_BindTarget", "cp_A100", "PlayerContextIDHolder.cp_A100", lines)
            if kind_grace then
                set_named_field_for_probe(player_id_holder, "_Cache", kind_grace, "PlayerContextIDHolder.cp_A100", lines)
            end
            local player_context_id_after = nil
            for _, call_name in ipairs({"getPlayerContextID(app.CharacterKindID)", "getPlayerContextID"}) do
                local ok_pc, result_pc = pcall(function()
                    return char_mgr:call(call_name, kind_grace)
                end)
                table.insert(lines, call_name .. "(cp_A100 after holder set) -> "
                    .. (ok_pc and probe_summary_text(result_pc) or ("ERR " .. safe_string(result_pc))))
                if ok_pc and result_pc and not player_context_id_after then player_context_id_after = result_pc end
            end
        else
            table.insert(lines, "PlayerContextIDHolder.cp_A100 set _RawContextID skipped")
        end
        set_named_field_for_probe(control, "_SpawnContextID", ctx, "Control", lines)
        set_named_field_for_probe(control, "IsSpawnRequestEnd", false, "Control", lines)
        set_named_field_for_probe(control, "<HasPermittedSpawn>k__BackingField", false, "Control", lines)
        set_named_field_for_probe(control, "_InitStateSuspended", false, "Control", lines)
        if managed_context_ids and #old_managed_context_ids > 0 then
            local ok_clear, err_clear = false, nil
            for _, call_name in ipairs({"Clear()", "Clear"}) do
                ok_clear, err_clear = pcall(function() managed_context_ids:call(call_name) end)
                table.insert(lines, "Control managed_ids " .. call_name .. " -> "
                    .. (ok_clear and "ok" or ("ERR " .. safe_string(err_clear))))
                if ok_clear then break end
            end
            local ok_add, err_add = false, nil
            for _, call_name in ipairs({"Add(app.ContextID)", "Add"}) do
                ok_add, err_add = pcall(function() managed_context_ids:call(call_name, ctx) end)
                table.insert(lines, "Control managed_ids " .. call_name .. "(new ctx) -> "
                    .. (ok_add and "ok" or ("ERR " .. safe_string(err_add))))
                if ok_add then break end
            end
            append_iterable_summary(lines, "Control.managed_ids.after_mutation", managed_context_ids, 16)
        else
            table.insert(lines, "Control managed_ids mutation skipped: set nil or old ids empty")
        end
        re9mp_append_spawn_control_identity_summary(lines, "Control.after_set", control, 140)

        for _, call_name in ipairs({"registerSpawnGroup(app.ICharacterSpawnControl)", "registerSpawnGroup"}) do
            local ok_group, err_group = pcall(function()
                char_mgr:call(call_name, control)
            end)
            table.insert(lines, call_name .. "(load-phase control) -> " .. (ok_group and "ok" or ("ERR " .. safe_string(err_group))))
            if ok_group then break end
        end

        local ok_setup, err_setup = pcall(function()
            control:call("setupControlCharacter(app.LevelPlayerCreateController.CreateSetting)", setting)
        end)
        table.insert(lines, "Control:setupControlCharacter(load-phase clone) -> " .. (ok_setup and "ok" or ("ERR " .. safe_string(err_setup))))
        re9mp_append_spawn_control_identity_summary(lines, "Control.after_setup", control, 140)

        local context_ref = nil
        for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
            local ok_ref, result = pcall(function()
                return char_mgr:call(call_name, ctx)
            end)
            table.insert(lines, call_name .. "(load-phase after setup) -> " .. (ok_ref and safe_string(result) or ("ERR " .. safe_string(result))))
            if ok_ref and result and not context_ref then
                context_ref = result
                state.load_phase_injection_context_ref_source = call_name .. " after setup"
                pcall(function() context_ref = context_ref:add_ref() end)
            end
        end
        if not context_ref then
            context_ref = find_pending_player_context(char_mgr, lines)
            table.insert(lines, "pending PlayerContext fallback -> " .. safe_string(context_ref))
            if context_ref then
                state.load_phase_injection_context_ref_source = "pending PlayerContext fallback"
            end
        end
        re9mp_append_load_phase_context_lookup_summary(lines, char_mgr, ctx, kind_grace, "after_setup_lookup")

        if context_ref and mode ~= "setup_only" then
            local ok_common, err_common = pcall(function()
                control:call("setupCommonMessageKind(app.LevelPlayerCreateController.CreateSetting, app.CharacterContext)", setting, context_ref)
            end)
            table.insert(lines, "Control:setupCommonMessageKind(load-phase clone) -> " .. (ok_common and "ok" or ("ERR " .. safe_string(err_common))))
        elseif not context_ref then
            table.insert(lines, "Control:setupCommonMessageKind skipped: no context after setup")
        end

        if mode == "setup_request_spawn" then
            local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
            local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
            local ok_spawn, err_spawn = pcall(function()
                char_mgr:call(
                    "requestSpawn(app.ContextID, app.CharacterKindID, app.MontageID, System.Int32, System.Boolean, app.CharacterUsePurposeFlag)",
                    ctx,
                    kind_grace,
                    montage_invalid,
                    0,
                    false,
                    purpose_default
                )
            end)
            state.load_phase_injection_request_spawn_ok = ok_spawn and true or false
            table.insert(lines, "CharacterManager:requestSpawn(load-phase ctx) -> "
                .. (ok_spawn and "ok" or ("ERR " .. safe_string(err_spawn))))
            re9mp_append_load_phase_context_lookup_summary(lines, char_mgr, ctx, kind_grace, "after_requestSpawn_lookup")
        elseif mode == "setup_create" or mode == "holder_register_setup_create" or mode == "holder_swap_setup_create" or mode == "create" or mode == "full" then
            local ok_create, err_create = pcall(function()
                control:call("createControlCharacter()")
            end)
            table.insert(lines, "Control:createControlCharacter(load-phase clone) -> " .. (ok_create and "ok" or ("ERR " .. safe_string(err_create))))
            re9mp_append_spawn_control_identity_summary(lines, "Control.after_create", control, 140)
        else
            table.insert(lines, "Control:createControlCharacter skipped for mode=" .. mode)
        end

        for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
            local ok_ref, result = pcall(function()
                return char_mgr:call(call_name, ctx)
            end)
            table.insert(lines, call_name .. "(load-phase after create) -> " .. (ok_ref and safe_string(result) or ("ERR " .. safe_string(result))))
            if ok_ref and result and not context_ref then
                context_ref = result
                state.load_phase_injection_context_ref_source = call_name .. " after create/requestSpawn"
                pcall(function() context_ref = context_ref:add_ref() end)
            end
        end

        if context_ref then
            pcall(function()
                table.insert(lines, "Injected context get_GameObject -> " .. safe_string(context_ref:call("get_GameObject")))
            end)
            pcall(function()
                table.insert(lines, "Injected context get_Updater -> " .. safe_string(context_ref:call("get_Updater")))
            end)
        end

        if holder_register_registered then
            re9mp_register_context_reserver_array(char_mgr, holder_register_array, true, lines, "injection_holder_unregister")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_injection_holder_unregister")
        end
        if holder_original_unregistered then
            re9mp_register_context_reserver_array(char_mgr, holder_original_array, false, lines, "injection_holder_reregister_original")
            re9mp_append_player_context_id_query(lines, char_mgr, kind_grace, "after_injection_holder_reregister_original")
        end
        pcall(function() control:set_field("_SpawnContextID", old_spawn_context) end)
        if old_game_object_guid ~= nil then pcall(function() control:set_field("_GameObjectGuid", old_game_object_guid) end) end
        if player_id_holder and old_player_id_raw_guid ~= nil then
            set_named_field_for_probe(player_id_holder, "_RawContextID", old_player_id_raw_guid, "PlayerContextIDHolder.cp_A100.restore", lines)
            set_named_field_for_probe(player_id_holder, "_BindTarget", "cp_A100", "PlayerContextIDHolder.cp_A100.restore", lines)
            if kind_grace then
                set_named_field_for_probe(player_id_holder, "_Cache", kind_grace, "PlayerContextIDHolder.cp_A100.restore", lines)
            end
        end
        if managed_context_ids and #old_managed_context_ids > 0 then
            for _, call_name in ipairs({"Clear()", "Clear"}) do
                local ok_clear = pcall(function() managed_context_ids:call(call_name) end)
                if ok_clear then break end
            end
            for _, old_id in ipairs(old_managed_context_ids) do
                for _, call_name in ipairs({"Add(app.ContextID)", "Add"}) do
                    local ok_add = pcall(function() managed_context_ids:call(call_name, old_id) end)
                    if ok_add then break end
                end
            end
            append_iterable_summary(lines, "Control.managed_ids.after_restore", managed_context_ids, 16)
        end
        if old_request_end ~= nil then pcall(function() control:set_field("IsSpawnRequestEnd", old_request_end) end) end
        if old_permitted ~= nil then pcall(function() control:set_field("<HasPermittedSpawn>k__BackingField", old_permitted) end) end
        if old_init_suspended ~= nil then pcall(function() control:set_field("_InitStateSuspended", old_init_suspended) end) end

        state.load_phase_injection_status = context_ref
            and ("triggered; context=" .. safe_string(state.load_phase_injection_context_text)
                .. " source=" .. safe_string(state.load_phase_injection_context_ref_source))
            or ("triggered; no context=" .. safe_string(state.load_phase_injection_context_text))
        state.character_spawn_status = "load-phase injection " .. state.load_phase_injection_status
        state.puppet_status = state.character_spawn_status
    end)

    if not ok_run then
        table.insert(lines, "ERROR " .. safe_string(err_run))
        state.load_phase_injection_status = "error: " .. safe_string(err_run)
        state.character_spawn_status = state.load_phase_injection_status
        state.puppet_status = state.load_phase_injection_status
    end

    state.load_phase_injection_guard = false
    state.load_phase_injection_followup_until = now() + 8.0
    state.load_phase_injection_next_dump = 0
    re9mp_dump_load_phase_injection_probe("after injection")
    push_level_trace_note("load_phase_injection " .. safe_string(state.load_phase_injection_status))
    return ok_run, state.load_phase_injection_status
end

function re9mp_arm_load_phase_player_clone_injection(mode)
    local requested = safe_string(mode or "")
    if requested == "" then requested = "setup_create" end
    if requested ~= "diagnose_only"
        and requested ~= "setup_only" and requested ~= "setup_common"
        and requested ~= "setup_request_spawn"
        and requested ~= "setup_create" and requested ~= "holder_register_setup_create"
        and requested ~= "holder_swap_setup_create" and requested ~= "create"
        and requested ~= "full" then
        return false, "mode must be diagnose_only, setup_only, setup_common, setup_request_spawn, setup_create, holder_register_setup_create, holder_swap_setup_create, create, or full"
    end

    clear_puppet_refs("despawned")
    state.remote_samples = {}
    state.remote_last_seq = nil
    state.remote_prev_seq = nil
    cfg.local_dummy = false
    cfg.auto_spawn_puppet = false
    cfg.level_trace_enabled = true
    cfg.pool_trace_enabled = true
    cfg.bind_trace_enabled = true
    cfg.controller_trace_enabled = true
    save_cfg()

    state.trace_mode = "load_phase_injection"
    state.load_phase_injection_armed = true
    state.load_phase_injection_done = false
    state.load_phase_injection_guard = false
    state.load_phase_injection_mode = requested
    state.load_phase_injection_status = "armed mode=" .. requested
    state.load_phase_injection_lines = {"armed at scene=" .. safe_string(get_current_scene())}
    state.load_phase_injection_context = nil
    state.load_phase_injection_context_text = ""
    state.load_phase_injection_pending_control = nil
    state.load_phase_injection_pending_setting = nil
    state.load_phase_injection_pre_lines = {}
    state.load_phase_injection_followup_until = 0
    state.load_phase_injection_next_dump = 0
    state.load_phase_injection_context_ref_source = ""
    state.load_phase_injection_request_spawn_ok = false

    state.level_trace_enabled = true
    state.pool_trace_enabled = true
    state.bind_trace_enabled = true
    state.spawn_hook_enabled = true
    state.spawn_hook_events = {}
    state.spawn_hook_dirty = true
    state.spawn_hook_status = "cleared for load-phase injection"
    reset_level_trace("load-phase injection " .. requested)
    reset_pool_trace("load-phase injection " .. requested)
    reset_bind_trace("load-phase injection " .. requested)
    push_pool_trace_event("load-phase injection armed", true)
    install_spawn_observer_hooks()
    install_bind_trace_hooks()
    re9mp_dump_load_phase_injection_probe("armed")
    dump_spawn_hook_log(true)
    dump_level_trace(true)
    dump_pool_trace(true)
    dump_bind_trace(true)
    return true, "load-phase player clone injection armed mode=" .. requested .. "; go Main Menu -> load gameplay"
end

function re9mp_cancel_load_phase_player_clone_injection()
    state.load_phase_injection_armed = false
    state.load_phase_injection_guard = false
    state.load_phase_injection_pending_control = nil
    state.load_phase_injection_pending_setting = nil
    state.load_phase_injection_pre_lines = {}
    state.load_phase_injection_status = "cancelled"
    re9mp_dump_load_phase_injection_probe("cancelled")
    return true, "load-phase injection cancelled"
end

function re9mp_poll_load_phase_player_clone_injection()
    if not state.load_phase_injection_done then return end
    if (state.load_phase_injection_followup_until or 0) <= 0 then return end
    local t = now()
    if t > state.load_phase_injection_followup_until then
        state.load_phase_injection_followup_until = 0
        re9mp_dump_load_phase_injection_probe("followup final")
        return
    end
    if t >= (state.load_phase_injection_next_dump or 0) then
        state.load_phase_injection_next_dump = t + 0.5
        re9mp_dump_load_phase_injection_probe("followup")
    end
end
