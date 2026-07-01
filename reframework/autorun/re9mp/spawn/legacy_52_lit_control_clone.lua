-- Visible lit control clone path extracted from pre-split runtime lines 6513-6893.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

function run_visual_mesh_clone_probe(refs)
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        ok = false,
        local_player = refs and refs.valid and true or false,
        local_error = refs and refs.error or "",
        visual_clone_mode = safe_string(cfg.visual_clone_mode or "shared_skeleton"),
        safety = {
            clear_shared_skeleton_game_object = false,
            notify_mesh_unit_changed = false,
            set_material_param_count = false,
        },
        lines = {},
        units = {},
    }

    if not refs or not refs.valid or not refs.go or not refs.xform then
        local message = "visual mesh clone failed: no local player"
        state.puppet_status = message
        pcall(function() json.dump_file(VISUAL_SPAWN_PROBE_FILE, report) end)
        return false, message
    end

    clear_puppet_refs("spawning visual mesh clone")

    local mesh_controller = find_component_by_type_name(refs.go, "app.PlayerMeshController")
    if not mesh_controller then
        local message = "visual mesh clone failed: PlayerMeshController not found"
        state.puppet_status = message
        pcall(function() json.dump_file(VISUAL_SPAWN_PROBE_FILE, report) end)
        return false, message
    end

    local units = collect_live_mesh_units(mesh_controller, 32, { exclude_re9mp_clones = true })
    report.source_mesh_units = #units
    if #units == 0 then
        local message = "visual mesh clone failed: MeshUnitDictionary empty"
        state.puppet_status = message
        pcall(function() json.dump_file(VISUAL_SPAWN_PROBE_FILE, report) end)
        return false, message
    end

    local folder = get_spawn_folder(refs)
    local visual_mode = safe_string(cfg.visual_clone_mode or "shared_skeleton")
    local own_player_controller_independent_mode = visual_mode == "registered_own_player_controller_independent_lit"
    local local_player_controller_independent_mode = visual_mode == "registered_player_controller_independent_lit"
    local material_post_mode = visual_mode == "registered_player_child_material"
        or visual_mode == "registered_player_material"
        or visual_mode == "registered_player_material_lit"
        or visual_mode == "registered_player_material_lit_local"
        or visual_mode == "registered_player_material_lit_detach"
        or visual_mode == "registered_player_material_lit_scene_detach"
        or visual_mode == "registered_player_material_lit_owned_anchor_detach"
        or visual_mode == "registered_own_player_controller_lit"
        or own_player_controller_independent_mode
        or local_player_controller_independent_mode
    local registered_mode = visual_mode == "registered_player_controller"
        or visual_mode == "registered_player_child"
        or material_post_mode
    local own_player_controller_mode = visual_mode == "registered_own_player_controller_lit"
        or own_player_controller_independent_mode
    local child_hierarchy_mode = (visual_mode == "registered_player_child" or material_post_mode)
        and not own_player_controller_independent_mode
        and not local_player_controller_independent_mode
    local detach_after_register_mode = visual_mode == "registered_player_material_lit_detach"
    local scene_detach_after_register_mode = visual_mode == "registered_player_material_lit_scene_detach"
        or visual_mode == "registered_player_material_lit_owned_anchor_detach"
    local local_hierarchy_mode = visual_mode == "registered_player_material_lit"
        or visual_mode == "registered_player_material_lit_local"
        or detach_after_register_mode
        or scene_detach_after_register_mode
    local copy_mode = (visual_mode == "registered_player_material_lit"
            or local_hierarchy_mode
            or own_player_controller_mode
            or local_player_controller_independent_mode) and "lit_visible"
        or (registered_mode and "force_visible" or visual_mode)
    local scene_anchor_go, scene_anchor_xform, scene_anchor_info = nil, nil, nil
    if scene_detach_after_register_mode then
        scene_anchor_info = {
            attempted = true,
            ok = false,
            error = "not created yet",
            created_by = "",
            selected = nil,
        }
        report.scene_detach_anchor = scene_anchor_info
    end
    local root_go, root_created_by = create_visual_game_object("RE9MP Remote Grace Visual " .. visual_mode, folder, refs.go)
    if not root_go then
        local message = "visual mesh clone failed: create root GameObject: " .. safe_string(root_created_by)
        state.puppet_status = message
        table.insert(report.lines, message)
        pcall(function() json.dump_file(VISUAL_SPAWN_PROBE_FILE, report) end)
        return false, message
    end

    local root_xform = nil
    pcall(function() root_xform = root_go:call("get_Transform") end)
    local pose = get_spawn_pose(refs)
    report.pose = {
        x = pose.px or 0,
        y = pose.py or 0,
        z = pose.pz or 0,
        qx = pose.qx or 0,
        qy = pose.qy or 0,
        qz = pose.qz or 0,
        qw = pose.qw or 1,
    }
    if scene_detach_after_register_mode then
        local anchor_created_by = ""
        scene_anchor_go, anchor_created_by = create_visual_game_object("RE9MP Remote Grace Scene Anchor", folder, nil)
        scene_anchor_info.created_by = safe_string(anchor_created_by)
        if scene_anchor_go then
            pcall(function() scene_anchor_xform = scene_anchor_go:call("get_Transform") end)
            pcall(function() scene_anchor_go:call("set_Name", "RE9MP Remote Grace Scene Anchor") end)
            pcall(function() scene_anchor_go:call("set_Draw", false) end)
            pcall(function() scene_anchor_go:call("set_DrawSelf", false) end)
            pcall(function() scene_anchor_go:call("set_UpdateSelf", true) end)
            set_transform_pose(scene_anchor_xform, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0, w = 1 }, nil)
            scene_anchor_info.ok = scene_anchor_xform ~= nil
            scene_anchor_info.error = scene_anchor_xform and "" or "anchor transform missing"
            scene_anchor_info.selected = re9mp_describe_transform(scene_anchor_xform)
        else
            scene_anchor_info.error = "create anchor failed: " .. safe_string(anchor_created_by)
        end
        report.scene_detach_anchor = scene_anchor_info
    end
    set_transform_pose(root_xform, {
        x = pose.px or 0,
        y = pose.py or 0,
        z = pose.pz or 0,
    }, {
        x = pose.qx or 0,
        y = pose.qy or 0,
        z = pose.qz or 0,
        w = pose.qw or 1,
    }, nil)
    pcall(function() root_go:call("set_Name", "RE9MP Remote Grace Visual") end)
    pcall(function() root_go:call("set_Draw", true) end)
    pcall(function() root_go:call("set_DrawSelf", true) end)
    pcall(function() root_go:call("set_UpdateSelf", true) end)
    report.root_position_before_parent = read_position(root_xform)
    local registration_mesh_controller = mesh_controller
    if own_player_controller_mode then
        local own_controller, own_controller_by = create_component_by_type_name(root_go, "app.PlayerMeshController")
        report.own_player_controller = {
            attempted = true,
            created_by = safe_string(own_controller_by),
            ref = safe_string(own_controller),
            type = trace_type_name(own_controller),
            before_search = re9mp_trace_mesh_controller_summary(own_controller, "own PlayerMeshController before search"),
        }
        if own_controller then
            registration_mesh_controller = own_controller
            pcall(function() own_controller:call("searchInitMeshUnits") end)
            report.own_player_controller.after_search = re9mp_trace_mesh_controller_summary(own_controller, "own PlayerMeshController after search")
        else
            local message = "visual mesh clone failed: create own PlayerMeshController: " .. safe_string(own_controller_by)
            state.puppet_status = message
            table.insert(report.lines, message)
            pcall(function() json.dump_file(VISUAL_SPAWN_PROBE_FILE, report) end)
            return false, message
        end
    end
    local local_snap = state.local_snapshot
    if not local_snap or not local_snap.valid then
        local_snap = make_local_snapshot()
    end
    if child_hierarchy_mode then
        report.root_parenting = parent_transform_keep_world(root_xform, refs.xform)
        if local_hierarchy_mode then
            local local_pos = world_delta_to_local_yaw(
                local_snap,
                (pose.px or 0) - ((local_snap and local_snap.px) or 0),
                (pose.py or 0) - ((local_snap and local_snap.py) or 0),
                (pose.pz or 0) - ((local_snap and local_snap.pz) or 0)
            )
            local local_rot = quat_multiply(quat_conjugate(snapshot_rotation(local_snap)), pose_rotation(pose))
            set_transform_local_pose(root_xform, local_pos, local_rot, nil)
            report.root_local_hierarchy = true
            report.root_local_pose_set = {
                position = local_pos,
                rotation = local_rot,
            }
        else
            set_transform_pose(root_xform, {
                x = pose.px or 0,
                y = pose.py or 0,
                z = pose.pz or 0,
            }, {
                x = pose.qx or 0,
                y = pose.qy or 0,
                z = pose.qz or 0,
                w = pose.qw or 1,
            }, nil)
        end
    end
    report.root_position_after_parent = read_position(root_xform)
    report.root_local_position_after_parent = read_local_position(root_xform)

    local local_root_pos = read_position(refs.xform) or { x = pose.px or 0, y = pose.py or 0, z = pose.pz or 0 }
    report.local_root_pos = local_root_pos
    local created = 0

    for i, unit in ipairs(units) do
        local source_go, source_mesh = nil, nil
        pcall(function() source_go = unit:call("get_GameObject") end)
        pcall(function() source_mesh = unit:call("get_Mesh") end)

        local row = {
            index = i - 1,
            mesh_unit = safe_string(unit),
            source_go = safe_string(source_go),
            source_mesh = safe_string(source_mesh),
            source_mesh_type = trace_type_name(source_mesh),
            source_mesh_unit_type = safe_string(trace_call(unit, "get_MeshType")),
            source_render = mesh_render_status(source_mesh),
        }

        if source_mesh and source_go then
            local clone_go, created_by = create_visual_game_object("RE9MP Remote Grace Mesh " .. visual_mode .. " " .. tostring(i - 1), folder, refs.go)
            row.clone_create = safe_string(created_by)
            if clone_go then
                local clone_xform = nil
                pcall(function() clone_xform = clone_go:call("get_Transform") end)

                local source_xform = nil
                pcall(function() source_xform = source_go:call("get_Transform") end)
                local source_pos = read_position(source_xform) or local_root_pos
                local source_rot = read_rotation(source_xform)
                local source_scale = read_scale(source_xform)
                local offset = {
                    x = (source_pos.x or 0) - (local_root_pos.x or 0),
                    y = (source_pos.y or 0) - (local_root_pos.y or 0),
                    z = (source_pos.z or 0) - (local_root_pos.z or 0),
                }
                local local_offset = world_delta_to_local_yaw(local_snap, offset.x, offset.y, offset.z)
                local local_rotation = quat_multiply(quat_conjugate(snapshot_rotation(local_snap)), source_rot)
                row.source_pos = source_pos
                row.offset = offset
                row.local_offset = local_offset
                row.local_rotation = local_rotation
                set_transform_pose(clone_xform, {
                    x = (pose.px or 0) + offset.x,
                    y = (pose.py or 0) + offset.y,
                    z = (pose.pz or 0) + offset.z,
                }, source_rot, source_scale)
                row.clone_position_before_parent = read_position(clone_xform)
                if child_hierarchy_mode then
                    row.parenting = parent_transform_keep_world(clone_xform, root_xform)
                    if local_hierarchy_mode then
                        set_transform_local_pose(clone_xform, local_offset, local_rotation, source_scale)
                    else
                        set_transform_pose(clone_xform, {
                            x = (pose.px or 0) + offset.x,
                            y = (pose.py or 0) + offset.y,
                            z = (pose.pz or 0) + offset.z,
                        }, source_rot, source_scale)
                    end
                end
                row.clone_position_after_parent = read_position(clone_xform)
                row.clone_local_position_after_parent = read_local_position(clone_xform)

                local clone_mesh, mesh_component_by = create_mesh_component(clone_go)
                row.clone_go = safe_string(clone_go)
                row.clone_mesh = safe_string(clone_mesh)
                row.clone_mesh_component = safe_string(mesh_component_by)

                row.resource_copy = {}
                if clone_mesh and copy_mesh_component_resources(source_mesh, clone_mesh, "unit " .. tostring(i - 1), report.lines, copy_mode, row.resource_copy) then
                    local registration = nil
                    if registered_mode then
                        registration = register_clone_mesh_unit(registration_mesh_controller, clone_mesh, unit, report.lines)
                        row.registration = registration
                    end
                    if material_post_mode then
                        row.material_post_register = copy_mesh_material_resources(source_mesh, clone_mesh, "unit " .. tostring(i - 1) .. " post_register")
                    end
                    pcall(function() clone_go:call("set_Draw", true) end)
                    pcall(function() clone_go:call("set_DrawSelf", true) end)
                    pcall(function() clone_go:call("set_UpdateSelf", true) end)
                    pcall(function() clone_mesh:call("set_Enabled", true) end)
                    row.clone_position_final = read_position(clone_xform)
                    row.clone_local_position_final = read_local_position(clone_xform)
                    local stored_unit = {
                        go = hold_managed_ref(clone_go),
                        xform = hold_managed_ref(clone_xform),
                        mesh = hold_managed_ref(clone_mesh),
                        offset = offset,
                        local_offset = local_offset,
                        local_rotation = local_rotation,
                        rotation = source_rot,
                        scale = source_scale,
                        parented = child_hierarchy_mode,
                        local_hierarchy = local_hierarchy_mode,
                    }
                    if registration and registration.registered_key ~= nil then
                        stored_unit.registration_controller = hold_managed_ref(registration_mesh_controller)
                        stored_unit.registration_key = registration.registered_key
                    end
                    table.insert(state.puppet_visual_units, stored_unit)
                    created = created + 1
                    row.ok = true
                    row.clone_render = mesh_render_status(clone_mesh)
                else
                    hide_game_object(clone_go)
                    row.ok = false
                    row.clone_render = mesh_render_status(clone_mesh)
                end
            else
                row.ok = false
            end
        else
            row.ok = false
        end
        table.insert(report.units, row)
    end

    local detach_ok = false
    if (detach_after_register_mode or scene_detach_after_register_mode) and created > 0 then
        local pose_pos = {
            x = pose.px or 0,
            y = pose.py or 0,
            z = pose.pz or 0,
        }
        local pose_rot = {
            x = pose.qx or 0,
            y = pose.qy or 0,
            z = pose.qz or 0,
            w = pose.qw or 1,
        }
        if scene_detach_after_register_mode then
            report.detach_after_register = scene_anchor_xform
                and parent_transform_keep_world(root_xform, scene_anchor_xform)
                or { attempted = false, ok = false, method = "scene_anchor", error = scene_anchor_info and scene_anchor_info.error or "no scene anchor" }
            if report.detach_after_register and report.detach_after_register.ok then
                report.detach_after_register.method = "scene_anchor:" .. safe_string(report.detach_after_register.method)
                if root_go and folder then
                    pcall(function() root_go:call("set_FolderSelf", folder) end)
                end
                set_transform_pose(root_xform, pose_pos, pose_rot, nil)
            end
        else
            report.detach_after_register = detach_transform_keep_world(root_go, root_xform, folder, pose_pos, pose_rot, nil)
        end
        detach_ok = report.detach_after_register and report.detach_after_register.ok and true or false
        local child_local_reset = 0
        for _, unit in ipairs(state.puppet_visual_units or {}) do
            if unit.xform and is_valid_managed(unit.xform) then
                set_transform_local_pose(unit.xform, unit.local_offset or unit.offset, unit.local_rotation or unit.rotation, unit.scale)
                child_local_reset = child_local_reset + 1
            end
            pcall(function()
                if unit.go and folder then unit.go:call("set_FolderSelf", folder) end
            end)
        end
        report.detach_child_local_reset = child_local_reset
        report.detach_root_position_final = read_position(root_xform)
        report.detach_root_local_position_final = read_local_position(root_xform)
    end

    state.puppet_go = hold_managed_ref(root_go)
    state.puppet_xform = hold_managed_ref(root_xform)
    state.puppet_anchor_go = scene_anchor_go and hold_managed_ref(scene_anchor_go) or nil
    state.puppet_root_parented = child_hierarchy_mode and not detach_ok
    state.puppet_local_hierarchy = local_hierarchy_mode and not detach_ok
    state.puppet_independent_root = detach_ok
    report.created_units = created
    report.ok = created > 0
    report.independent_root = state.puppet_independent_root and true or false
    report.parented_control_path = state.puppet_root_parented and true or false
    report.control_path_note = state.puppet_root_parented
        and "visible render/material proof only; follows local player transform"
        or ""

    if created > 0 then
        if state.puppet_root_parented then
            state.puppet_status = "parented visual control clone spawned units=" .. tostring(created)
        elseif state.puppet_independent_root then
            state.puppet_status = "independent visual mesh clone spawned units=" .. tostring(created)
        else
            state.puppet_status = "visual mesh clone spawned units=" .. tostring(created)
        end
    else
        clear_puppet_refs("visual mesh clone failed: no mesh components copied")
    end

    report.status = state.puppet_status
    pcall(function() json.dump_file(VISUAL_SPAWN_PROBE_FILE, report) end)
    return created > 0, state.puppet_status
end
