-- Context and controller helper paths extracted from pre-split runtime lines 3484-4612.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function run_request_spawn_empty_context()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "requestSpawn object probe failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local context_empty = get_static_field_value("app.ContextID", {"Empty"})
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
    local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
    if not context_empty or not kind_grace or not montage_invalid then
        state.character_spawn_status = "requestSpawn object probe failed: missing ContextID/Kind/Montage"
        return false, state.character_spawn_status
    end

    local ok, err = pcall(function()
        char_mgr:call(
            "requestSpawn(app.ContextID, app.CharacterKindID, app.MontageID, System.Int32, System.Boolean, app.CharacterUsePurposeFlag)",
            context_empty,
            kind_grace,
            montage_invalid,
            0,
            false,
            purpose_default
        )
    end)

    dump_spawn_hook_log(true)
    if ok then
        state.character_spawn_status = "requestSpawn sent with ContextID.Empty/cp_A100 object args"
        state.puppet_status = "CharacterManager requestSpawn sent; check for new Grace"
        return true, state.character_spawn_status
    end
    state.character_spawn_status = "requestSpawn object probe failed: " .. safe_string(err)
    state.puppet_status = state.character_spawn_status
    return false, state.character_spawn_status
end

local function create_new_context_id()
    local lines = {}
    local guid = nil
    local ctx = nil

    local guid_td = sdk.find_type_definition("System.Guid")
    if guid_td then
        for _, method in ipairs(guid_td:get_methods()) do
            local name = method:get_name() or ""
            if name == "NewGuid" then
                local ok, result = pcall(function() return method:call(nil) end)
                table.insert(lines, "System.Guid.NewGuid -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
                if ok and result then guid = result end
                break
            end
        end
    else
        table.insert(lines, "System.Guid type not found")
    end

    local ok_ctx, ctx_or_err = pcall(function()
        return sdk.create_instance("app.ContextID")
    end)
    table.insert(lines, "sdk.create_instance(app.ContextID) -> " .. (ok_ctx and safe_string(ctx_or_err) or ("ERR " .. safe_string(ctx_or_err))))
    if ok_ctx and ctx_or_err then
        ctx = ctx_or_err
        if guid then
            for _, call_name in ipairs({".ctor(System.Guid)", ".ctor"}) do
                local ok, err = pcall(function()
                    ctx:call(call_name, guid)
                end)
                table.insert(lines, "ContextID:" .. call_name .. "(guid) -> " .. (ok and "ok" or ("ERR " .. safe_string(err))))
                if ok then break end
            end
        end
        pcall(function() table.insert(lines, "ContextID.ToString -> " .. safe_string(ctx:call("ToString"))) end)
        pcall(function() table.insert(lines, "ContextID.get_IsEmpty -> " .. safe_string(ctx:call("get_IsEmpty"))) end)
        pcall(function() table.insert(lines, "ContextID.get_RawID -> " .. safe_string(ctx:call("get_RawID"))) end)
    end

    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if char_mgr and ctx then
        for _, call_name in ipairs({"isUsedContext(app.ContextID)", "isUsedContext"}) do
            local ok, result = pcall(function() return char_mgr:call(call_name, ctx) end)
            table.insert(lines, call_name .. "(new ctx) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        end
    end

    return ctx, lines, guid
end

local function run_context_create_probe()
    local ctx, lines = create_new_context_id()
    pcall(function()
        json.dump_file(DATA_PREFIX .. "context_create_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            ok = ctx ~= nil,
            lines = lines,
        })
    end)
    state.character_spawn_status = table.concat(lines, " | ")
    return ctx ~= nil, state.character_spawn_status
end

local function run_request_spawn_new_context()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "requestSpawn new context failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local ctx, lines = create_new_context_id()
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
    local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
    if not ctx or not kind_grace or not montage_invalid then
        state.character_spawn_status = "requestSpawn new context failed: missing ContextID/Kind/Montage | " .. table.concat(lines, " | ")
        return false, state.character_spawn_status
    end

    pcall(function() ctx = ctx:add_ref() end)
    state.last_spawn_context = ctx
    pcall(function() state.last_spawn_context_text = safe_string(ctx:call("ToString")) end)

    local ok, err = pcall(function()
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

    dump_spawn_hook_log(true)
    if ok then
        state.character_spawn_status = "requestSpawn sent with new ContextID " .. safe_string(state.last_spawn_context_text)
        state.puppet_status = "New ContextID requestSpawn sent; check for Grace"
        return true, state.character_spawn_status
    end
    state.character_spawn_status = "requestSpawn new context failed: " .. safe_string(err)
    state.puppet_status = state.character_spawn_status
    return false, state.character_spawn_status
end

local function duplicate_player_spawn_data(char_mgr, kind_grace, lines)
    local player_context_id = nil
    for _, call_name in ipairs({"getPlayerContextID(app.CharacterKindID)", "getPlayerContextID"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, kind_grace)
        end)
        table.insert(lines, call_name .. "(cp_A100) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not player_context_id then
            player_context_id = result
        end
    end
    if not player_context_id then
        return nil, "player ContextID for cp_A100 not found"
    end

    local player_spawn_data = nil
    for _, call_name in ipairs({"getSpawnDataRef(app.ContextID)", "getSpawnDataRef"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, player_context_id)
        end)
        table.insert(lines, call_name .. "(PlayerContextID.cp_A100) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not player_spawn_data then
            player_spawn_data = result
        end
    end
    if not player_spawn_data then
        return nil, "player spawn data for cp_A100 not found"
    end

    for _, call_name in ipairs({"duplicate()", "duplicate"}) do
        local ok, result = pcall(function()
            return player_spawn_data:call(call_name)
        end)
        table.insert(lines, "PlayerSpawnData:" .. call_name .. " -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result then
            pcall(function() result = result:add_ref() end)
            return result, "duplicated via " .. call_name
        end
    end

    local ok_new, copy_or_err = pcall(function()
        return sdk.create_instance("app.PlayerSpawnData")
    end)
    table.insert(lines, "sdk.create_instance(app.PlayerSpawnData) -> " .. (ok_new and safe_string(copy_or_err) or ("ERR " .. safe_string(copy_or_err))))
    if ok_new and copy_or_err then
        for _, ctor in ipairs({".ctor(app.PlayerSpawnData)", ".ctor"}) do
            local ok_ctor, err = pcall(function()
                copy_or_err:call(ctor, player_spawn_data)
            end)
            table.insert(lines, "PlayerSpawnData:" .. ctor .. "(player_spawn_data) -> " .. (ok_ctor and "ok" or ("ERR " .. safe_string(err))))
            if ok_ctor then
                pcall(function() copy_or_err = copy_or_err:add_ref() end)
                return copy_or_err, "copied via " .. ctor
            end
        end
    end

    return nil, "could not duplicate player spawn data"
end

local function run_request_spawn_registered_duplicate()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "registered duplicate spawn failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local ctx, lines = create_new_context_id()
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
    local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
    if not ctx or not kind_grace or not montage_invalid then
        state.character_spawn_status = "registered duplicate spawn failed: missing ContextID/Kind/Montage | " .. table.concat(lines, " | ")
        return false, state.character_spawn_status
    end

    pcall(function() ctx = ctx:add_ref() end)
    state.last_spawn_context = ctx
    pcall(function() state.last_spawn_context_text = safe_string(ctx:call("ToString")) end)

    local duplicate, duplicate_status = duplicate_player_spawn_data(char_mgr, kind_grace, lines)
    table.insert(lines, "duplicate_status=" .. duplicate_status)
    if not duplicate then
        state.character_spawn_status = "registered duplicate spawn failed: " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    set_fields_by_type_or_name(duplicate, "app.ContextID", {}, ctx, "SpawnData.ContextID", lines)
    set_fields_by_type_or_name(duplicate, "app.CharacterKindID", {}, kind_grace, "SpawnData.CharacterKindID", lines)

    local registered = false
    for _, call_name in ipairs({"registerSpawnData(app.CharacterSpawnData)", "registerSpawnData"}) do
        local ok, err = pcall(function()
            char_mgr:call(call_name, duplicate)
        end)
        table.insert(lines, call_name .. "(duplicate) -> " .. (ok and "ok" or ("ERR " .. safe_string(err))))
        if ok then
            registered = true
            break
        end
    end
    if not registered then
        state.character_spawn_status = "registered duplicate spawn failed: registerSpawnData failed | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    for _, call_name in ipairs({"getSpawnDataRef(app.ContextID)", "getSpawnDataRef"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, ctx)
        end)
        table.insert(lines, call_name .. "(new ctx after register) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
    end

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
    table.insert(lines, "requestSpawn(new registered ctx) -> " .. (ok_spawn and "ok" or ("ERR " .. safe_string(err_spawn))))

    dump_spawn_hook_log(true)
    pcall(function()
        json.dump_file(DATA_PREFIX .. "registered_spawn_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            ok = ok_spawn,
            context = state.last_spawn_context_text,
            lines = lines,
        })
    end)

    state.character_spawn_status = "registered duplicate spawn " .. (ok_spawn and "sent" or "failed") .. " for " .. safe_string(state.last_spawn_context_text)
    state.puppet_status = ok_spawn and "Registered duplicate requestSpawn sent; check for Grace" or state.character_spawn_status
    return ok_spawn, state.character_spawn_status
end

local function run_ready_registered_duplicate()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "ready duplicate spawn failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local ctx, lines = create_new_context_id()
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
    local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
    if not ctx or not kind_grace or not montage_invalid then
        state.character_spawn_status = "ready duplicate spawn failed: missing ContextID/Kind/Montage | " .. table.concat(lines, " | ")
        return false, state.character_spawn_status
    end

    pcall(function() ctx = ctx:add_ref() end)
    state.last_spawn_context = ctx
    pcall(function() state.last_spawn_context_text = safe_string(ctx:call("ToString")) end)

    local duplicate, duplicate_status = duplicate_player_spawn_data(char_mgr, kind_grace, lines)
    table.insert(lines, "duplicate_status=" .. duplicate_status)
    if not duplicate then
        state.character_spawn_status = "ready duplicate spawn failed: " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    set_fields_by_type_or_name(duplicate, "app.ContextID", {}, ctx, "SpawnData.ContextID", lines)
    set_fields_by_type_or_name(duplicate, "app.CharacterKindID", {}, kind_grace, "SpawnData.CharacterKindID", lines)

    local registered = false
    for _, call_name in ipairs({"registerSpawnData(app.CharacterSpawnData)", "registerSpawnData"}) do
        local ok, err = pcall(function()
            char_mgr:call(call_name, duplicate)
        end)
        table.insert(lines, call_name .. "(duplicate) -> " .. (ok and "ok" or ("ERR " .. safe_string(err))))
        if ok then
            registered = true
            break
        end
    end
    if not registered then
        state.character_spawn_status = "ready duplicate spawn failed: registerSpawnData failed | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    local factory = nil
    for _, call_name in ipairs({"getCharacterContextFactory(app.CharacterKindID)", "getCharacterContextFactory"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, kind_grace)
        end)
        table.insert(lines, call_name .. "(cp_A100) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not factory then
            factory = result
        end
    end
    if not factory then
        state.character_spawn_status = "ready duplicate spawn failed: no CharacterContext factory | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    local context_ref = nil
    for _, attempt in ipairs({
        {
            name = "readyContext(app.ContextID, app.CharacterKindID, System.Func`1<app.CharacterContext>, System.Boolean)",
            args = { ctx, kind_grace, factory, false },
        },
        {
            name = "readyContext(app.ContextID, app.CharacterKindID, System.Func`1<app.CharacterContext>)",
            args = { ctx, kind_grace, factory },
        },
        {
            name = "readyContext",
            args = { ctx, kind_grace, factory, false },
        },
    }) do
        local ok, result = pcall(function()
            return char_mgr:call(attempt.name, unpack_args(attempt.args))
        end)
        table.insert(lines, attempt.name .. "(new ctx) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not context_ref then
            context_ref = result
            pcall(function() context_ref = context_ref:add_ref() end)
            break
        end
    end

    for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, ctx)
        end)
        table.insert(lines, call_name .. "(new ctx after ready) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not context_ref then
            context_ref = result
            pcall(function() context_ref = context_ref:add_ref() end)
        end
    end

    if context_ref then
        pcall(function()
            local go = context_ref:call("get_GameObject")
            table.insert(lines, "Context.get_GameObject -> " .. safe_string(go))
            if go then
                state.puppet_go = go:add_ref()
                state.puppet_xform = go:call("get_Transform")
                pcall(function() state.puppet_xform = state.puppet_xform:add_ref() end)
            end
        end)
        pcall(function()
            local xform = context_ref:call("get_Transform")
            table.insert(lines, "Context.get_Transform -> " .. safe_string(xform))
        end)
    end

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
    table.insert(lines, "requestSpawn(new ready ctx) -> " .. (ok_spawn and "ok" or ("ERR " .. safe_string(err_spawn))))

    dump_spawn_hook_log(true)
    pcall(function()
        json.dump_file(DATA_PREFIX .. "ready_spawn_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            ok = context_ref ~= nil or ok_spawn,
            context = state.last_spawn_context_text,
            lines = lines,
        })
    end)

    state.character_spawn_status = "ready duplicate spawn " .. ((context_ref or ok_spawn) and "sent" or "failed") .. " for " .. safe_string(state.last_spawn_context_text)
    state.puppet_status = context_ref and "Ready context created; check for Grace" or (ok_spawn and "Ready duplicate requestSpawn sent; check for Grace" or state.character_spawn_status)
    return context_ref ~= nil or ok_spawn, state.character_spawn_status
end

local function get_spawn_control_bundle(char_mgr, kind_grace, lines)
    local player_context_id = nil
    for _, call_name in ipairs({"getPlayerContextID(app.CharacterKindID)", "getPlayerContextID"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, kind_grace)
        end)
        table.insert(lines, "bundle " .. call_name .. "(cp_A100) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not player_context_id then
            player_context_id = result
        end
    end
    if not player_context_id then return nil, nil, nil, "cp_A100 ContextID not found" end

    local spawn_data = nil
    for _, call_name in ipairs({"getSpawnDataRef(app.ContextID)", "getSpawnDataRef"}) do
        local ok, result = pcall(function()
            return char_mgr:call(call_name, player_context_id)
        end)
        table.insert(lines, "bundle " .. call_name .. "(cp_A100 ctx) -> " .. (ok and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok and result and not spawn_data then
            spawn_data = result
        end
    end
    if not spawn_data then return nil, nil, nil, "cp_A100 SpawnData not found" end

    local control = nil
    pcall(function() control = spawn_data:get_field("<SpawnControl>k__BackingField") end)
    table.insert(lines, "bundle SpawnControl -> " .. safe_string(control))
    if not control then return nil, nil, nil, "SpawnControl not found" end

    local setting = nil
    pcall(function() setting = control:get_field("_DefaultPlayer") end)
    if not setting then pcall(function() setting = control:get_field("_InitControlPlayer") end) end
    table.insert(lines, "bundle CreateSetting -> " .. safe_string(setting))
    if not setting then return nil, nil, nil, "Default CreateSetting not found" end

    return spawn_data, control, setting, ""
end

local function make_controller_create_setting(default_setting, kind, lines)
    local ok_new, setting = pcall(function()
        return sdk.create_instance("app.LevelPlayerCreateController.CreateSetting")
    end)
    table.insert(lines, "sdk.create_instance(CreateSetting) -> " .. (ok_new and safe_string(setting) or ("ERR " .. safe_string(setting))))
    if not ok_new or not setting then
        table.insert(lines, "using default CreateSetting directly")
        return default_setting
    end

    pcall(function() setting = setting:add_ref() end)
    for _, ctor in ipairs({".ctor()", ".ctor"}) do
        local ok_ctor, err_ctor = pcall(function()
            setting:call(ctor)
        end)
        table.insert(lines, "CreateSetting:" .. ctor .. " -> " .. (ok_ctor and "ok" or ("ERR " .. safe_string(err_ctor))))
        if ok_ctor then break end
    end

    pcall(function()
        local td = default_setting:get_type_definition()
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
                local value = nil
                pcall(function() value = default_setting:get_field(name) end)
                if type_name == "app.CharacterKindID" then
                    value = kind
                end
                local ok_set, err_set = pcall(function() setting:set_field(name, value) end)
                table.insert(lines, "CreateSetting copy " .. name .. " -> " .. (ok_set and safe_string(value) or ("ERR " .. safe_string(err_set))))
            end
            local parent = get_parent_type_definition(td)
            if not parent then break end
            td = parent
            depth = depth + 1
        end
    end)
    return setting
end

local function schedule_controller_restore(control, old_spawn_context, old_request_end, old_permitted)
    state.pending_controller_restore = {
        control = control,
        old_spawn_context = old_spawn_context,
        old_request_end = old_request_end,
        old_permitted = old_permitted,
        restore_at = now() + 15.0,
    }
end

local function restore_controller_fields_if_due(force)
    local pending = state.pending_controller_restore
    if not pending then return end
    if not force and now() < (pending.restore_at or 0) then return end
    local control = pending.control
    if control then
        pcall(function() control:set_field("_SpawnContextID", pending.old_spawn_context) end)
        if pending.old_request_end ~= nil then
            pcall(function() control:set_field("IsSpawnRequestEnd", pending.old_request_end) end)
        end
        if pending.old_permitted ~= nil then
            pcall(function() control:set_field("<HasPermittedSpawn>k__BackingField", pending.old_permitted) end)
        end
    end
    state.pending_controller_restore = nil
end

local function run_controller_grace_spawn_probe()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "controller spawn failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local ctx, lines = create_new_context_id()
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    if not ctx or not kind_grace then
        state.character_spawn_status = "controller spawn failed: missing ContextID/kind | " .. table.concat(lines, " | ")
        return false, state.character_spawn_status
    end
    pcall(function() ctx = ctx:add_ref() end)
    state.last_spawn_context = ctx
    pcall(function() state.last_spawn_context_text = safe_string(ctx:call("ToString")) end)

    local _, control, default_setting, bundle_err = get_spawn_control_bundle(char_mgr, kind_grace, lines)
    if not control or not default_setting then
        state.character_spawn_status = "controller spawn failed: " .. bundle_err .. " | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    local duplicate, duplicate_status = duplicate_player_spawn_data(char_mgr, kind_grace, lines)
    table.insert(lines, "duplicate_status=" .. duplicate_status)
    if not duplicate then
        state.character_spawn_status = "controller spawn failed: " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    set_fields_by_type_or_name(duplicate, "app.ContextID", {}, ctx, "SpawnData.ContextID", lines)
    set_fields_by_type_or_name(duplicate, "app.CharacterKindID", {}, kind_grace, "SpawnData.CharacterKindID", lines)
    pcall(function() duplicate:set_field("<SpawnControl>k__BackingField", control) end)

    local registered = false
    for _, call_name in ipairs({"registerSpawnData(app.CharacterSpawnData)", "registerSpawnData"}) do
        local ok_register, err_register = pcall(function()
            char_mgr:call(call_name, duplicate)
        end)
        table.insert(lines, call_name .. "(controller duplicate) -> " .. (ok_register and "ok" or ("ERR " .. safe_string(err_register))))
        if ok_register then
            registered = true
            break
        end
    end
    if not registered then
        state.character_spawn_status = "controller spawn failed: registerSpawnData failed | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    local setting = make_controller_create_setting(default_setting, kind_grace, lines)
    local old_spawn_context = nil
    local old_request_end = nil
    local old_permitted = nil
    pcall(function() old_spawn_context = control:get_field("_SpawnContextID") end)
    pcall(function() old_request_end = control:get_field("IsSpawnRequestEnd") end)
    pcall(function() old_permitted = control:get_field("<HasPermittedSpawn>k__BackingField") end)

    pcall(function() control:set_field("_SpawnContextID", ctx) end)
    pcall(function() control:set_field("IsSpawnRequestEnd", false) end)
    pcall(function() control:set_field("<HasPermittedSpawn>k__BackingField", true) end)
    schedule_controller_restore(control, old_spawn_context, old_request_end, old_permitted)

    for _, call_name in ipairs({"registerSpawnGroup(app.ICharacterSpawnControl)", "registerSpawnGroup"}) do
        local ok_group, err_group = pcall(function()
            char_mgr:call(call_name, control)
        end)
        table.insert(lines, call_name .. "(controller control) -> " .. (ok_group and "ok" or ("ERR " .. safe_string(err_group))))
        if ok_group then break end
    end

    local owner_context_id = nil
    for _, call_name in ipairs({"getPlayerContextID(app.CharacterKindID)", "getPlayerContextID"}) do
        local ok_owner, result = pcall(function()
            return char_mgr:call(call_name, kind_grace)
        end)
        table.insert(lines, call_name .. "(owner cp_A100) -> " .. (ok_owner and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok_owner and result and not owner_context_id then
            owner_context_id = result
        end
    end
    if owner_context_id then
        for _, args in ipairs({
            { label = "new,owner", values = { ctx, owner_context_id } },
            { label = "owner,new", values = { owner_context_id, ctx } },
        }) do
            local ok_owner_request, result_owner_request = pcall(function()
                return char_mgr:call("getAndRequestSpawnOwner(app.ContextID, app.ContextID)", unpack_args(args.values))
            end)
            table.insert(lines, "getAndRequestSpawnOwner(" .. args.label .. ") -> " .. (ok_owner_request and safe_string(result_owner_request) or ("ERR " .. safe_string(result_owner_request))))
            if ok_owner_request and result_owner_request then break end
        end
    end

    for _, call_name in ipairs({"isUsedContext(app.ContextID)", "isUsedContext"}) do
        local ok_used, result_used = pcall(function()
            return char_mgr:call(call_name, ctx)
        end)
        table.insert(lines, call_name .. "(controller ctx after group/owner) -> " .. (ok_used and safe_string(result_used) or ("ERR " .. safe_string(result_used))))
    end

    local context_ref = nil
    local factory = nil
    for _, call_name in ipairs({"getCharacterContextFactory(app.CharacterKindID)", "getCharacterContextFactory"}) do
        local ok_factory, result = pcall(function()
            return char_mgr:call(call_name, kind_grace)
        end)
        table.insert(lines, call_name .. "(controller cp_A100) -> " .. (ok_factory and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok_factory and result and not factory then
            factory = result
        end
    end
    if factory then
        for _, attempt in ipairs({
            {
                name = "readyContext(app.ContextID, app.CharacterKindID, System.Func`1<app.CharacterContext>, System.Boolean)",
                args = { ctx, kind_grace, factory, false },
            },
            {
                name = "readyContext(app.ContextID, app.CharacterKindID, System.Func`1<app.CharacterContext>)",
                args = { ctx, kind_grace, factory },
            },
            {
                name = "readyContext",
                args = { ctx, kind_grace, factory },
            },
        }) do
            local ok_ready, result = pcall(function()
                return char_mgr:call(attempt.name, unpack_args(attempt.args))
            end)
            table.insert(lines, attempt.name .. "(controller ctx) -> " .. (ok_ready and safe_string(result) or ("ERR " .. safe_string(result))))
            if ok_ready and result and not context_ref then
                context_ref = result
                pcall(function() context_ref = context_ref:add_ref() end)
            end
        end
    end

    if context_ref then
        pcall(function()
            local go_before = context_ref:call("get_GameObject")
            table.insert(lines, "Controller context before create get_GameObject -> " .. safe_string(go_before))
        end)
        pcall(function()
            local updater_before = context_ref:call("get_Updater")
            table.insert(lines, "Controller context before create get_Updater -> " .. safe_string(updater_before))
        end)
    end

    for _, call in ipairs({
        { name = "setupControlCharacter(app.LevelPlayerCreateController.CreateSetting)", args = { setting } },
        { name = "setupCommonMessageKind(app.LevelPlayerCreateController.CreateSetting, app.CharacterContext)", args = { setting, context_ref }, require_context = true },
    }) do
        if call.require_context and not context_ref then
            table.insert(lines, "Controller:" .. call.name .. " -> skipped (no context)")
            goto continue_controller_call
        end
        local ok_call, err_call = pcall(function()
            control:call(call.name, unpack_args(call.args))
        end)
        table.insert(lines, "Controller:" .. call.name .. " -> " .. (ok_call and "ok" or ("ERR " .. safe_string(err_call))))
        ::continue_controller_call::
    end

    local montage_invalid = get_static_field_value("app.MontageID", {"Invalid"})
    local purpose_default = get_static_field_value("app.CharacterUsePurposeFlag", {"Default"}) or 0
    if montage_invalid then
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
        table.insert(lines, "CharacterManager:requestSpawn(controller ctx) -> " .. (ok_spawn and "ok" or ("ERR " .. safe_string(err_spawn))))
    else
        table.insert(lines, "CharacterManager:requestSpawn(controller ctx) -> skipped (MontageID.Invalid missing)")
    end

    for _, call in ipairs({
        { name = "app.ICharacterSpawnControl.requestSpawn()", args = {} },
        { name = "createControlCharacter()", args = {} },
        { name = "app.ICharacterSpawnControl.requestResume(System.Int32)", args = { 0 } },
    }) do
        local ok_call, err_call = pcall(function()
            control:call(call.name, unpack_args(call.args))
        end)
        table.insert(lines, "Controller:" .. call.name .. " -> " .. (ok_call and "ok" or ("ERR " .. safe_string(err_call))))
    end

    for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
        local ok_ref, result = pcall(function()
            return char_mgr:call(call_name, ctx)
        end)
        table.insert(lines, call_name .. "(controller ctx) -> " .. (ok_ref and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok_ref and result and not context_ref then
            context_ref = result
            pcall(function() context_ref = context_ref:add_ref() end)
        end
    end

    if context_ref then
        pcall(function()
            local go = context_ref:call("get_GameObject")
            table.insert(lines, "Controller context get_GameObject -> " .. safe_string(go))
            if go then
                state.puppet_go = go:add_ref()
                state.puppet_xform = go:call("get_Transform")
                pcall(function() state.puppet_xform = state.puppet_xform:add_ref() end)
            end
        end)
        pcall(function()
            local updater = context_ref:call("get_Updater")
            table.insert(lines, "Controller context get_Updater -> " .. safe_string(updater))
        end)
    end

    dump_spawn_hook_log(true)
    pcall(function()
        json.dump_file(DATA_PREFIX .. "controller_spawn_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            context = state.last_spawn_context_text,
            ok = true,
            lines = lines,
        })
    end)

    state.character_spawn_status = "controller spawn probe sent for " .. safe_string(state.last_spawn_context_text)
    state.puppet_status = context_ref and "Controller context created; check for Grace" or "Controller spawn sent; waiting for context"
    return true, state.character_spawn_status
end

local function run_player_load_order_grace_probe()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "load-order spawn failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local ctx, lines = create_new_context_id()
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    if not ctx or not kind_grace then
        state.character_spawn_status = "load-order spawn failed: missing ContextID/kind | " .. table.concat(lines, " | ")
        return false, state.character_spawn_status
    end
    pcall(function() ctx = ctx:add_ref() end)
    state.last_spawn_context = ctx
    pcall(function() state.last_spawn_context_text = safe_string(ctx:call("ToString")) end)

    local spawn_data, control, default_setting, bundle_err = get_spawn_control_bundle(char_mgr, kind_grace, lines)
    if not spawn_data or not control or not default_setting then
        state.character_spawn_status = "load-order spawn failed: " .. bundle_err .. " | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    local duplicate, duplicate_status = duplicate_player_spawn_data(char_mgr, kind_grace, lines)
    table.insert(lines, "duplicate_status=" .. duplicate_status)
    if not duplicate then
        state.character_spawn_status = "load-order spawn failed: " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    set_fields_by_type_or_name(duplicate, "app.ContextID", {}, ctx, "SpawnData.ContextID", lines)
    set_fields_by_type_or_name(duplicate, "app.CharacterKindID", {}, kind_grace, "SpawnData.CharacterKindID", lines)
    set_named_field_for_probe(duplicate, "<ResumeType>k__BackingField", 1, "SpawnData", lines)
    set_named_field_for_probe(duplicate, "<IsEventWait>k__BackingField", false, "SpawnData", lines)
    set_named_field_for_probe(duplicate, "<IsForceTransform>k__BackingField", true, "SpawnData", lines)
    set_named_field_for_probe(duplicate, "<IsFirstSpawn>k__BackingField", true, "SpawnData", lines)
    set_named_field_for_probe(duplicate, "<SpawnControl>k__BackingField", control, "SpawnData", lines)

    local refs = get_local_player_refs()
    if refs.valid and refs.xform then
        local pos = nil
        local rot = nil
        pcall(function() pos = refs.xform:call("get_Position") end)
        pcall(function() rot = refs.xform:call("get_Rotation") end)
        if pos then set_named_field_for_probe(duplicate, "<Position>k__BackingField", pos, "SpawnData", lines) end
        if rot then set_named_field_for_probe(duplicate, "<Rotation>k__BackingField", rot, "SpawnData", lines) end
    else
        table.insert(lines, "local transform skipped: " .. safe_string(refs.error))
    end

    local old_spawn_context = nil
    local old_request_end = nil
    local old_permitted = nil
    local old_init_suspended = nil
    pcall(function() old_spawn_context = control:get_field("_SpawnContextID") end)
    pcall(function() old_request_end = control:get_field("IsSpawnRequestEnd") end)
    pcall(function() old_permitted = control:get_field("<HasPermittedSpawn>k__BackingField") end)
    pcall(function() old_init_suspended = control:get_field("_InitStateSuspended") end)
    table.insert(lines, "control old _SpawnContextID=" .. safe_string(old_spawn_context) .. " IsSpawnRequestEnd=" .. safe_string(old_request_end) .. " HasPermitted=" .. safe_string(old_permitted) .. " InitSuspended=" .. safe_string(old_init_suspended))

    set_named_field_for_probe(control, "_SpawnContextID", ctx, "Control", lines)
    set_named_field_for_probe(control, "IsSpawnRequestEnd", false, "Control", lines)
    set_named_field_for_probe(control, "<HasPermittedSpawn>k__BackingField", false, "Control", lines)
    set_named_field_for_probe(control, "_InitStateSuspended", false, "Control", lines)

    for _, call_name in ipairs({"registerSpawnGroup(app.ICharacterSpawnControl)", "registerSpawnGroup"}) do
        local ok_group, err_group = pcall(function()
            char_mgr:call(call_name, control)
        end)
        table.insert(lines, call_name .. "(load-order control) -> " .. (ok_group and "ok" or ("ERR " .. safe_string(err_group))))
        if ok_group then break end
    end

    local factory = nil
    for _, call_name in ipairs({"getCharacterContextFactory(app.CharacterKindID)", "getCharacterContextFactory"}) do
        local ok_factory, result = pcall(function()
            return char_mgr:call(call_name, kind_grace)
        end)
        table.insert(lines, call_name .. "(load-order cp_A100) -> " .. (ok_factory and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok_factory and result and not factory then
            factory = result
        end
    end

    local context_ref = nil
    if factory then
        for _, attempt in ipairs({
            {
                name = "readyContext(app.ContextID, app.CharacterKindID, System.Func`1<app.CharacterContext>, System.Boolean)",
                args = { ctx, kind_grace, factory, false },
            },
            {
                name = "readyContext(app.ContextID, app.CharacterKindID, System.Func`1<app.CharacterContext>)",
                args = { ctx, kind_grace, factory },
            },
            {
                name = "readyContext",
                args = { ctx, kind_grace, factory },
            },
        }) do
            local ok_ready, result = pcall(function()
                return char_mgr:call(attempt.name, unpack_args(attempt.args))
            end)
            table.insert(lines, attempt.name .. "(load-order ctx) -> " .. (ok_ready and safe_string(result) or ("ERR " .. safe_string(result))))
            if ok_ready and result and not context_ref then
                context_ref = result
                pcall(function() context_ref = context_ref:add_ref() end)
                break
            end
        end
    end

    if context_ref then
        for _, call_name in ipairs({"restoreContext(app.ContextID, app.CharacterContext)", "restoreContext"}) do
            local ok_restore, result_restore = pcall(function()
                return char_mgr:call(call_name, ctx, context_ref)
            end)
            table.insert(lines, call_name .. "(load-order ctx) -> " .. (ok_restore and safe_string(result_restore) or ("ERR " .. safe_string(result_restore))))
            if ok_restore then break end
        end
    else
        table.insert(lines, "restoreContext skipped: no context_ref")
    end

    local registered = false
    for _, call_name in ipairs({"registerSpawnData(app.CharacterSpawnData)", "registerSpawnData"}) do
        local ok_register, err_register = pcall(function()
            char_mgr:call(call_name, duplicate)
        end)
        table.insert(lines, call_name .. "(load-order duplicate) -> " .. (ok_register and "ok" or ("ERR " .. safe_string(err_register))))
        if ok_register then
            registered = true
            break
        end
    end

    if context_ref then
        pcall(function()
            local go_before = context_ref:call("get_GameObject")
            table.insert(lines, "Context before controller get_GameObject -> " .. safe_string(go_before))
        end)
        pcall(function()
            local updater_before = context_ref:call("get_Updater")
            table.insert(lines, "Context before controller get_Updater -> " .. safe_string(updater_before))
        end)
    end

    local setting = make_controller_create_setting(default_setting, kind_grace, lines)
    for _, call in ipairs({
        { name = "setupControlCharacter(app.LevelPlayerCreateController.CreateSetting)", args = { setting } },
        { name = "setupCommonMessageKind(app.LevelPlayerCreateController.CreateSetting, app.CharacterContext)", args = { setting, context_ref }, require_context = true },
        { name = "app.ICharacterSpawnControl.requestSpawn()", args = {} },
        { name = "app.ICharacterSpawnControl.requestResume(System.Int32)", args = { 0 } },
        { name = "createControlCharacter()", args = {} },
    }) do
        if call.require_context and not context_ref then
            table.insert(lines, "Control:" .. call.name .. " -> skipped (no context)")
        else
            local ok_call, err_call = pcall(function()
                control:call(call.name, unpack_args(call.args))
            end)
            table.insert(lines, "Control:" .. call.name .. " -> " .. (ok_call and "ok" or ("ERR " .. safe_string(err_call))))
        end
    end

    if context_ref then
        pcall(function()
            local go = context_ref:call("get_GameObject")
            table.insert(lines, "Context after controller get_GameObject -> " .. safe_string(go))
            if go then
                state.puppet_go = go:add_ref()
                state.puppet_xform = go:call("get_Transform")
                pcall(function() state.puppet_xform = state.puppet_xform:add_ref() end)
            end
        end)
        pcall(function()
            local updater = context_ref:call("get_Updater")
            table.insert(lines, "Context after controller get_Updater -> " .. safe_string(updater))
        end)
    end

    pcall(function() control:set_field("_SpawnContextID", old_spawn_context) end)
    if old_request_end ~= nil then pcall(function() control:set_field("IsSpawnRequestEnd", old_request_end) end) end
    if old_permitted ~= nil then pcall(function() control:set_field("<HasPermittedSpawn>k__BackingField", old_permitted) end) end
    if old_init_suspended ~= nil then pcall(function() control:set_field("_InitStateSuspended", old_init_suspended) end) end

    pcall(function()
        json.dump_file(DATA_PREFIX .. "load_order_spawn_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            ok = context_ref ~= nil or registered,
            context = state.last_spawn_context_text,
            lines = lines,
        })
    end)

    local has_go = false
    if context_ref then
        pcall(function() has_go = context_ref:call("get_GameObject") ~= nil end)
    end
    state.character_spawn_status = "load-order spawn " .. (has_go and "has gameobject" or (registered and "sent" or "failed")) .. " for " .. safe_string(state.last_spawn_context_text)
    state.puppet_status = has_go and "Load-order Grace context has GameObject" or state.character_spawn_status
    return context_ref ~= nil or registered, state.character_spawn_status
end

function re9mp_run_trace_order_controller_spawn_probe()
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_status = "trace-order spawn failed: CharacterManager not found"
        return false, state.character_spawn_status
    end

    local ctx, lines = create_new_context_id()
    local kind_grace = get_static_field_value("app.CharacterKindID", {"cp_A100"})
    if not ctx or not kind_grace then
        state.character_spawn_status = "trace-order spawn failed: missing ContextID/kind | " .. table.concat(lines, " | ")
        return false, state.character_spawn_status
    end
    pcall(function() ctx = ctx:add_ref() end)
    state.last_spawn_context = ctx
    pcall(function() state.last_spawn_context_text = safe_string(ctx:call("ToString")) end)

    local _, control, default_setting, bundle_err = get_spawn_control_bundle(char_mgr, kind_grace, lines)
    if not control or not default_setting then
        state.character_spawn_status = "trace-order spawn failed: " .. bundle_err .. " | " .. table.concat(lines, " | ")
        state.puppet_status = state.character_spawn_status
        return false, state.character_spawn_status
    end

    local setting = make_controller_create_setting(default_setting, kind_grace, lines)
    local old_spawn_context = nil
    local old_request_end = nil
    local old_permitted = nil
    local old_init_suspended = nil
    pcall(function() old_spawn_context = control:get_field("_SpawnContextID") end)
    pcall(function() old_request_end = control:get_field("IsSpawnRequestEnd") end)
    pcall(function() old_permitted = control:get_field("<HasPermittedSpawn>k__BackingField") end)
    pcall(function() old_init_suspended = control:get_field("_InitStateSuspended") end)
    table.insert(lines, "control old _SpawnContextID=" .. safe_string(old_spawn_context)
        .. " IsSpawnRequestEnd=" .. safe_string(old_request_end)
        .. " HasPermitted=" .. safe_string(old_permitted)
        .. " InitSuspended=" .. safe_string(old_init_suspended))

    set_named_field_for_probe(control, "_SpawnContextID", ctx, "Control", lines)
    set_named_field_for_probe(control, "IsSpawnRequestEnd", false, "Control", lines)
    set_named_field_for_probe(control, "<HasPermittedSpawn>k__BackingField", false, "Control", lines)
    set_named_field_for_probe(control, "_InitStateSuspended", false, "Control", lines)
    schedule_controller_restore(control, old_spawn_context, old_request_end, old_permitted)

    for _, call_name in ipairs({"registerSpawnGroup(app.ICharacterSpawnControl)", "registerSpawnGroup"}) do
        local ok_group, err_group = pcall(function()
            char_mgr:call(call_name, control)
        end)
        table.insert(lines, call_name .. "(trace-order control) -> " .. (ok_group and "ok" or ("ERR " .. safe_string(err_group))))
        if ok_group then break end
    end

    local context_ref = nil
    local ok_setup, err_setup = pcall(function()
        control:call("setupControlCharacter(app.LevelPlayerCreateController.CreateSetting)", setting)
    end)
    table.insert(lines, "Control:setupControlCharacter(trace-order setting) -> " .. (ok_setup and "ok" or ("ERR " .. safe_string(err_setup))))

    for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
        local ok_ref, result = pcall(function()
            return char_mgr:call(call_name, ctx)
        end)
        table.insert(lines, call_name .. "(trace-order after setup) -> " .. (ok_ref and safe_string(result) or ("ERR " .. safe_string(result))))
        if ok_ref and result and not context_ref then
            context_ref = result
            pcall(function() context_ref = context_ref:add_ref() end)
        end
    end

    if context_ref then
        local ok_common, err_common = pcall(function()
            control:call("setupCommonMessageKind(app.LevelPlayerCreateController.CreateSetting, app.CharacterContext)", setting, context_ref)
        end)
        table.insert(lines, "Control:setupCommonMessageKind(trace-order context) -> " .. (ok_common and "ok" or ("ERR " .. safe_string(err_common))))
    else
        table.insert(lines, "Control:setupCommonMessageKind skipped: no context after setup")
    end

    local ok_create, err_create = pcall(function()
        control:call("createControlCharacter()")
    end)
    table.insert(lines, "Control:createControlCharacter(trace-order) -> " .. (ok_create and "ok" or ("ERR " .. safe_string(err_create))))

    if not context_ref then
        for _, call_name in ipairs({"getContextRef(app.ContextID)", "getContextRef"}) do
            local ok_ref, result = pcall(function()
                return char_mgr:call(call_name, ctx)
            end)
            table.insert(lines, call_name .. "(trace-order after create) -> " .. (ok_ref and safe_string(result) or ("ERR " .. safe_string(result))))
            if ok_ref and result and not context_ref then
                context_ref = result
                pcall(function() context_ref = context_ref:add_ref() end)
            end
        end
    end

    local has_go = false
    if context_ref then
        pcall(function()
            local go = context_ref:call("get_GameObject")
            table.insert(lines, "Trace-order context get_GameObject -> " .. safe_string(go))
            has_go = go ~= nil
            if go then
                state.puppet_go = go:add_ref()
                state.puppet_xform = go:call("get_Transform")
                pcall(function() state.puppet_xform = state.puppet_xform:add_ref() end)
            end
        end)
        pcall(function()
            local updater = context_ref:call("get_Updater")
            table.insert(lines, "Trace-order context get_Updater -> " .. safe_string(updater))
        end)
    end

    pcall(function()
        json.dump_file(DATA_PREFIX .. "trace_order_spawn_probe.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            ok = context_ref ~= nil,
            has_game_object = has_go,
            context = state.last_spawn_context_text,
            lines = lines,
        })
    end)

    state.character_spawn_status = "trace-order spawn " .. (has_go and "has gameobject" or (context_ref and "has context" or "failed"))
        .. " for " .. safe_string(state.last_spawn_context_text)
    state.puppet_status = has_go and "Trace-order Grace context has GameObject" or state.character_spawn_status
    return context_ref ~= nil or ok_setup or ok_create, state.character_spawn_status
end
