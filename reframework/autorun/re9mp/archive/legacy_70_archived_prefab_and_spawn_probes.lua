-- Archived prefab and spawn probes extracted from pre-split runtime lines 7126-7425.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

local function run_resource_probe(custom_path)
    local inputs = {}
    if custom_path and safe_string(custom_path) ~= "" then
        add_unique(inputs, safe_string(custom_path), 24)
    end
    for _, path in ipairs(DEFAULT_GRACE_PREFAB_PATHS) do
        add_unique(inputs, path, 24)
    end
    add_unique(inputs, "vfx/provider/epv_character/epvc_ch_prefab_id/epvc2_cp_a100.pfb", 24)
    add_unique(inputs, "natives/stm/vfx/provider/epv_character/epvc_ch_prefab_id/epvc2_cp_a100.pfb.18", 24)

    local rows = {}
    local found = nil
    for _, input in ipairs(inputs) do
        local row = { input = input, ok = false, path = "", attempts = {} }
        for _, candidate in ipairs(resource_path_variants(input)) do
            local prefab = nil
            local ok, err = pcall(function()
                prefab = sdk.create_resource("via.Prefab", candidate)
            end)
            local attempt = {
                path = candidate,
                ok = ok and prefab ~= nil,
                error = ok and (prefab and "" or "nil") or safe_string(err),
            }
            table.insert(row.attempts, attempt)
            if attempt.ok then
                row.ok = true
                row.path = candidate
                found = found or candidate
                break
            end
            if #row.attempts >= 8 then break end
        end
        table.insert(rows, row)
    end

    state.resource_probe_status = found and ("found " .. found) or "no via.Prefab resource loaded"
    pcall(function()
        json.dump_file(RESOURCE_PROBE_FILE, {
            time_ms = now_ms(),
            status = state.resource_probe_status,
            rows = rows,
        })
    end)
    return found ~= nil, state.resource_probe_status
end

local function try_character_manager_spawn(refs)
    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then return false, "CharacterManager not found" end

    local calls = {
        {
            name = "requestSpawn(app.ContextID, app.CharacterKindID, app.MontageID, System.Int32, System.Boolean, app.CharacterUsePurposeFlag)",
            args = { 1, 13632, 0, 0, true, 0 },
            label = "cp_A100/A100/default",
        },
        {
            name = "requestSpawn(app.ContextID, app.CharacterKindID, app.MontageID, System.Int32, System.Boolean, app.CharacterUsePurposeFlag)",
            args = { 1, 13632, 0, 0, false, 0 },
            label = "cp_A100/A100/no-force",
        },
        {
            name = "requestSpawn(app.ContextID, app.CharacterKindID, app.MontageID, System.Int32, System.Boolean, app.CharacterUsePurposeFlag)",
            args = { 1, 1, 0, 0, true, 0 },
            label = "cp_A100/kind1/default",
        },
    }

    local errors = {}
    for _, call in ipairs(calls) do
        local ok, err = pcall(function()
            char_mgr:call(call.name, unpack_args(call.args))
        end)
        if ok then
            state.character_spawn_status = "requestSpawn accepted: " .. call.label
            state.puppet_status = "requestSpawn sent via CharacterManager; look for new Grace"
            return true
        else
            table.insert(errors, call.label .. ": " .. safe_string(err))
        end
    end

    state.character_spawn_status = (#errors > 0 and errors[1]) or "requestSpawn had no callable overload"
    return false, state.character_spawn_status
end

local function try_character_manager_only()
    state.puppet_last_attempt = now()
    local refs = get_local_player_refs()
    if not refs.valid then
        state.puppet_status = "no local player for CharacterManager probe"
        return false
    end
    local ok, err = try_character_manager_spawn(refs)
    if not ok then
        state.puppet_status = "CharacterManager probe failed: " .. safe_string(err)
    end
    return ok
end

local function try_spawn_puppet(manual)
    state.puppet_last_attempt = now()
    local refs = get_local_player_refs()
    if not refs.valid or not refs.go then
        state.puppet_status = "no local player to clone"
        return false
    end

    local prefab_ok, prefab_err = try_spawn_prefab_candidate(refs)
    if prefab_ok then return true end

    local visual_ok, visual_err = run_visual_mesh_clone_probe(refs)
    if visual_ok then return true end

    local character_err = ""
    if manual then
        local character_ok, err = try_character_manager_spawn(refs)
        if character_ok then return true end
        character_err = " | character manager: " .. safe_string(err)
    end

    collect_clone_candidates(refs.go)

    local clone = nil
    local methods = {
        "clone", "Clone", "copy", "Copy", "duplicate", "Duplicate",
        "instantiate", "Instantiate", "createClone", "CreateClone",
    }

    for _, method in ipairs(methods) do
        local ok, result = pcall(function() return refs.go:call(method) end)
        if ok and result and is_valid_managed(result) then
            clone = result
            state.puppet_status = "spawned via " .. method
            break
        end
    end

    if not clone then
        state.puppet_status = "prefab failed: " .. safe_string(prefab_err)
            .. " | visual mesh: " .. safe_string(visual_err)
            .. character_err
            .. " | clone method not found yet"
        return false
    end

    pcall(function() clone:call("set_Name", "RE9MP Remote Grace") end)
    pcall(function() clone:call("set_Draw", true) end)
    pcall(function() clone:call("set_UpdateSelf", true) end)
    disable_puppet_components(clone)

    local xform = nil
    pcall(function() xform = clone:call("get_Transform") end)
    if not xform then
        state.puppet_status = "clone has no transform"
        return false
    end

    state.puppet_go = clone
    state.puppet_xform = xform
    return true
end

function re9mp_run_raw_gameobject_clone_probe()
    local refs = get_local_player_refs()
    local report = {
        time_ms = now_ms(),
        scene = get_current_scene(),
        local_player = refs and refs.valid and true or false,
        local_error = refs and refs.error or "",
        source_go = safe_string(refs and refs.go),
        source_go_name = safe_string(refs and refs.name),
        source_components = refs and refs.go and component_summary_for_go(refs.go, 120) or "",
        candidates = {},
        attempts = {},
        ok = false,
        status = "",
    }

    if not refs or not refs.valid or not refs.go then
        report.status = "raw clone probe failed: " .. safe_string(refs and refs.error)
        state.puppet_status = report.status
        pcall(function() json.dump_file(DATA_PREFIX .. "raw_gameobject_clone_probe.json", report) end)
        return false, report.status
    end

    clear_puppet_refs("raw clone probe")

    local exact_names = {
        clone = true,
        Clone = true,
        copy = true,
        Copy = true,
        duplicate = true,
        Duplicate = true,
        instantiate = true,
        Instantiate = true,
        createClone = true,
        CreateClone = true,
    }
    local td = nil
    pcall(function() td = refs.go:get_type_definition() end)
    local seen_types = {}
    local depth = 0
    local success = false

    while td and depth < 8 and not success do
        local type_name = td:get_full_name() or "?"
        if seen_types[type_name] then break end
        seen_types[type_name] = true

        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name() or ""
            local params = 999
            pcall(function() params = method:get_num_params() end)
            local ret = method:get_return_type()
            local ret_name = ret and ret:get_full_name() or ""
            local interesting = name:find("clone") or name:find("Clone")
                or name:find("copy") or name:find("Copy")
                or name:find("duplicate") or name:find("Duplicate")
                or name:find("instantiate") or name:find("Instantiate")
            if interesting then
                local row = {
                    declaring_type = type_name,
                    signature = method_signature(method),
                    params = params,
                    return_type = ret_name,
                    called = false,
                    ok = false,
                    error = "",
                    result = "",
                    result_type = "",
                    result_components = "",
                    adopted = false,
                }
                table.insert(report.candidates, row)

                if params == 0 and exact_names[name] and #report.attempts < 12 then
                    row.called = true
                    local result = nil
                    local ok_call, err_call = pcall(function()
                        result = method:call(refs.go)
                    end)
                    row.ok = ok_call and result ~= nil and is_valid_managed(result)
                    row.error = ok_call and (result and "" or "nil") or safe_string(err_call)
                    row.result = safe_string(result)
                    row.result_type = trace_type_name(result)

                    local result_go = nil
                    local result_xform = nil
                    pcall(function() result_xform = result and result:call("get_Transform") end)
                    if not result_xform then
                        pcall(function()
                            local rtd = result and result:get_type_definition()
                            if rtd and rtd:get_full_name() == "via.Transform" then
                                result_xform = result
                            end
                        end)
                    end
                    pcall(function() result_go = result_xform and result_xform:call("get_GameObject") end)
                    if result_go then
                        row.result_go = safe_string(result_go)
                        row.result_go_name = safe_string(trace_call(result_go, "get_Name"))
                        row.result_components = component_summary_for_go(result_go, 120)
                    end

                    table.insert(report.attempts, row)
                    if result and safe_string(result) ~= safe_string(refs.go) then
                        local adopted = adopt_puppet_from_result(result, "raw " .. row.signature)
                        row.adopted = adopted and true or false
                        if adopted then
                            report.ok = true
                            report.status = "raw GameObject clone adopted via " .. row.signature
                            success = true
                            break
                        end
                    end
                end

                if #report.candidates >= 80 then break end
            end
        end

        td = get_parent_type_definition(td)
        depth = depth + 1
    end

    if not report.ok then
        report.status = "raw GameObject clone probe found no usable no-arg clone/copy/instantiate method"
        state.puppet_status = report.status
    else
        state.puppet_status = report.status
    end

    pcall(function() json.dump_file(DATA_PREFIX .. "raw_gameobject_clone_probe.json", report) end)
    return report.ok, report.status .. " candidates=" .. tostring(#report.candidates) .. " attempts=" .. tostring(#report.attempts)
end
