-- Runtime commands, UI, and callbacks extracted from pre-split runtime lines 7426-8295.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function despawn_puppet()
    clear_puppet_refs("despawned")
end

function re9mp_is_active_visual_clone_mode(mode)
    return mode == "registered_player_material_lit"
end

function re9mp_archived_dev_action(action, reason)
    return false, "archived dev action: " .. safe_string(action) .. " (" .. safe_string(reason) .. ")"
end

local function write_dev_result(id, ok, message)
    state.dev_status = safe_string(message)
    pcall(function()
        json.dump_file(DEV_RESULT_FILE, {
            id = id or state.dev_last_id,
            ok = ok and true or false,
            message = safe_string(message),
            time_ms = now_ms(),
            scene = get_current_scene(),
            local_ok = state.local_ok,
            local_error = state.local_error,
            puppet = state.puppet_status,
            native_state = (state.status or {}).state or "",
            native_mode = (state.status or {}).mode or "",
            remote_samples = #state.remote_samples,
            draw = state.draw_status,
            spawn_hook_status = state.spawn_hook_status,
            spawn_hook_events = #state.spawn_hook_events,
            level_trace_status = state.level_trace_status,
            level_trace_events = #state.level_trace_events,
            pool_trace_status = state.pool_trace_status,
            pool_trace_events = #state.pool_trace_events,
            bind_trace_status = state.bind_trace_status,
            bind_trace_events = #state.bind_trace_events,
            load_phase_injection_status = state.load_phase_injection_status,
            load_phase_injection_armed = state.load_phase_injection_armed,
            load_phase_injection_done = state.load_phase_injection_done,
            component_resource_status = state.component_resource_status,
            visual_probe_status = state.visual_probe_status,
        })
    end)
end

local function poll_dev_command()
    local cmd = nil
    pcall(function() cmd = json.load_file(DEV_COMMAND_FILE) end)
    if not cmd then return end

    local id = tonumber(cmd.id or 0) or 0
    if id <= (state.dev_last_id or 0) then return end
    state.dev_last_id = id

    local action = safe_string(cmd.action)
    local ok, message = true, "ok"

    if action == "status" then
        message = "status"
    elseif action == "set_dummy" then
        cfg.local_dummy = cmd.value and true or false
        if not cfg.local_dummy then
            state.remote_samples = {}
            state.remote_last_seq = nil
        end
        save_cfg()
        message = "local_dummy=" .. tostring(cfg.local_dummy)
    elseif action == "set_dummy_ahead" then
        cfg.local_dummy = true
        cfg.dummy_offset_x = 0
        cfg.dummy_offset_y = 0
        cfg.dummy_offset_z = 2.4
        state.remote_samples = {}
        state.remote_last_seq = nil
        save_cfg()
        message = "local_dummy=true offset=0,0,2.4"
    elseif action == "set_dummy_static_ahead" then
        ok, message = set_static_dummy_ahead(2.4)
    elseif action == "set_dummy_offset" then
        local text = safe_string(cmd.text or "")
        local x, y, z = text:match("^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$")
        if not x then
            x, z = text:match("^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$")
            y = "0"
        end
        if x and y and z then
            cfg.local_dummy = true
            cfg.dummy_offset_x = tonumber(x) or 0
            cfg.dummy_offset_y = tonumber(y) or 0
            cfg.dummy_offset_z = tonumber(z) or 0
            state.remote_samples = {}
            state.remote_last_seq = nil
            save_cfg()
            message = string.format("local_dummy=true offset=%.2f,%.2f,%.2f", cfg.dummy_offset_x, cfg.dummy_offset_y, cfg.dummy_offset_z)
        else
            ok = false
            message = "set_dummy_offset expects Text like x,z or x,y,z"
        end
    elseif action == "set_marker" then
        cfg.draw_remote_marker = cmd.value and true or false
        save_cfg()
        message = "draw_remote_marker=" .. tostring(cfg.draw_remote_marker)
    elseif action == "set_visual_clone_mode" then
        local mode = safe_string(cmd.text or "")
        if re9mp_is_active_visual_clone_mode(mode) then
            cfg.visual_clone_mode = mode
            save_cfg()
            message = "visual_clone_mode=" .. mode
        else
            ok = false
            message = "archived visual mode: " .. mode .. "; active mode is registered_player_material_lit"
        end
    elseif action == "despawn" then
        despawn_puppet()
        message = "despawned"
    elseif action == "clear_remote" then
        state.remote_samples = {}
        state.remote_last_seq = nil
        message = "remote samples cleared"
    elseif action == "spawn_hook_status" then
        dump_spawn_hook_log(true)
        message = state.spawn_hook_status .. " events=" .. tostring(#state.spawn_hook_events)
    elseif action == "runtime_safety_status" then
        message = "reload_safe auto_spawn=" .. tostring(cfg.auto_spawn_puppet)
            .. " spawn_hook_enabled=" .. tostring(state.spawn_hook_enabled)
            .. " spawn_hook_attempted=" .. tostring(state.spawn_hook_attempted)
            .. " pool_trace_enabled=" .. tostring(state.pool_trace_enabled)
            .. " bind_trace_enabled=" .. tostring(state.bind_trace_enabled)
            .. " bind_trace_attempted=" .. tostring(state.bind_trace_attempted)
            .. " controller_trace_enabled=" .. tostring(cfg.controller_trace_enabled)
            .. " trace_mode=" .. safe_string(state.trace_mode or "")
            .. " load_phase_injection_armed=" .. tostring(state.load_phase_injection_armed)
            .. " load_phase_injection_done=" .. tostring(state.load_phase_injection_done)
            .. " load_phase_injection_status=" .. safe_string(state.load_phase_injection_status)
            .. " visual_clone_mode=" .. safe_string(cfg.visual_clone_mode)
            .. " clone_safety=no_skeleton_ref_no_notify_no_material_param_count"
    elseif action == "start_spawn_hooks" then
        state.spawn_hook_enabled = true
        install_spawn_observer_hooks()
        dump_spawn_hook_log(true)
        message = state.spawn_hook_status .. " events=" .. tostring(#state.spawn_hook_events)
    elseif action == "start_grace_ownership_trace" then
        ok, message = re9mp_start_grace_ownership_trace(cmd.text ~= "" and cmd.text or "dev command")
    elseif action == "stop_grace_ownership_trace" then
        ok, message = re9mp_stop_grace_ownership_trace()
    elseif action == "start_join_ownership_trace" then
        ok, message = re9mp_start_join_ownership_trace(cmd.text ~= "" and cmd.text or "dev command")
    elseif action == "stop_join_ownership_trace" then
        ok, message = re9mp_stop_join_ownership_trace()
    elseif action == "dump_grace_ownership_recipe" then
        ok, message = re9mp_run_grace_ownership_recipe_dump()
    elseif action == "arm_load_phase_player_clone_injection" then
        ok, message = re9mp_arm_load_phase_player_clone_injection(cmd.text)
    elseif action == "cancel_load_phase_player_clone_injection" then
        ok, message = re9mp_cancel_load_phase_player_clone_injection()
    elseif action == "dump_load_phase_injection_probe" then
        ok, message = re9mp_dump_load_phase_injection_probe("dev command")
    elseif action == "context_reserver_probe" then
        ok, message = re9mp_run_context_reserver_probe(cmd.text)
    elseif action == "start_level_trace" then
        state.level_trace_enabled = true
        state.spawn_hook_enabled = true
        cfg.level_trace_enabled = true
        save_cfg()
        reset_level_trace(cmd.text ~= "" and cmd.text or "dev command")
        dump_level_trace(true)
        message = state.level_trace_status
    elseif action == "stop_level_trace" then
        state.level_trace_enabled = false
        state.spawn_hook_enabled = false
        cfg.level_trace_enabled = false
        save_cfg()
        state.level_trace_status = "stopped events=" .. tostring(#state.level_trace_events)
        dump_level_trace(true)
        message = state.level_trace_status
    elseif action == "dump_level_trace" then
        dump_level_trace(true)
        message = state.level_trace_status .. " events=" .. tostring(#state.level_trace_events)
    elseif action == "start_pool_trace" then
        state.pool_trace_enabled = true
        cfg.pool_trace_enabled = true
        save_cfg()
        reset_pool_trace(cmd.text ~= "" and cmd.text or "dev command")
        push_pool_trace_event("start", true)
        dump_pool_trace(true)
        message = state.pool_trace_status
    elseif action == "stop_pool_trace" then
        push_pool_trace_event("stop", true)
        state.pool_trace_enabled = false
        cfg.pool_trace_enabled = false
        save_cfg()
        state.pool_trace_status = "stopped events=" .. tostring(#state.pool_trace_events)
        dump_pool_trace(true)
        message = state.pool_trace_status
    elseif action == "dump_pool_trace" then
        push_pool_trace_event("dump", true)
        dump_pool_trace(true)
        message = state.pool_trace_status .. " events=" .. tostring(#state.pool_trace_events)
    elseif action == "start_bind_trace" then
        state.bind_trace_enabled = true
        cfg.bind_trace_enabled = true
        save_cfg()
        state.spawn_hook_events = {}
        state.spawn_hook_dirty = true
        state.spawn_hook_status = "cleared for bind trace"
        reset_bind_trace(cmd.text ~= "" and cmd.text or "dev command")
        dump_spawn_hook_log(true)
        dump_bind_trace(true)
        message = state.bind_trace_status
    elseif action == "stop_bind_trace" then
        state.bind_trace_enabled = false
        cfg.bind_trace_enabled = false
        save_cfg()
        state.bind_trace_status = "stopped events=" .. tostring(#state.bind_trace_events)
        dump_bind_trace(true)
        message = state.bind_trace_status
    elseif action == "dump_bind_trace" then
        dump_bind_trace(true)
        message = state.bind_trace_status .. " events=" .. tostring(#state.bind_trace_events)
    elseif action == "diagnostics" then
        dump_runtime_diagnostics()
        message = "runtime diagnostics dumped"
    elseif action == "character_probe" then
        ok, message = run_character_object_probe()
    elseif action == "component_resource_probe" then
        ok, message = run_component_resource_probe()
    elseif action == "visual_component_probe" then
        ok, message = run_visual_component_probe()
    elseif action == "mesh_registration_probe" then
        ok, message = run_mesh_registration_probe()
    elseif action == "spawn_visual_mesh_clone" then
        if not re9mp_is_active_visual_clone_mode(cfg.visual_clone_mode) then
            cfg.visual_clone_mode = "registered_player_material_lit"
            save_cfg()
        end
        local refs = get_local_player_refs()
        ok, message = run_visual_mesh_clone_probe(refs)
    elseif action == "spawn_visual_mesh_clone_force_visible" then
        ok, message = re9mp_archived_dev_action(action, "force-visible debug clone was a negative-control rendering probe")
    elseif action == "spawn_visual_mesh_clone_force_static" then
        ok, message = re9mp_archived_dev_action(action, "force-static debug clone was a negative-control rendering probe")
    elseif action == "spawn_visual_mesh_clone_registered" then
        ok, message = re9mp_archived_dev_action(action, "superseded by registered_player_material_lit")
    elseif action == "spawn_visual_mesh_clone_registered_child" then
        ok, message = re9mp_archived_dev_action(action, "superseded by registered_player_material_lit")
    elseif action == "spawn_visual_mesh_clone_registered_child_material" then
        ok, message = re9mp_archived_dev_action(action, "superseded by registered_player_material_lit")
    elseif action == "spawn_visual_mesh_clone_registered_material" then
        ok, message = re9mp_archived_dev_action(action, "superseded by registered_player_material_lit")
    elseif action == "spawn_visual_mesh_clone_registered_material_lit" then
        cfg.visual_clone_mode = "registered_player_material_lit"
        save_cfg()
        local refs = get_local_player_refs()
        ok, message = run_visual_mesh_clone_probe(refs)
    elseif action == "spawn_visual_mesh_clone_registered_material_lit_detach" then
        ok, message = re9mp_archived_dev_action(action, "detach kept objects alive but made Grace invisible")
    elseif action == "spawn_visual_mesh_clone_registered_material_lit_scene_detach" then
        ok, message = re9mp_archived_dev_action(action, "scene detach lost visible render ownership")
    elseif action == "spawn_visual_mesh_clone_registered_material_lit_owned_anchor_detach" then
        ok, message = re9mp_archived_dev_action(action, "owned-anchor detach lost visible render ownership")
    elseif action == "spawn_visual_mesh_clone_registered_own_player_controller_lit" then
        ok, message = re9mp_archived_dev_action(action, "standalone PlayerMeshController path stayed invisible")
    elseif action == "spawn_visual_mesh_clone_registered_own_player_controller_independent_lit" then
        ok, message = re9mp_archived_dev_action(action, "independent own-controller path stayed invisible")
    elseif action == "spawn_visual_mesh_clone_registered_player_controller_independent_lit" then
        ok, message = re9mp_archived_dev_action(action, "independent local-controller registration stayed invisible")
    elseif action == "spawn_empty_context" then
        ok = false
        message = "disabled: empty ContextID can pollute runtime state; use spawn_new_context"
    elseif action == "spawn_new_context" then
        ok, message = re9mp_archived_dev_action(action, "direct requestSpawn with a fresh ContextID did not create visible Grace")
    elseif action == "spawn_registered_duplicate" then
        ok, message = re9mp_archived_dev_action(action, "duplicated PlayerSpawnData path did not reach a valid visible spawn")
    elseif action == "spawn_ready_duplicate" then
        ok, message = re9mp_archived_dev_action(action, "manual readyContext/requestSpawn duplicate path did not allocate the needed player object")
    elseif action == "spawn_controller_grace" then
        ok, message = re9mp_archived_dev_action(action, "controller replay during gameplay did not bind a new visible context")
    elseif action == "spawn_load_order_grace" then
        ok, message = re9mp_archived_dev_action(action, "old load-order replay was superseded by load-phase injection")
    elseif action == "spawn_trace_order_controller_grace" then
        ok, message = re9mp_archived_dev_action(action, "trace-order controller replay returned ok but did not bind a new context")
    elseif action == "raw_gameobject_clone_probe" then
        ok, message = re9mp_archived_dev_action(action, "raw GameObject clone probe is historical and not part of the active path")
    elseif action == "context_create_probe" then
        ok, message = re9mp_archived_dev_action(action, "basic ContextID creation is now covered by context_reserver_probe")
    elseif action == "set_prefab" then
        ok, message = re9mp_archived_dev_action(action, "prefab path probing is archived until exact asset paths are confirmed")
    elseif action == "resource_probe" then
        ok, message = re9mp_archived_dev_action(action, "broad prefab resource probing generated noisy Missing file overlays")
    elseif action == "probe_prefab" then
        ok, message = re9mp_archived_dev_action(action, "direct prefab spawn probing did not produce a usable Grace path")
    elseif action == "host" then
        send_command("host")
        message = "host command sent"
    elseif action == "disconnect" then
        send_command("disconnect")
        message = "disconnect command sent"
    elseif action == "stop" then
        send_command("stop")
        message = "stop command sent"
    elseif action == "open_window" then
        cfg.window_open = cmd.value ~= false
        save_cfg()
        message = "window_open=" .. tostring(cfg.window_open)
    elseif action:sub(1, 8) == "archive." then
        ok = false
        message = "archive command is documented but not loadable from the normal runtime: " .. action
    else
        ok = false
        message = "unknown or disabled dev action: " .. action
    end

    write_dev_result(id, ok, message)
end

local function apply_remote_pose()
    local pose = current_remote_pose()
    if not pose or not pose.valid then return end

    if update_visual_clone_pose(pose) then return end

    if not state.puppet_xform or not is_valid_managed(state.puppet_xform) then return end

    pcall(function()
        local vec3_td = sdk.find_type_definition("via.vec3")
        if vec3_td then
            local pos = ValueType.new(vec3_td)
            pos.x = pose.px or 0
            pos.y = pose.py or 0
            pos.z = pose.pz or 0
            state.puppet_xform:call("set_Position", pos)
        end
    end)

    pcall(function()
        local quat_td = sdk.find_type_definition("via.Quaternion")
            or sdk.find_type_definition("via.Quaternionf")
        if quat_td then
            local rot = ValueType.new(quat_td)
            rot.x = pose.qx or 0
            rot.y = pose.qy or 0
            rot.z = pose.qz or 0
            rot.w = pose.qw or 1
            state.puppet_xform:call("set_Rotation", rot)
        end
    end)
end

local function draw_remote_marker()
    if not cfg.draw_remote_marker then
        state.draw_status = "disabled"
        return
    end
    local pose = current_remote_pose()
    if not pose or not pose.valid then
        state.draw_status = "no remote pose"
        return
    end

    if not draw then
        state.draw_status = "draw global missing"
        return
    end

    local rr = remote_readout()
    local hud_ok, hud_err = pcall(function()
        if draw.text and rr.valid then
            draw.text("RE9MP REMOTE " .. string.format("%.1fm dx %.1f dz %.1f", rr.dist, rr.dx, rr.dz), 36, 92, 0xFF00FFFF)
            draw.text("HUD fallback active", 36, 110, 0xFF00FFFF)
        end
    end)
    local hud_status = hud_ok and "hud ok" or ("hud failed: " .. safe_string(hud_err))

    local feet, chest, head = nil, nil, nil
    local vec_ok, vec_err = pcall(function()
        feet = Vector3f.new(pose.px or 0, (pose.py or 0) + 0.05, pose.pz or 0)
        chest = Vector3f.new(pose.px or 0, (pose.py or 0) + 1.05, pose.pz or 0)
        head = Vector3f.new(pose.px or 0, (pose.py or 0) + 1.65, pose.pz or 0)
    end)
    if not vec_ok then
        state.draw_status = hud_status .. "; vector failed: " .. safe_string(vec_err)
        return
    end

    local errors = {}
    if draw.capsule then
        local ok, err = pcall(function() draw.capsule(feet, head, 0.24, 0xFF00CCFF, false) end)
        if not ok then table.insert(errors, "capsule " .. safe_string(err)) end
    end
    if draw.sphere then
        local ok, err = pcall(function() draw.sphere(head, 0.18, 0xFF00FFFF, true) end)
        if not ok then table.insert(errors, "sphere " .. safe_string(err)) end
    end
    if draw.world_text then
        local ok, err = pcall(function() draw.world_text("RE9MP remote", chest, 0xFF00FFFF) end)
        if not ok then table.insert(errors, "world_text " .. safe_string(err)) end
    end

    local screen = nil
    if draw.world_to_screen then
        local ok, err = pcall(function() screen = draw.world_to_screen(chest) end)
        if not ok then table.insert(errors, "world_to_screen " .. safe_string(err)) end
    end

    if screen then
        if draw.filled_circle then
            local ok, err = pcall(function() draw.filled_circle(screen.x, screen.y, 8, 0xFF00FFFF, 24) end)
            if not ok then table.insert(errors, "filled_circle " .. safe_string(err)) end
        end
        if draw.text then
            local ok, err = pcall(function() draw.text("RE9MP remote", screen.x + 12, screen.y - 8, 0xFF00FFFF) end)
            if not ok then table.insert(errors, "screen_text " .. safe_string(err)) end
        end
        state.draw_status = string.format("%s; screen %.0f %.0f", hud_status, screen.x or 0, screen.y or 0)
    elseif #errors > 0 then
        state.draw_status = hud_status .. "; world issue: " .. errors[1]
    else
        state.draw_status = hud_status .. "; remote world point not on screen"
    end
end

local function radar_lines(rr)
    if not rr or not rr.valid then return nil end
    local sx = math.floor(clamp(rr.dx / 0.75, -4, 4) + 0.5)
    local sz = math.floor(clamp(rr.dz / 0.75, -2, 2) + 0.5)
    local lines = {}
    table.insert(lines, "+---------+")
    for row = 2, -2, -1 do
        local line = "|"
        for col = -4, 4 do
            if row == 0 and col == 0 then
                line = line .. "Y"
            elseif row == sz and col == sx then
                line = line .. "R"
            elseif row == 2 and col == 0 then
                line = line .. "F"
            else
                line = line .. "."
            end
        end
        line = line .. "|"
        table.insert(lines, line)
    end
    table.insert(lines, "+---------+")
    return lines
end

local function draw_main_window()
    if not cfg.window_open or not imgui.begin_window then return end
    local visible = imgui.begin_window("RE9 Multiplayer MVP##re9mp", true, 0)
    if not visible then
        imgui.end_window()
        return
    end

    local st = state.status or {}
    imgui.text("Native: " .. safe_string(st.state or "waiting"))
    imgui.text("Mode: " .. safe_string(st.mode or "idle"))
    imgui.text("Build: " .. safe_string(st.build_id or "?") .. " | re9.exe " .. safe_string(st.exe_version or "?"))
    imgui.text("Scene: " .. safe_string(get_current_scene()))
    if st.last_error and st.last_error ~= "" then
        imgui.text("Status: " .. safe_string(st.last_error))
    end
    if st.scene_mismatch then
        imgui.text_colored("Scene mismatch: both players must load the same area manually.", 0xFF4444FF)
    end
    if not state.local_ok then
        imgui.text_colored("Local player: " .. safe_string(state.local_error), 0xFF8888FF)
    else
        imgui.text_colored("Local player: detected", 0xFF44FF44)
    end

    imgui.separator()
    if st.mode ~= "host" then
        if imgui.button("Host Lobby") then send_command("host") end
    else
        if imgui.button("Stop Host") then send_command("stop") end
    end
    imgui.same_line()
    if st.mode ~= "idle" then
        if imgui.button("Disconnect") then send_command("disconnect") end
    else
        imgui.text("Disconnected")
    end

    if st.join_code and st.join_code ~= "" then
        imgui.text("Join Code:")
        imgui.text(safe_string(st.join_code))
        if imgui.button("Copy Join Code") then
            pcall(function() imgui.set_clipboard_text(st.join_code) end)
        end
    end

    imgui.separator()
    local changed, join_value = imgui.input_text("Join Code##re9mp_join", cfg.join_code or "")
    if changed then
        cfg.join_code = join_value
        save_cfg()
    end
    if imgui.button("Join") then
        send_command("join", cfg.join_code or "")
    end

    imgui.separator()
    imgui.text("Peer: " .. safe_string(st.peer or ""))
    imgui.text("Ping: " .. safe_string(st.ping_ms or -1) .. " ms")
    imgui.text("Packets sent/recv/drop: "
        .. safe_string(st.packets_sent or 0) .. "/"
        .. safe_string(st.packets_received or 0) .. "/"
        .. safe_string(st.packets_dropped or 0))
    imgui.text("Remote age: " .. safe_string(st.remote_age_ms or 0) .. " ms")
    local rr = remote_readout()
    if rr.valid then
        imgui.text_colored(rr.text, 0xFF00FFFF)
        if math.abs(rr.dx) > math.abs(rr.dz) then
            imgui.text("Direction: mostly " .. (rr.dx > 0 and "+X / right-ish" or "-X / left-ish"))
        else
            imgui.text("Direction: mostly " .. (rr.dz > 0 and "+Z / forward-ish" or "-Z / back-ish"))
        end
        local lines = radar_lines(rr)
        if lines then
            imgui.text("Remote radar: Y=you R=remote F=+Z")
            for _, line in ipairs(lines) do
                imgui.text_colored(line, 0xFF00FFFF)
            end
        end
    else
        imgui.text_colored(rr.text, 0xFF8888FF)
        imgui.text_colored("Offline test: enable Local dummy remote, not Grace spawn probe.", 0xFFAAFFFF)
    end

    imgui.separator()
    if imgui.button("Enable Dummy Marker Test") then
        cfg.local_dummy = true
        cfg.draw_remote_marker = true
        state.remote_samples = {}
        state.remote_last_seq = nil
        save_cfg()
    end
    local auto_changed, auto_val = imgui.checkbox("Auto move spawned puppet", cfg.auto_spawn_puppet)
    if auto_changed then
        cfg.auto_spawn_puppet = auto_val
        save_cfg()
    end
    local marker_changed, marker_val = imgui.checkbox("Draw remote marker", cfg.draw_remote_marker)
    if marker_changed then
        cfg.draw_remote_marker = marker_val
        save_cfg()
    end
    local dummy_changed, dummy_val = imgui.checkbox("Local dummy remote (offline marker test)", cfg.local_dummy)
    if dummy_changed then
        cfg.local_dummy = dummy_val
        state.remote_samples = {}
        state.remote_last_seq = nil
        save_cfg()
    end
    imgui.text("Draw: " .. safe_string(state.draw_status))
    imgui.text("Puppet: " .. safe_string(state.puppet_status))
    if state.character_spawn_status ~= "" then
        imgui.text("CharacterManager: " .. safe_string(state.character_spawn_status))
    end
    if state.character_object_probe ~= "" then
        imgui.text("Character probe dumped to character_probe.json")
    end
    if state.last_spawn_components ~= "" then
        imgui.text("Last spawn components dumped to runtime_diagnostics.json")
    end
    if state.clone_candidates ~= "" then
        imgui.text("Clone candidates: " .. state.clone_candidates)
    end
    if state.scene_candidates ~= "" then
        imgui.text("Scene candidates: " .. state.scene_candidates)
    end
    if state.method_signatures ~= "" then
        imgui.text("Method signatures dumped to runtime_diagnostics.json")
    end
    imgui.text_colored("Archived experiments are disabled in the normal UI.", 0xFF8888FF)
    if state.component_resource_status ~= "" then
        imgui.text("Component resource probe: " .. safe_string(state.component_resource_status))
    end
    if state.visual_probe_status ~= "" then
        imgui.text("Visual probe: " .. safe_string(state.visual_probe_status))
    end
    if imgui.button("Probe Character Objects") then
        run_character_object_probe()
    end
    imgui.same_line()
    if imgui.button("Probe Mesh Registration") then
        run_mesh_registration_probe()
    end
    imgui.same_line()
    if imgui.button("Spawn Lit Control Clone") then
        cfg.visual_clone_mode = "registered_player_material_lit"
        save_cfg()
        local refs = get_local_player_refs()
        run_visual_mesh_clone_probe(refs)
    end
    if state.dev_status ~= "" then
        imgui.text("Dev: " .. safe_string(state.dev_status))
    end
    imgui.text("Spawn hook: " .. safe_string(state.spawn_hook_status))
    imgui.text("Level trace: " .. safe_string(state.level_trace_status))
    imgui.text("Pool trace: " .. safe_string(state.pool_trace_status))
    imgui.text("Bind trace: " .. safe_string(state.bind_trace_status))
    imgui.text("Load injection: " .. safe_string(state.load_phase_injection_status))
    if imgui.button("Install Spawn Hooks") then
        state.spawn_hook_enabled = true
        install_spawn_observer_hooks()
        dump_spawn_hook_log(true)
    end
    local trace_changed, trace_enabled = imgui.checkbox("Record level-load trace", state.level_trace_enabled)
    if trace_changed then
        state.level_trace_enabled = trace_enabled
        state.spawn_hook_enabled = trace_enabled
        cfg.level_trace_enabled = trace_enabled
        save_cfg()
        if trace_enabled then
            reset_level_trace("ui")
        else
            state.level_trace_status = "stopped events=" .. tostring(#state.level_trace_events)
        end
        dump_level_trace(true)
    end
    if imgui.button("Reset Level Trace") then
        state.level_trace_enabled = true
        state.spawn_hook_enabled = true
        cfg.level_trace_enabled = true
        save_cfg()
        reset_level_trace("ui reset")
        dump_level_trace(true)
    end
    imgui.same_line()
    if imgui.button("Dump Level Trace") then
        dump_level_trace(true)
    end
    if imgui.button("Reset Pool Trace") then
        state.pool_trace_enabled = true
        cfg.pool_trace_enabled = true
        save_cfg()
        reset_pool_trace("ui reset")
        push_pool_trace_event("ui reset", true)
        dump_pool_trace(true)
    end
    imgui.same_line()
    if imgui.button("Dump Pool Trace") then
        push_pool_trace_event("ui dump", true)
        dump_pool_trace(true)
    end
    if imgui.button("Reset Bind Trace") then
        state.bind_trace_enabled = true
        cfg.bind_trace_enabled = true
        save_cfg()
        reset_bind_trace("ui reset")
        dump_bind_trace(true)
    end
    imgui.same_line()
    if imgui.button("Dump Bind Trace") then
        dump_bind_trace(true)
    end
    if imgui.button("Refresh Spawn Diagnostics") then
        dump_runtime_diagnostics()
    end
    imgui.same_line()
    if imgui.button("Despawn Puppet") then despawn_puppet() end

    imgui.end_window()
end

re.on_frame(function()
    local t = now()
    if state.spawn_hook_enabled or state.level_trace_enabled then
        install_spawn_observer_hooks()
    end
    if state.bind_trace_enabled then
        install_bind_trace_hooks()
    end
    if state.level_trace_enabled then
        local scene = get_current_scene()
        if scene ~= state.level_trace_last_scene then
            state.level_trace_last_scene = scene
            push_level_trace_note("scene=" .. safe_string(scene))
        end
    end
    if state.pool_trace_enabled then
        local scene = get_current_scene()
        if scene ~= state.pool_trace_last_scene then
            state.pool_trace_last_scene = scene
            push_pool_trace_event("scene=" .. safe_string(scene), true)
        elseif t >= state.pool_trace_last_sample + 0.10 then
            push_pool_trace_event("sample", false)
            state.pool_trace_last_sample = t
        end
    end
    if t >= state.last_snapshot_time + 0.033 then
        write_local_snapshot()
        state.last_snapshot_time = t
    end
    if t >= state.last_status_time + 0.20 then
        read_status()
        state.last_status_time = t
    end
    if t >= state.remote_read_time + 0.02 then
        read_remote_snapshot()
        state.remote_read_time = t
    end
    if t >= state.last_dev_poll + 0.20 then
        poll_dev_command()
        state.last_dev_poll = t
    end
    restore_controller_fields_if_due(false)
    re9mp_poll_load_phase_player_clone_injection()
    update_local_dummy()
    if cfg.auto_runtime_diagnostics and state.local_ok then
        dump_runtime_diagnostics()
    end
    if t >= state.last_spawn_hook_dump + 1.0 then
        dump_spawn_hook_log(false)
        state.last_spawn_hook_dump = t
    end
    if t >= state.level_trace_last_dump + 0.50 then
        dump_level_trace(false)
        state.level_trace_last_dump = t
    end
    if t >= state.pool_trace_last_dump + 0.50 then
        dump_pool_trace(false)
        state.pool_trace_last_dump = t
    end
    if t >= state.bind_trace_last_dump + 0.50 then
        dump_bind_trace(false)
        state.bind_trace_last_dump = t
    end
    apply_remote_pose()
end)

re.on_draw_ui(function()
    if imgui.tree_node("RE9 Multiplayer MVP") then
        imgui.text("Native state: " .. safe_string((state.status or {}).state or "waiting"))
        imgui.same_line()
        if imgui.button("Open##re9mp_open") then cfg.window_open = true; save_cfg() end
        imgui.tree_pop()
    end
    draw_main_window()
    draw_remote_marker()
end)

log.info("[RE9MP] Lua bridge loaded")
