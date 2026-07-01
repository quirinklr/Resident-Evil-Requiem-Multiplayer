-- Ownership recipe trace helpers extracted from pre-split runtime lines 6894-7125.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

function re9mp_run_grace_ownership_recipe_dump()
    local refs = get_local_player_refs()
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        local_player = refs and refs.valid and true or false,
        local_error = refs and refs.error or "",
        trace = {
            mode = safe_string(state.trace_mode or ""),
            spawn_hook_status = state.spawn_hook_status,
            spawn_hook_events = #state.spawn_hook_events,
            level_trace_status = state.level_trace_status,
            level_trace_events = #state.level_trace_events,
            pool_trace_status = state.pool_trace_status,
            pool_trace_events = #state.pool_trace_events,
            bind_trace_status = state.bind_trace_status,
            bind_trace_events = #state.bind_trace_events,
            bind_trace_errors = #(state.bind_trace_errors or {}),
        },
        character_manager = {},
        local_player_refs = {},
        network = {
            native_status = state.status or {},
            remote_samples = #state.remote_samples,
            remote_last_seq = state.remote_last_seq,
            remote_prev_seq = state.remote_prev_seq,
        },
        mesh_ownership = {
            controllers = {},
            units = {},
        },
        trace_samples = {
            spawn_recent = {},
            level_recent = {},
            bind_recent = {},
            pool_recent = {},
        },
        conclusions = {
            visible_control_path = "registered_player_material_lit remains the parented proof/control path",
            detached_mesh_only_result = "null/scene-folder detach kept objects alive but made Grace invisible",
            next_required_context = "independent Character/MeshController ownership context or true prefab/character spawn",
        },
    }

    local function recent(src, limit)
        local out = {}
        local count = #(src or {})
        local first = math.max(1, count - (limit or 40) + 1)
        for i = first, count do
            table.insert(out, src[i])
        end
        return out
    end

    report.trace_samples.spawn_recent = recent(state.spawn_hook_events, 60)
    report.trace_samples.level_recent = recent(state.level_trace_events, 80)
    report.trace_samples.bind_recent = recent(state.bind_trace_events, 100)
    report.trace_samples.pool_recent = recent(state.pool_trace_events, 20)

    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    report.character_manager.ref = safe_string(char_mgr)
    if char_mgr then
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
        report.character_manager.counts = {
            player_contexts = trace_count(player_list),
            spawnable_contexts = trace_count(spawnable_list),
            character_pool = trace_count(pool_list),
            spawn_data_db = trace_count(spawn_data_db),
            context_db = trace_count(context_db),
            spawn_owner = trace_count(spawn_owner),
        }
        report.character_manager_counts = report.character_manager.counts
        report.character_manager.player_contexts = {}
        report.character_manager.pool = {}
        for i = 0, math.min((report.character_manager.counts.player_contexts or 0) - 1, 7) do
            table.insert(report.character_manager.player_contexts, trace_context_summary(trace_item(player_list, i), i))
        end
        for i = 0, math.min((report.character_manager.counts.character_pool or 0) - 1, 63) do
            local row = trace_pool_summary(trace_item(pool_list, i), i)
            if row.updater ~= "" or row.used ~= nil or row.reserved ~= nil or row.finalized ~= nil then
                table.insert(report.character_manager.pool, row)
            end
        end
    end

    if refs and refs.valid then
        report.local_player_refs = {
            player = safe_string(refs.player),
            player_type = trace_type_name(refs.player),
            game_object = safe_string(refs.go),
            game_object_name = safe_string(trace_call(refs.go, "get_Name")),
            transform = safe_string(refs.xform),
            position = read_position(refs.xform),
            rotation = read_rotation(refs.xform),
            context_id = safe_string(re9mp_trace_value(refs.player, {"get_ContextID"}, {
                "<ContextID>k__BackingField", "_ContextID", "ContextID",
            })),
            character_kind_id = safe_string(re9mp_trace_value(refs.player, {"get_CharacterKindID"}, {
                "<CharacterKindID>k__BackingField", "_CharacterKindID", "CharacterKindID",
            })),
            updater = safe_string(trace_call(refs.player, "get_Updater")),
            updater_type = trace_type_name(trace_call(refs.player, "get_Updater")),
        }

        local player_mesh_controller = find_component_by_type_name(refs.go, "app.PlayerMeshController")
        local actor_mesh_controller = find_component_by_type_name(refs.go, "app.ActorPlayerMeshController")
        report.mesh_ownership.controllers.player = re9mp_trace_mesh_controller_summary(player_mesh_controller, "PlayerMeshController")
        report.mesh_ownership.controllers.actor_player = re9mp_trace_mesh_controller_summary(actor_mesh_controller, "ActorPlayerMeshController")

        local units = collect_live_mesh_units(player_mesh_controller, 48)
        report.mesh_ownership.unit_count = #units
        for i, unit in ipairs(units) do
            local row = re9mp_trace_mesh_unit_summary(unit, i - 1)
            row.render = mesh_render_status(trace_call(unit, "get_Mesh"))
            table.insert(report.mesh_ownership.units, row)
        end
    end

    report.trace_status = report.trace
    pcall(function() json.dump_file(GRACE_OWNERSHIP_RECIPE_FILE, report) end)
    return true, "grace ownership recipe dumped units=" .. tostring(report.mesh_ownership.unit_count or 0)
end

function re9mp_start_grace_ownership_trace(reason)
    local label = safe_string(reason or "grace ownership trace")
    state.trace_mode = "level_or_reload"
    state.spawn_hook_events = {}
    state.spawn_hook_dirty = true
    state.spawn_hook_status = "cleared for " .. label
    clear_puppet_refs("despawned")
    state.remote_samples = {}
    state.remote_last_seq = nil
    cfg.local_dummy = false
    cfg.auto_spawn_puppet = false
    cfg.level_trace_enabled = true
    cfg.pool_trace_enabled = true
    cfg.bind_trace_enabled = true
    cfg.controller_trace_enabled = true
    save_cfg()

    state.level_trace_enabled = true
    state.pool_trace_enabled = true
    state.bind_trace_enabled = true
    state.spawn_hook_enabled = true
    reset_level_trace(label)
    reset_pool_trace(label)
    reset_bind_trace(label)
    push_pool_trace_event("grace ownership trace start", true)
    install_spawn_observer_hooks()
    install_bind_trace_hooks()
    dump_spawn_hook_log(true)
    dump_level_trace(true)
    dump_pool_trace(true)
    dump_bind_trace(true)
    return true, "grace ownership trace started; reload the level/scene, then stop_grace_ownership_trace"
end

function re9mp_start_join_ownership_trace(reason)
    local label = safe_string(reason or "gameplay load ownership trace")
    state.trace_mode = "gameplay_load"
    state.spawn_hook_events = {}
    state.spawn_hook_dirty = true
    state.spawn_hook_status = "cleared for " .. label
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

    state.level_trace_enabled = true
    state.pool_trace_enabled = true
    state.bind_trace_enabled = true
    state.spawn_hook_enabled = true
    reset_level_trace(label)
    reset_pool_trace(label)
    reset_bind_trace(label)
    push_pool_trace_event("join ownership trace start", true)
    install_spawn_observer_hooks()
    install_bind_trace_hooks()
    dump_spawn_hook_log(true)
    dump_level_trace(true)
    dump_pool_trace(true)
    dump_bind_trace(true)
    return true, "gameplay load ownership trace started; load the save/level now, then stop_join_ownership_trace"
end

function re9mp_stop_grace_ownership_trace()
    push_pool_trace_event("grace ownership trace stop", true)
    state.level_trace_enabled = false
    state.pool_trace_enabled = false
    state.bind_trace_enabled = false
    state.spawn_hook_enabled = false
    cfg.level_trace_enabled = false
    cfg.pool_trace_enabled = false
    cfg.bind_trace_enabled = false
    save_cfg()
    state.level_trace_status = "stopped events=" .. tostring(#state.level_trace_events)
    state.pool_trace_status = "stopped events=" .. tostring(#state.pool_trace_events)
    state.bind_trace_status = "stopped events=" .. tostring(#state.bind_trace_events)
    dump_spawn_hook_log(true)
    dump_level_trace(true)
    dump_pool_trace(true)
    dump_bind_trace(true)
    local ok, recipe_message = re9mp_run_grace_ownership_recipe_dump()
    return ok, "grace ownership trace stopped level=" .. tostring(#state.level_trace_events)
        .. " bind=" .. tostring(#state.bind_trace_events)
        .. " pool=" .. tostring(#state.pool_trace_events)
        .. " spawn=" .. tostring(#state.spawn_hook_events)
        .. " | " .. safe_string(recipe_message)
end

function re9mp_stop_join_ownership_trace()
    return re9mp_stop_grace_ownership_trace()
end
