-- Visual clone foundation helpers extracted from pre-split runtime lines 5420-5986.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function disable_puppet_components(go)
    pcall(function()
        local components = go:call("get_Components")
        if not components then return end
        local count = components:call("get_Count") or 0
        for i = 0, count - 1 do
            pcall(function()
                local comp = components:call("get_Item", i)
                if not comp then return end
                local td = comp:get_type_definition()
                local tname = td and td:get_full_name() or ""
                if tname:find("Input") or tname:find("Camera") or tname:find("Collider")
                    or tname:find("Collision") or tname:find("CharacterController")
                    or tname:find("HitPoint") or tname:find("Damage")
                    or tname:find("BehaviorTree") or tname:find("ActionController")
                    or tname:find("PlayerUpdater") or tname:find("Inventory")
                    or tname:find("Equipment") or tname:find("AI") then
                    pcall(function() comp:call("set_Enabled", false) end)
                end
            end)
        end
    end)
end

local function is_valid_managed(obj)
    local ok, result = pcall(function()
        return obj and sdk.is_managed_object(obj)
    end)
    return ok and result
end

local function get_current_via_scene()
    local scene = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local td = sdk.find_type_definition("via.SceneManager")
        if sm and td then
            scene = sdk.call_native_func(sm, td, "get_CurrentScene()")
                or sdk.call_native_func(sm, td, "get_CurrentScene")
        end
    end)
    return scene
end

local function make_vec3(x, y, z)
    if Vector3f then
        return Vector3f.new(x or 0, y or 0, z or 0)
    end
    local td = sdk.find_type_definition("via.vec3")
    if not td then return nil end
    local value = ValueType.new(td)
    value.x = x or 0
    value.y = y or 0
    value.z = z or 0
    return value
end

local function make_quat(qx, qy, qz, qw)
    local td = sdk.find_type_definition("via.Quaternion") or sdk.find_type_definition("via.Quaternionf")
    if not td then return nil end
    local value = ValueType.new(td)
    value.x = qx or 0
    value.y = qy or 0
    value.z = qz or 0
    value.w = qw or 1
    return value
end

local function get_spawn_pose(refs)
    local pose = current_remote_pose()
    if pose and pose.valid then
        return pose
    end

    local snap = state.local_snapshot
    if not snap or not snap.valid then
        snap = make_local_snapshot()
    end
    local fx, fz = yaw_forward_from_snapshot(snap)
    return {
        valid = true,
        px = (snap.px or 0) + (fx * 2.2),
        py = snap.py or 0,
        pz = (snap.pz or 0) + (fz * 2.2),
        qx = snap.qx or 0,
        qy = snap.qy or 0,
        qz = snap.qz or 0,
        qw = snap.qw or 1,
    }
end

local function get_spawn_folder(refs)
    local folder = nil
    if refs and refs.go then
        pcall(function() folder = refs.go:call("get_Folder") end)
    end
    if folder then return folder end

    local scene = get_current_via_scene()
    if scene then
        pcall(function()
            folder = scene:call("findFolder", "ModdedTemporaryObjects")
                or scene:call("findFolder(System.String)", "ModdedTemporaryObjects")
        end)
    end
    return folder
end

local function first_scene_transform()
    local xform = nil
    pcall(function()
        local scene = get_current_via_scene()
        if not scene then return end
        local transforms = scene:call("findComponents(System.Type)", sdk.typeof("via.Transform"))
        if transforms then xform = transforms[0] end
    end)
    return xform
end

function re9mp_describe_transform(xform)
    local go = nil
    pcall(function() go = xform and xform:call("get_GameObject") end)
    return {
        transform = safe_string(xform),
        game_object = safe_string(go),
        name = safe_string(trace_call(go, "get_Name")),
        position = read_position(xform),
    }
end

local function component_summary_for_go(go, limit)
    local names = {}
    pcall(function()
        local components = go and go:call("get_Components")
        if not components then return end
        local count = components:call("get_Count") or 0
        for i = 0, math.min(count - 1, (limit or 80)) do
            pcall(function()
                local comp = components:call("get_Item", i)
                if not comp then return end
                local td = comp:get_type_definition()
                table.insert(names, td and td:get_full_name() or "unknown")
            end)
        end
    end)
    return table.concat(names, ", ")
end

local function looks_like_grace_character(go, label)
    local summary = component_summary_for_go(go, 90)
    state.last_spawn_components = summary
    local lower_label = tostring(label or ""):lower()
    if lower_label:find("character/ch/ch01/0100") or lower_label:find("ch0100_01") then
        return true
    end
    return summary:find("app.Cp_A100")
        or summary:find("PlayerMeshController")
        or summary:find("ActorPlayerMeshController")
        or summary:find("PlayerThinkDriver")
        or summary:find("via.motion.Motion")
end

local function adopt_puppet_from_result(result, label)
    local go, xform = nil, nil
    if result and is_valid_managed(result) then
        pcall(function() xform = result:call("get_Transform") end)
        if not xform then
            pcall(function()
                local td = result:get_type_definition()
                if td and td:get_full_name() == "via.Transform" then
                    xform = result
                    go = result:call("get_GameObject")
                end
            end)
        end
        if xform and not go then
            pcall(function() go = xform:call("get_GameObject") end)
        end
    end

    if not xform or not is_valid_managed(xform) then
        return false
    end

    if not go then
        state.puppet_status = "spawned transform without GameObject via " .. label
        return false
    end

    if go and not looks_like_grace_character(go, label) then
        state.puppet_status = "spawned non-character via " .. label
        return false
    end

    pcall(function() if go then go = go:add_ref() end end)
    pcall(function() xform = xform:add_ref() end)
    pcall(function() if go then go:call("set_Name", "RE9MP Remote Grace") end end)
    pcall(function() if go then go:call("set_Draw", true) end end)
    pcall(function() if go then go:call("set_UpdateSelf", true) end end)
    if go then disable_puppet_components(go) end

    state.puppet_go = go
    state.puppet_xform = xform
    state.puppet_status = "spawned via " .. label
    return true
end

local function create_prefab_from_path(path)
    path = normalize_prefab_path(path) or path
    if not path or path == "" then return nil, "empty prefab path" end

    local errors = {}
    for _, candidate in ipairs(resource_path_variants(path)) do
        local prefab = nil
        local ok, err = pcall(function()
            prefab = sdk.create_resource("via.Prefab", candidate)
        end)
        if ok and prefab then
            if prefab.add_ref then
                pcall(function() prefab = prefab:add_ref() end)
            end
            return prefab, candidate
        end
        table.insert(errors, candidate .. " -> " .. (ok and "nil" or safe_string(err)))
        if #errors >= 8 then break end
    end
    return nil, "sdk.create_resource returned nil for " .. table.concat(errors, "; ")
end

local function try_spawn_prefab_object(prefab, label, refs)
    if not prefab then return false, "no prefab object" end
    local pose = get_spawn_pose(refs)
    local pos = make_vec3(pose.px or 0, pose.py or 0, pose.pz or 0)
    local rot = make_quat(pose.qx or 0, pose.qy or 0, pose.qz or 0, pose.qw or 1)
    local folder = get_spawn_folder(refs)
    local before = first_scene_transform()

    pcall(function() prefab:call("set_Standby", true) end)
    local calls = {}
    if folder then
        table.insert(calls, { name = "instantiate(via.vec3, via.Quaternion, via.Folder)", args = { pos, rot, folder } })
        table.insert(calls, { name = "instantiate(via.vec3, via.Folder)", args = { pos, folder } })
        table.insert(calls, { name = "instantiate(via.Folder)", args = { folder } })
    end
    table.insert(calls, { name = "instantiate(via.vec3, via.Quaternion)", args = { pos, rot } })
    table.insert(calls, { name = "instantiate(via.vec3)", args = { pos } })
    table.insert(calls, { name = "instantiate()", args = {} })

    local errors = {}
    for _, call in ipairs(calls) do
        if pos then
            local result = nil
            local ok, err = pcall(function()
                result = prefab:call(call.name, unpack_args(call.args))
            end)
            if ok and result and adopt_puppet_from_result(result, label .. ":" .. call.name) then
                return true
            end
            if not ok then table.insert(errors, call.name .. " -> " .. safe_string(err)) end
        end
    end

    local after = first_scene_transform()
    if after and after ~= before and adopt_puppet_from_result(after, label .. ":scene delta") then
        return true
    end

    return false, (#errors > 0 and errors[1] or "prefab instantiate returned no GameObject")
end

local function try_spawn_prefab_candidate(refs)
    collect_prefab_hints(refs)
    local errors = {}

    if cfg.prefab_path and cfg.prefab_path ~= "" then
        if is_effect_prefab_path(cfg.prefab_path) then
            table.insert(errors, "manual path is effect-only, not Grace body")
        else
        local prefab, created_or_err = create_prefab_from_path(cfg.prefab_path)
        if prefab then
            local ok, err = try_spawn_prefab_object(prefab, "manual " .. created_or_err, refs)
            if ok then return true end
            table.insert(errors, "manual: " .. safe_string(err))
        else
            table.insert(errors, "manual create: " .. safe_string(created_or_err))
        end
        end
    end

    for _, candidate in ipairs(state.prefab_hint_objects or {}) do
        local ok, err = try_spawn_prefab_object(candidate.prefab, candidate.label, refs)
        if ok then return true end
        table.insert(errors, candidate.label .. ": " .. safe_string(err))
    end

    for _, path in ipairs(state.prefab_hint_paths or {}) do
        local prefab, created_or_err = create_prefab_from_path(path)
        if prefab then
            local ok, err = try_spawn_prefab_object(prefab, path, refs)
            if ok then return true end
            table.insert(errors, path .. ": " .. safe_string(err))
        else
            table.insert(errors, path .. ": " .. safe_string(created_or_err))
        end
    end

    for _, path in ipairs(DEFAULT_GRACE_PREFAB_PATHS) do
        local prefab, created_or_err = create_prefab_from_path(path)
        if prefab then
            local ok, err = try_spawn_prefab_object(prefab, path, refs)
            if ok then return true end
            table.insert(errors, path .. ": " .. safe_string(err))
        else
            table.insert(errors, path .. ": " .. safe_string(created_or_err))
        end
    end

    if #errors == 0 then
        return false, "no via.Prefab/path hints found on Grace yet"
    end
    return false, errors[1]
end

function hold_managed_ref(obj)
    local held = obj
    pcall(function()
        if obj and obj.add_ref then held = obj:add_ref() end
    end)
    return held
end

function hide_game_object(go)
    if not go then return end
    pcall(function() go:call("set_Draw", false) end)
    pcall(function() go:call("set_DrawSelf", false) end)
    pcall(function() go:call("set_UpdateSelf", false) end)
    pcall(function() go:call("set_Active", false) end)
end

function clear_puppet_refs(status)
    hide_game_object(state.puppet_go)
    hide_game_object(state.puppet_anchor_go)
    for _, unit in ipairs(state.puppet_visual_units or {}) do
        if unit.registration_controller and unit.registration_key ~= nil then
            pcall(function()
                unit.registration_controller:call("unregisterMeshUnit(System.UInt32)", unit.registration_key)
            end)
            pcall(function()
                unit.registration_controller:call("unregisterMeshUnit", unit.registration_key)
            end)
        end
        hide_game_object(unit.go)
    end
    state.puppet_go = nil
    state.puppet_xform = nil
    state.puppet_anchor_go = nil
    state.puppet_root_parented = false
    state.puppet_local_hierarchy = false
    state.puppet_independent_root = false
    state.puppet_visual_units = {}
    if status then state.puppet_status = status end
end

function read_scale(xform)
    local scale = nil
    pcall(function() scale = xform and xform:call("get_Scale") end)
    if not scale then return { x = 1, y = 1, z = 1 } end
    return {
        x = float_field(scale, "x", 1),
        y = float_field(scale, "y", 1),
        z = float_field(scale, "z", 1),
    }
end

function set_transform_pose(xform, pos, rot, scale)
    if not xform then return end
    if pos then
        local v = make_vec3(pos.x or 0, pos.y or 0, pos.z or 0)
        if v then pcall(function() xform:call("set_Position", v) end) end
    end
    if rot then
        local q = make_quat(rot.x or 0, rot.y or 0, rot.z or 0, rot.w or 1)
        if q then pcall(function() xform:call("set_Rotation", q) end) end
    end
    if scale then
        local s = make_vec3(scale.x or 1, scale.y or 1, scale.z or 1)
        if s then pcall(function() xform:call("set_Scale", s) end) end
    end
end

function set_transform_local_pose(xform, pos, rot, scale)
    if not xform then return end
    if pos then
        local v = make_vec3(pos.x or 0, pos.y or 0, pos.z or 0)
        if v then pcall(function() xform:call("set_LocalPosition", v) end) end
    end
    if rot then
        local q = make_quat(rot.x or 0, rot.y or 0, rot.z or 0, rot.w or 1)
        if q then pcall(function() xform:call("set_LocalRotation", q) end) end
    end
    if scale then
        local s = make_vec3(scale.x or 1, scale.y or 1, scale.z or 1)
        if s then pcall(function() xform:call("set_LocalScale", s) end) end
    end
end

function parent_transform_keep_world(child_xform, parent_xform)
    local info = {
        attempted = child_xform ~= nil and parent_xform ~= nil,
        ok = false,
        method = "",
        error = "",
    }
    if not info.attempted then
        info.error = "missing child or parent transform"
        return info
    end

    local ok, err = pcall(function()
        child_xform:call("setParent", parent_xform, true)
    end)
    if ok then
        info.ok = true
        info.method = "setParent(via.Transform,true)"
        return info
    end
    info.error = safe_string(err)

    ok, err = pcall(function()
        child_xform:call("set_Parent", parent_xform)
    end)
    if ok then
        info.ok = true
        info.method = "set_Parent(via.Transform)"
        return info
    end
    info.error = info.error .. " | set_Parent: " .. safe_string(err)

    ok, err = pcall(function()
        child_xform:call("setParentDirect", parent_xform)
    end)
    if ok then
        info.ok = true
        info.method = "setParentDirect(via.Transform)"
        return info
    end
    info.error = info.error .. " | setParentDirect: " .. safe_string(err)
    return info
end

function detach_transform_keep_world(go, xform, folder, pos, rot, scale)
    local info = {
        attempted = xform ~= nil,
        ok = false,
        method = "",
        error = "",
        before_position = read_position(xform),
        before_local_position = read_local_position(xform),
    }
    if not info.attempted then
        info.error = "missing transform"
        return info
    end

    local ok, err = pcall(function()
        xform:call("setParent", nil, true)
    end)
    if ok then
        info.ok = true
        info.method = "setParent(nil,true)"
    else
        info.error = safe_string(err)
        ok, err = pcall(function()
            xform:call("set_Parent", nil)
        end)
        if ok then
            info.ok = true
            info.method = "set_Parent(nil)"
        else
            info.error = info.error .. " | set_Parent(nil): " .. safe_string(err)
            ok, err = pcall(function()
                xform:call("setParentDirect", nil)
            end)
            if ok then
                info.ok = true
                info.method = "setParentDirect(nil)"
            else
                info.error = info.error .. " | setParentDirect(nil): " .. safe_string(err)
            end
        end
    end

    if go and folder then
        local folder_ok, folder_err = pcall(function()
            go:call("set_FolderSelf", folder)
        end)
        info.folder_set = folder_ok and true or false
        info.folder_error = folder_ok and "" or safe_string(folder_err)
    end
    if info.ok then
        set_transform_pose(xform, pos, rot, scale)
    end
    info.after_position = read_position(xform)
    info.after_local_position = read_local_position(xform)
    return info
end

function update_visual_clone_pose(pose)
    if not pose or not pose.valid then return false end
    if state.puppet_independent_root then return false end
    if state.puppet_local_hierarchy and state.puppet_xform and is_valid_managed(state.puppet_xform) then
        local snap = state.local_snapshot
        if not snap or not snap.valid then snap = make_local_snapshot() end
        if snap and snap.valid then
            local local_pos = world_delta_to_local_yaw(
                snap,
                (pose.px or 0) - (snap.px or 0),
                (pose.py or 0) - (snap.py or 0),
                (pose.pz or 0) - (snap.pz or 0)
            )
            local local_rot = quat_multiply(quat_conjugate(snapshot_rotation(snap)), pose_rotation(pose))
            set_transform_local_pose(state.puppet_xform, local_pos, local_rot, nil)
            return true
        end
    end

    local handled = false
    for _, unit in ipairs(state.puppet_visual_units or {}) do
        if unit.xform and is_valid_managed(unit.xform) then
            local offset = unit.offset or { x = 0, y = 0, z = 0 }
            set_transform_pose(unit.xform, {
                x = (pose.px or 0) + (offset.x or 0),
                y = (pose.py or 0) + (offset.y or 0),
                z = (pose.pz or 0) + (offset.z or 0),
            }, unit.rotation, unit.scale)
            handled = true
        end
    end
    return handled
end

function call_static_game_object_create(args)
    local td = sdk.find_type_definition("via.GameObject")
    if not td then return nil, "via.GameObject type not found" end

    local last_error = "no matching create overload"
    for _, method in ipairs(td:get_methods()) do
        local name = method:get_name() or ""
        if name == "create" then
            local params = 999
            pcall(function() params = method:get_num_params() end)
            if params == #args then
                local result = nil
                local ok, err = pcall(function()
                    result = method:call(nil, unpack_args(args))
                end)
                if ok and result and is_valid_managed(result) then
                    return result, method_signature(method)
                end
                last_error = method_signature(method) .. " -> " .. (ok and safe_string(result) or safe_string(err))
            end
        end
    end

    return nil, last_error
end
