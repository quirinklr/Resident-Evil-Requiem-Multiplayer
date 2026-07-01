-- Mesh copy and registration helpers extracted from pre-split runtime lines 5987-6512.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

function create_visual_game_object(name, folder, fallback_go)
    local errors = {}

    local function try(label, fn)
        local result = nil
        local ok, err = pcall(function() result = fn() end)
        if ok and result and is_valid_managed(result) then
            return result
        end
        table.insert(errors, label .. " -> " .. (ok and safe_string(result) or safe_string(err)))
        return nil
    end

    if folder then
        local result, err = call_static_game_object_create({ name, folder })
        if result then return result, "static folder" end
        table.insert(errors, "static folder " .. safe_string(err))

        if fallback_go then
            local go = try("fallback create(System.String, via.Folder)", function()
                return fallback_go:call("create(System.String, via.Folder)", name, folder)
            end)
            if go then return go, "fallback folder" end
        end
    end

    local result, err = call_static_game_object_create({ name })
    if result then return result, "static" end
    table.insert(errors, "static " .. safe_string(err))

    if fallback_go then
        local go = try("fallback create(System.String)", function()
            return fallback_go:call("create(System.String)", name)
        end)
        if go then return go, "fallback" end
    end

    return nil, table.concat(errors, "; ")
end

function create_mesh_component(go)
    if not go then return nil, "no GameObject" end
    local mesh_type = nil
    pcall(function() mesh_type = sdk.typeof("via.render.Mesh") end)
    if not mesh_type then return nil, "sdk.typeof(via.render.Mesh) failed" end

    local component = nil
    local errors = {}
    for _, call_name in ipairs({ "createComponent(System.Type)", "createComponent" }) do
        local ok, err = pcall(function()
            component = go:call(call_name, mesh_type)
        end)
        if ok and component and is_valid_managed(component) then
            return component, call_name
        end
        table.insert(errors, call_name .. " -> " .. (ok and safe_string(component) or safe_string(err)))
    end
    return nil, table.concat(errors, "; ")
end

function create_component_by_type_name(go, type_name)
    if not go then return nil, "no GameObject" end
    local component_type = nil
    pcall(function() component_type = sdk.typeof(type_name) end)
    if not component_type then return nil, "sdk.typeof(" .. safe_string(type_name) .. ") failed" end

    local component = nil
    local errors = {}
    for _, call_name in ipairs({ "createComponent(System.Type)", "createComponent" }) do
        local ok, err = pcall(function()
            component = go:call(call_name, component_type)
        end)
        if ok and component and is_valid_managed(component) then
            return component, call_name
        end
        table.insert(errors, call_name .. " -> " .. (ok and safe_string(component) or safe_string(err)))
    end
    return nil, table.concat(errors, "; ")
end

function copy_bool_mesh_property(src_mesh, dst_mesh, prop_name)
    local value = nil
    local ok_get = pcall(function() value = src_mesh:call("get_" .. prop_name) end)
    if ok_get and value ~= nil then
        pcall(function() dst_mesh:call("set_" .. prop_name, value) end)
    end
end

function set_mesh_bool(mesh, prop_name, value)
    pcall(function() mesh:call("set_" .. prop_name, value and true or false) end)
end

function set_mesh_float(mesh, prop_name, value)
    pcall(function() mesh:call("set_" .. prop_name, value) end)
end

function read_mesh_bool(mesh, prop_name)
    local value = nil
    pcall(function() value = mesh and mesh:call("get_" .. prop_name) end)
    return value
end

function mesh_render_status(mesh)
    if not mesh then return {} end
    return {
        enabled = read_mesh_bool(mesh, "Enabled"),
        mesh_ready = read_mesh_bool(mesh, "MeshReady"),
        material_ready = read_mesh_bool(mesh, "MaterialReady"),
        draw_default = read_mesh_bool(mesh, "DrawDefault"),
        draw_shadow = read_mesh_bool(mesh, "DrawShadowCast"),
        shared_skeleton = read_mesh_bool(mesh, "SharedSkeleton"),
        static_mesh = read_mesh_bool(mesh, "StaticMesh"),
        frustum_culling = read_mesh_bool(mesh, "FrustumCulling"),
        occlusion_culling = read_mesh_bool(mesh, "OcclusionCulling"),
        ignore_depth = read_mesh_bool(mesh, "IgnoreDepth"),
        force_two_side = read_mesh_bool(mesh, "ForceTwoSide"),
        mesh_holder = safe_string(trace_call(mesh, "getMesh")),
        material_holder = safe_string(trace_call(mesh, "get_Material")),
        shared_skeleton_ref = safe_string(trace_call(mesh, "get_SharedSkeletonGameObject")),
    }
end

function apply_force_visible_mesh_flags(mesh)
    if not mesh then return end
    set_mesh_bool(mesh, "Enabled", true)
    set_mesh_bool(mesh, "DrawDefault", true)
    set_mesh_bool(mesh, "DrawShadowCast", false)
    set_mesh_bool(mesh, "DrawRaytracing", false)
    set_mesh_bool(mesh, "DrawDepthOcclusion", false)
    set_mesh_bool(mesh, "DrawDepthBlocker", false)
    set_mesh_bool(mesh, "FrustumCulling", false)
    set_mesh_bool(mesh, "OcclusionCulling", false)
    set_mesh_bool(mesh, "IgnoreDepth", true)
    set_mesh_bool(mesh, "IgnoreDepthTransparentCorrection", true)
    set_mesh_bool(mesh, "ForceTwoSide", true)
    set_mesh_bool(mesh, "SharedSkeleton", false)
    set_mesh_bool(mesh, "StaticMesh", false)
    set_mesh_float(mesh, "SmallObjectCullingFactor", 0.0)
    local scale = make_vec3(5, 5, 5)
    if scale then
        pcall(function() mesh:call("set_AutoBoundingBoxExtentScaling", scale) end)
    end
end

function apply_force_static_mesh_flags(mesh)
    apply_force_visible_mesh_flags(mesh)
    set_mesh_bool(mesh, "StaticMesh", true)
    set_mesh_bool(mesh, "SharedSkeleton", false)
end

function apply_lit_visible_mesh_flags(src_mesh, dst_mesh)
    if not dst_mesh then return end
    for _, prop in ipairs({
        "StaticMesh",
        "SharedSkeleton",
        "DrawShadowCast",
        "DrawRaytracing",
        "ForceTwoSide",
        "FrustumCulling",
        "OcclusionCulling",
        "ReceiveUserLighting",
        "UseStencilValuePriority",
    }) do
        copy_bool_mesh_property(src_mesh, dst_mesh, prop)
    end

    set_mesh_bool(dst_mesh, "Enabled", true)
    set_mesh_bool(dst_mesh, "DrawDefault", true)
    set_mesh_bool(dst_mesh, "IgnoreDepth", false)
    set_mesh_bool(dst_mesh, "IgnoreDepthTransparentCorrection", false)
    set_mesh_bool(dst_mesh, "DrawDepthOcclusion", true)
    set_mesh_bool(dst_mesh, "DrawDepthBlocker", true)
end

function read_mesh_u32(mesh, call_name, default)
    local value = nil
    pcall(function() value = mesh and mesh:call(call_name) end)
    return tonumber(value) or default or 0
end

function wrapped_array_count(container, fallback)
    if not container then return tonumber(fallback) or 0 end
    local value = nil
    for _, call_name in ipairs({ "get_Count", "get_Length", "get_Size", "get_Num", "getCount" }) do
        local ok = pcall(function() value = container:call(call_name) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return tonumber(fallback) or 0
end

function wrapped_array_get(container, index)
    if not container then return nil, "" end
    local value = nil
    local errors = {}
    for _, call_name in ipairs({
        "get_Item(System.UInt32)",
        "get_Item(System.Int32)",
        "get_Item",
        "get",
        "getElement",
    }) do
        local ok, err = pcall(function() value = container:call(call_name, index) end)
        if ok and value ~= nil then return value, call_name end
        table.insert(errors, call_name .. ": " .. safe_string(err))
    end
    local ok, err = pcall(function() value = container[index] end)
    if ok and value ~= nil then return value, "index" end
    table.insert(errors, "index: " .. safe_string(err))
    return nil, table.concat(errors, " | ")
end

function wrapped_array_set(container, index, value)
    if not container or value == nil then return false, "missing container or value" end
    local errors = {}
    for _, call_name in ipairs({
        "set_Item(System.UInt32)",
        "set_Item(System.Int32)",
        "set_Item",
        "set",
        "setElement",
    }) do
        local ok, err = pcall(function() container:call(call_name, index, value) end)
        if ok then return true, call_name end
        table.insert(errors, call_name .. ": " .. safe_string(err))
    end
    local ok, err = pcall(function() container[index] = value end)
    if ok then return true, "index" end
    table.insert(errors, "index: " .. safe_string(err))
    return false, table.concat(errors, " | ")
end

function copy_wrapped_array(src_container, dst_container, fallback_count, limit)
    local info = {
        attempted = src_container ~= nil and dst_container ~= nil,
        count = 0,
        copied = 0,
        first_get = "",
        first_set = "",
        first_error = "",
    }
    if not info.attempted then
        info.first_error = "missing source or destination container"
        return info
    end

    local count = wrapped_array_count(src_container, fallback_count)
    info.count = count
    local max_count = math.min(count, limit or 32)
    for i = 0, max_count - 1 do
        local value, get_method = wrapped_array_get(src_container, i)
        if value ~= nil then
            local ok_set, set_method = wrapped_array_set(dst_container, i, value)
            if ok_set then
                info.copied = info.copied + 1
                if info.first_get == "" then info.first_get = safe_string(get_method) end
                if info.first_set == "" then info.first_set = safe_string(set_method) end
            elseif info.first_error == "" then
                info.first_error = safe_string(set_method)
            end
        elseif info.first_error == "" then
            info.first_error = safe_string(get_method)
        end
    end
    return info
end

function copy_mesh_material_resources(src_mesh, dst_mesh, label)
    local info = {
        label = safe_string(label or ""),
        source_material_holder = "",
        source_material_ready = read_mesh_bool(src_mesh, "MaterialReady"),
        before_material_holder = safe_string(trace_call(dst_mesh, "get_Material")),
        before_material_ready = read_mesh_bool(dst_mesh, "MaterialReady"),
        holder_set = false,
        holder_method = "",
        holder_error = "",
        source_material_num = read_mesh_u32(src_mesh, "get_MaterialNum", 0),
        dest_material_num_before = read_mesh_u32(dst_mesh, "get_MaterialNum", 0),
    }

    local material_holder = nil
    pcall(function() material_holder = src_mesh and src_mesh:call("get_Material") end)
    info.source_material_holder = safe_string(material_holder)

    if material_holder then
        for _, call_name in ipairs({ "set_Material(via.render.MeshMaterialResourceHolder)", "set_Material" }) do
            local ok, err = pcall(function() dst_mesh:call(call_name, material_holder) end)
            if ok then
                info.holder_set = true
                info.holder_method = call_name
                break
            elseif info.holder_error == "" then
                info.holder_error = safe_string(err)
            end
        end
    else
        info.holder_error = "source get_Material returned nil"
    end

    local param_count = nil
    pcall(function() param_count = src_mesh and src_mesh:call("get_MaterialParamCount") end)
    info.source_material_param_count = tonumber(param_count) or 0
    info.param_count_set = false
    info.param_count_skipped = "disabled after via.render.Mesh.set_MaterialParamCount crash on 2026-07-01"

    local src_materials, dst_materials = nil, nil
    pcall(function() src_materials = src_mesh and src_mesh:call("get_Materials") end)
    pcall(function() dst_materials = dst_mesh and dst_mesh:call("get_Materials") end)
    info.materials_array = copy_wrapped_array(src_materials, dst_materials, info.source_material_num, 32)

    local src_names, dst_names = nil, nil
    pcall(function() src_names = src_mesh and src_mesh:call("get_MaterialNames") end)
    pcall(function() dst_names = dst_mesh and dst_mesh:call("get_MaterialNames") end)
    info.material_names_array = copy_wrapped_array(src_names, dst_names, info.source_material_num, 32)

    info.slot_values = {
        attempted = false,
        skipped = "disabled after via.render.Mesh.getMaterialTexture crash on 2026-07-01",
    }
    info.dest_material_num_after = read_mesh_u32(dst_mesh, "get_MaterialNum", 0)
    info.after_material_holder = safe_string(trace_call(dst_mesh, "get_Material"))
    info.after_material_ready = read_mesh_bool(dst_mesh, "MaterialReady")
    return info
end

function copy_mesh_component_resources(src_mesh, dst_mesh, label, lines, mode, copy_info)
    mode = safe_string(mode or "shared_skeleton")
    local mesh_holder = nil
    pcall(function() mesh_holder = src_mesh and src_mesh:call("getMesh") end)
    if copy_info then
        copy_info.mesh_holder = safe_string(mesh_holder)
    end

    if not mesh_holder then
        if lines then table.insert(lines, label .. " skipped: source getMesh returned nil") end
        return false
    end

    local mesh_set = false
    for _, call_name in ipairs({ "setMesh(via.render.MeshResourceHolder)", "setMesh" }) do
        local ok = pcall(function() dst_mesh:call(call_name, mesh_holder) end)
        if ok then
            mesh_set = true
            break
        end
    end
    if not mesh_set then
        if lines then table.insert(lines, label .. " failed: setMesh rejected holder " .. safe_string(mesh_holder)) end
        return false
    end
    if copy_info then copy_info.mesh_set = true end

    local material_info = copy_mesh_material_resources(src_mesh, dst_mesh, label .. " initial")
    if copy_info then copy_info.material_initial = material_info end

    if mode == "force_static" then
        apply_force_static_mesh_flags(dst_mesh)
    elseif mode == "force_visible" then
        apply_force_visible_mesh_flags(dst_mesh)
    elseif mode == "lit_visible" then
        apply_lit_visible_mesh_flags(src_mesh, dst_mesh)
    else
        for _, prop in ipairs({
            "StaticMesh",
            "SharedSkeleton",
            "DrawShadowCast",
            "DrawRaytracing",
            "ForceTwoSide",
            "FrustumCulling",
            "OcclusionCulling",
            "ReceiveUserLighting",
            "UseStencilValuePriority",
        }) do
            copy_bool_mesh_property(src_mesh, dst_mesh, prop)
        end

        pcall(function() dst_mesh:call("set_Enabled", true) end)
        pcall(function() dst_mesh:call("set_DrawDefault", true) end)
    end

    local material_after_flags = copy_mesh_material_resources(src_mesh, dst_mesh, label .. " after_flags")
    if copy_info then copy_info.material_after_flags = material_after_flags end
    return true
end

function collect_live_mesh_units(mesh_controller, limit)
    local units = {}
    local mesh_unit_dictionary = nil
    pcall(function() mesh_unit_dictionary = mesh_controller:get_field("<MeshUnitDictionary>k__BackingField") end)
    if not mesh_unit_dictionary then return units end

    pcall(function()
        local iter = mesh_unit_dictionary:call("GetEnumerator")
        if not iter then return end
        for _ = 1, (limit or 32) do
            local moved = iter:call("MoveNext")
            if not moved then break end
            local current = iter:call("get_Current")
            local value = nil
            pcall(function() value = current:call("get_Value") end)
            if not value then value = current end
            if trace_type_name(value):find("app.MeshUnit", 1, true) then
                table.insert(units, value)
            end
        end
    end)

    if #units == 0 then
        local count = trace_count(mesh_unit_dictionary)
        for i = 0, math.min(count - 1, (limit or 32) - 1) do
            local value = trace_item(mesh_unit_dictionary, i)
            if trace_type_name(value):find("app.MeshUnit", 1, true) then
                table.insert(units, value)
            end
        end
    end

    return units
end

function get_mesh_unit_dictionary(mesh_controller)
    local dictionary = nil
    pcall(function()
        if mesh_controller then
            dictionary = mesh_controller:get_field("<MeshUnitDictionary>k__BackingField")
                or mesh_controller:call("get_MeshUnitDictionary")
        end
    end)
    return dictionary
end

function find_mesh_unit_key_for_mesh(mesh_controller, mesh)
    local dictionary = get_mesh_unit_dictionary(mesh_controller)
    local mesh_text = safe_string(mesh)
    local found = nil
    pcall(function()
        local iter = dictionary and dictionary:call("GetEnumerator")
        if not iter then return end
        for _ = 1, 256 do
            local moved = iter:call("MoveNext")
            if not moved then break end
            local current = iter:call("get_Current")
            local key, value = nil, nil
            pcall(function() key = current:call("get_Key") end)
            pcall(function() value = current:call("get_Value") end)
            local value_mesh = nil
            pcall(function() value_mesh = value and value:call("get_Mesh") end)
            if safe_string(value_mesh) == mesh_text then
                found = {
                    key = tonumber(key),
                    key_text = safe_string(key),
                    mesh_unit = value,
                    mesh_unit_type = trace_type_name(value),
                    mesh_type = safe_string(trace_call(value, "get_MeshType")),
                    game_object = safe_string(trace_call(value, "get_GameObject")),
                }
                return
            end
        end
    end)
    return found
end

function register_clone_mesh_unit(mesh_controller, clone_mesh, source_unit, report_lines)
    local info = {
        attempted = false,
        ok = false,
        before_count = trace_count(get_mesh_unit_dictionary(mesh_controller)),
        after_count = 0,
        source_mesh_type = "",
        registered_key = nil,
        registered_mesh_unit = "",
        registered_mesh_unit_type = "",
        error = "",
    }
    if not mesh_controller or not clone_mesh or not source_unit then
        info.error = "missing mesh_controller/clone_mesh/source_unit"
        return info
    end

    local mesh_type = nil
    pcall(function() mesh_type = source_unit:call("get_MeshType") end)
    info.source_mesh_type = safe_string(mesh_type)
    if mesh_type == nil then
        info.error = "source MeshUnit get_MeshType returned nil"
        return info
    end

    info.attempted = true
    local ok_register, err_register = pcall(function()
        mesh_controller:call("registerMeshUnit(via.render.Mesh, app.MeshUnit.Type)", clone_mesh, mesh_type)
    end)
    if not ok_register then
        ok_register, err_register = pcall(function()
            mesh_controller:call("registerMeshUnit", clone_mesh, mesh_type)
        end)
    end
    info.after_count = trace_count(get_mesh_unit_dictionary(mesh_controller))
    if not ok_register then
        info.error = safe_string(err_register)
        if report_lines then
            table.insert(report_lines, "registerMeshUnit failed: " .. info.error)
        end
        return info
    end

    local found = find_mesh_unit_key_for_mesh(mesh_controller, clone_mesh)
    if found then
        info.ok = true
        info.registered_key = found.key
        info.registered_key_text = found.key_text
        info.registered_mesh_unit = safe_string(found.mesh_unit)
        info.registered_mesh_unit_type = found.mesh_unit_type
        info.registered_mesh_type = found.mesh_type
        info.registered_game_object = found.game_object
        pcall(function() found.mesh_unit:call("setDrawAndUpdate", true, true) end)
        pcall(function() found.mesh_unit:call("setDrawDefault", true, "RE9MP") end)
        pcall(function() found.mesh_unit:call("setDrawShadow", false, "RE9MP") end)
    else
        info.ok = true
        info.error = "register call succeeded but clone mesh unit key not found"
    end
    info.notify_mesh_unit_changed = "skipped after NullReferenceException/crash on 2026-07-01"
    return info
end
