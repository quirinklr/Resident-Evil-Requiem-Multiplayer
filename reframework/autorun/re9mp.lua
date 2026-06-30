-- RE9 Multiplayer MVP bridge.
-- Native plugin: UDP lobby/networking.
-- Lua bridge: RE9 player/scene sampling, overlay UI, and best-effort remote puppet.

local MOD_VERSION = "0.1.0"
local DATA_PREFIX = "re9mp/"
local CFG_FILE = DATA_PREFIX .. "config.json"
local COMMAND_FILE = DATA_PREFIX .. "command.json"
local LOCAL_FILE = DATA_PREFIX .. "local_snapshot.json"
local STATUS_FILE = DATA_PREFIX .. "status.json"
local REMOTE_FILE = DATA_PREFIX .. "remote_snapshot.json"

local cfg = {
    window_open = true,
    join_code = "",
    command_id = 0,
    auto_spawn_puppet = true,
    draw_remote_marker = true,
}

pcall(function()
    local loaded = json.load_file(CFG_FILE)
    if loaded then
        for k, v in pairs(loaded) do cfg[k] = v end
    end
end)

local function save_cfg()
    pcall(function() json.dump_file(CFG_FILE, cfg) end)
end

local function now()
    return os.clock()
end

local function now_ms()
    return math.floor(now() * 1000.0)
end

local function safe_string(v)
    if v == nil then return "" end
    return tostring(v)
end

local state = {
    seq = 0,
    last_sample_time = 0,
    last_snapshot_time = 0,
    last_status_time = 0,
    status = nil,
    local_snapshot = nil,
    local_ok = false,
    local_error = "Waiting for player",
    last_pos = nil,
    last_pos_time = nil,
    remote_last_seq = nil,
    remote_prev_seq = nil,
    remote_seq_changed_at = 0,
    remote_samples = {},
    remote_read_time = 0,
    puppet_go = nil,
    puppet_xform = nil,
    puppet_status = "not spawned",
    puppet_last_attempt = 0,
    clone_candidates = "",
    scene_candidates = "",
    component_summary = "",
    method_signatures = "",
    player_fields = "",
    last_diagnostic_dump = 0,
}

local function get_current_scene()
    local scene = ""
    pcall(function()
        local fm = sdk.get_managed_singleton("app.MainGameFlowManager")
        if not fm then return end
        local ctrl = fm:get_field("_CurrentController")
        if not ctrl then return end
        local cur = ctrl:get_field("_CurrentMainSceneName")
        if cur then scene = tostring(cur) end
    end)
    return scene
end

local function get_local_player_refs()
    local result = { valid = false, error = "CharacterManager not found" }
    pcall(function()
        local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
        if not char_mgr then return end

        local player = char_mgr:call("get_PlayerContextFast")
        if not player then
            result.error = "PlayerContext not found"
            return
        end

        local go = nil
        pcall(function() go = player:call("get_GameObject") end)
        if not go then
            pcall(function()
                local t = player:get_field("Transform")
                if t then go = t:call("get_GameObject") end
            end)
        end
        if not go then
            result.error = "Player GameObject not found"
            return
        end

        local xform = nil
        pcall(function() xform = go:call("get_Transform") end)
        if not xform then
            result.error = "Player Transform not found"
            return
        end

        result.valid = true
        result.error = ""
        result.player = player
        result.go = go
        result.xform = xform
        pcall(function() result.name = go:call("get_Name") end)
    end)
    return result
end

local function float_field(obj, key, default)
    local direct = nil
    pcall(function() direct = obj[key] end)
    if direct ~= nil then return tonumber(direct) or default end
    local via_get_field = nil
    pcall(function() via_get_field = obj:get_field(key) end)
    if via_get_field ~= nil then return tonumber(via_get_field) or default end
    return default
end

local function read_position(xform)
    local pos = nil
    pcall(function() pos = xform:call("get_Position") end)
    if not pos then return nil end
    return {
        x = float_field(pos, "x", 0),
        y = float_field(pos, "y", 0),
        z = float_field(pos, "z", 0),
    }
end

local function read_rotation(xform)
    local rot = nil
    pcall(function() rot = xform:call("get_Rotation") end)
    if not rot then
        return { x = 0, y = 0, z = 0, w = 1 }
    end
    return {
        x = float_field(rot, "x", 0),
        y = float_field(rot, "y", 0),
        z = float_field(rot, "z", 0),
        w = float_field(rot, "w", 1),
    }
end

local function make_local_snapshot()
    local refs = get_local_player_refs()
    local scene = get_current_scene()
    if not refs.valid then
        state.local_ok = false
        state.local_error = refs.error
        return {
            valid = false,
            seq = state.seq,
            time_ms = now_ms(),
            scene = scene,
            error = refs.error,
            mod_version = MOD_VERSION,
        }
    end

    local pos = read_position(refs.xform)
    if not pos then
        state.local_ok = false
        state.local_error = "Position not readable"
        return {
            valid = false,
            seq = state.seq,
            time_ms = now_ms(),
            scene = scene,
            error = state.local_error,
            mod_version = MOD_VERSION,
        }
    end

    local t = now()
    local vx, vy, vz = 0, 0, 0
    if state.last_pos and state.last_pos_time and t > state.last_pos_time then
        local dt = t - state.last_pos_time
        vx = (pos.x - state.last_pos.x) / dt
        vy = (pos.y - state.last_pos.y) / dt
        vz = (pos.z - state.last_pos.z) / dt
    end
    state.last_pos = pos
    state.last_pos_time = t

    local speed2d = math.sqrt((vx * vx) + (vz * vz))
    local moving = speed2d > 0.05
    local rot = read_rotation(refs.xform)
    local flags = moving and 1 or 0
    local stance = moving and "move" or "idle"

    state.seq = state.seq + 1
    state.local_ok = true
    state.local_error = ""

    return {
        valid = true,
        seq = state.seq,
        time_ms = now_ms(),
        scene = scene,
        player_name = safe_string(refs.name),
        px = pos.x,
        py = pos.y,
        pz = pos.z,
        qx = rot.x,
        qy = rot.y,
        qz = rot.z,
        qw = rot.w,
        vx = vx,
        vy = vy,
        vz = vz,
        flags = flags,
        motion = stance,
        stance = stance,
        mod_version = MOD_VERSION,
    }
end

local function write_local_snapshot()
    local snap = make_local_snapshot()
    state.local_snapshot = snap
    pcall(function() json.dump_file(LOCAL_FILE, snap) end)
end

local function read_status()
    pcall(function()
        local st = json.load_file(STATUS_FILE)
        if st then state.status = st end
    end)
end

local function send_command(action, endpoint)
    cfg.command_id = (cfg.command_id or 0) + 1
    local cmd = {
        id = cfg.command_id,
        action = action,
        endpoint = endpoint or "",
        scene = get_current_scene(),
        mod_version = MOD_VERSION,
    }
    pcall(function() json.dump_file(COMMAND_FILE, cmd) end)
    save_cfg()
end

local function read_remote_snapshot()
    local data = nil
    pcall(function() data = json.load_file(REMOTE_FILE) end)
    if not data or not data.valid then return end
    if state.remote_last_seq == data.seq then return end

    state.remote_last_seq = data.seq
    table.insert(state.remote_samples, {
        t = now(),
        data = data,
    })
    while #state.remote_samples > 12 do
        table.remove(state.remote_samples, 1)
    end
end

local function lerp(a, b, f)
    return a + ((b - a) * f)
end

local function current_remote_pose()
    if #state.remote_samples == 0 then return nil end
    if #state.remote_samples == 1 then return state.remote_samples[1].data end

    local target = now() - 0.10
    local older = state.remote_samples[1]
    local newer = state.remote_samples[#state.remote_samples]

    for i = 1, #state.remote_samples - 1 do
        local a = state.remote_samples[i]
        local b = state.remote_samples[i + 1]
        if a.t <= target and target <= b.t then
            older = a
            newer = b
            break
        end
    end

    if older == newer or newer.t <= older.t then
        return newer.data
    end

    local f = (target - older.t) / (newer.t - older.t)
    if f < 0 then f = 0 end
    if f > 1 then f = 1 end

    return {
        valid = true,
        seq = newer.data.seq,
        scene = newer.data.scene,
        px = lerp(older.data.px or 0, newer.data.px or 0, f),
        py = lerp(older.data.py or 0, newer.data.py or 0, f),
        pz = lerp(older.data.pz or 0, newer.data.pz or 0, f),
        qx = lerp(older.data.qx or 0, newer.data.qx or 0, f),
        qy = lerp(older.data.qy or 0, newer.data.qy or 0, f),
        qz = lerp(older.data.qz or 0, newer.data.qz or 0, f),
        qw = lerp(older.data.qw or 1, newer.data.qw or 1, f),
        vx = newer.data.vx or 0,
        vy = newer.data.vy or 0,
        vz = newer.data.vz or 0,
        flags = newer.data.flags or 0,
        motion = newer.data.motion or "",
        stance = newer.data.stance or "",
    }
end

local function remote_readout()
    local pose = current_remote_pose()
    local local_snap = state.local_snapshot
    if not pose or not pose.valid then
        return {
            valid = false,
            text = "Remote: no snapshot",
        }
    end

    local dx, dy, dz, dist = 0, 0, 0, 0
    if local_snap and local_snap.valid then
        dx = (pose.px or 0) - (local_snap.px or 0)
        dy = (pose.py or 0) - (local_snap.py or 0)
        dz = (pose.pz or 0) - (local_snap.pz or 0)
        dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
    end

    local speed = math.sqrt(((pose.vx or 0) * (pose.vx or 0)) + ((pose.vz or 0) * (pose.vz or 0)))
    local age = 0
    if #state.remote_samples > 0 then
        age = math.floor((now() - state.remote_samples[#state.remote_samples].t) * 1000)
    end

    return {
        valid = true,
        text = string.format(
            "Remote: seq %s | age %dms | %.1fm away | dx %.1f dz %.1f | %s %.2fm/s",
            safe_string(pose.seq), age, dist, dx, dz, safe_string(pose.stance), speed
        ),
        dx = dx,
        dz = dz,
        dist = dist,
        speed = speed,
    }
end

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
        local params = method:get_params()
        local ptxt = {}
        if params then
            for _, p in ipairs(params) do
                local ptype = p.t and p.t:get_full_name() or "?"
                local pname = p.name or "arg"
                table.insert(ptxt, ptype .. " " .. pname)
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
        {"app.CharacterManager", {"requestSpawn", "requestInstantiateMontage", "getSpawnDataRef", "getSpawnedContextRefList", "getSpawnableContextList"}},
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

local function collect_player_fields(player)
    local lines = {}
    pcall(function()
        local td = player:get_type_definition()
        if not td then return end
        for _, field in ipairs(td:get_fields()) do
            local name = field:get_name()
            local ftype = field:get_type()
            local type_name = ftype and ftype:get_full_name() or "?"
            if name and (name:find("Spawn") or name:find("spawn")
                    or name:find("Context") or name:find("context")
                    or name:find("ID") or name:find("Id")
                    or name:find("User") or name:find("user")
                    or name:find("Character") or name:find("character")) then
                table.insert(lines, type_name .. " " .. name)
            end
        end
    end)
    state.player_fields = table.concat(lines, "\n")
end

local function collect_scene_candidates()
    local patterns = {
        "create", "Create", "spawn", "Spawn", "instantiate", "Instantiate",
        "GameObject", "Prefab", "Resource", "add", "Add",
    }
    local names = {}

    local function append(label, list)
        if #list == 0 then return end
        table.insert(names, label .. ": " .. table.concat(list, ", "))
    end

    append("via.SceneManager", collect_methods_from_type("via.SceneManager", patterns, 30))
    append("via.Scene", collect_methods_from_type("via.Scene", patterns, 30))
    append("via.GameObject", collect_methods_from_type("via.GameObject", patterns, 40))
    append("app.CharacterManager", collect_methods_from_type("app.CharacterManager", patterns, 40))

    state.scene_candidates = table.concat(names, " | ")
end

local function collect_component_summary(go)
    local counts = {}
    local names = {}
    pcall(function()
        local components = go:call("get_Components")
        if not components then return end
        local count = components:call("get_Count") or 0
        for i = 0, math.min(count - 1, 80) do
            pcall(function()
                local comp = components:call("get_Item", i)
                if not comp then return end
                local td = comp:get_type_definition()
                local tname = td and td:get_full_name() or "unknown"
                if not counts[tname] then
                    counts[tname] = true
                    table.insert(names, tname)
                end
            end)
        end
    end)
    state.component_summary = table.concat(names, ", ")
end

local function dump_runtime_diagnostics()
    if now() < state.last_diagnostic_dump + 2.0 then return end
    state.last_diagnostic_dump = now()

    local refs = get_local_player_refs()
    if refs.valid and refs.go then
        collect_clone_candidates(refs.go)
        collect_component_summary(refs.go)
        collect_player_fields(refs.player)
    end
    collect_scene_candidates()
    collect_method_signatures()

    pcall(function()
        json.dump_file(DATA_PREFIX .. "runtime_diagnostics.json", {
            time_ms = now_ms(),
            scene = get_current_scene(),
            player_valid = refs.valid,
            player_name = refs.name or "",
            clone_candidates = state.clone_candidates,
            scene_candidates = state.scene_candidates,
            component_summary = state.component_summary,
            method_signatures = state.method_signatures,
            player_fields = state.player_fields,
        })
    end)
end

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

local function try_spawn_puppet()
    state.puppet_last_attempt = now()
    local refs = get_local_player_refs()
    if not refs.valid or not refs.go then
        state.puppet_status = "no local player to clone"
        return false
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
        state.puppet_status = "clone method not found yet"
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

local function despawn_puppet()
    if state.puppet_go then
        pcall(function() state.puppet_go:call("set_Draw", false) end)
        pcall(function() state.puppet_go:call("set_Active", false) end)
    end
    state.puppet_go = nil
    state.puppet_xform = nil
    state.puppet_status = "despawned"
end

local function apply_remote_pose()
    local pose = current_remote_pose()
    if not pose or not pose.valid then return end

    if (not state.puppet_xform or not is_valid_managed(state.puppet_xform))
        and cfg.auto_spawn_puppet and now() > state.puppet_last_attempt + 2.0 then
        try_spawn_puppet()
    end

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
    if not cfg.draw_remote_marker then return end
    local pose = current_remote_pose()
    if not pose or not pose.valid then return end

    pcall(function()
        local feet = Vector3f.new(pose.px or 0, (pose.py or 0) + 0.05, pose.pz or 0)
        local chest = Vector3f.new(pose.px or 0, (pose.py or 0) + 1.05, pose.pz or 0)
        local head = Vector3f.new(pose.px or 0, (pose.py or 0) + 1.65, pose.pz or 0)
        draw.capsule(feet, head, 0.24, 0xFF00CCFF, false)
        draw.sphere(head, 0.18, 0xFF00FFFF, true)
        draw.world_text("RE9MP remote", chest, 0xFF00FFFF)
    end)
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
    else
        imgui.text_colored(rr.text, 0xFF8888FF)
    end

    imgui.separator()
    local auto_changed, auto_val = imgui.checkbox("Auto spawn remote puppet", cfg.auto_spawn_puppet)
    if auto_changed then
        cfg.auto_spawn_puppet = auto_val
        save_cfg()
    end
    local marker_changed, marker_val = imgui.checkbox("Draw remote marker", cfg.draw_remote_marker)
    if marker_changed then
        cfg.draw_remote_marker = marker_val
        save_cfg()
    end
    imgui.text("Puppet: " .. safe_string(state.puppet_status))
    if state.clone_candidates ~= "" then
        imgui.text("Clone candidates: " .. state.clone_candidates)
    end
    if state.scene_candidates ~= "" then
        imgui.text("Scene candidates: " .. state.scene_candidates)
    end
    if state.method_signatures ~= "" then
        imgui.text("Method signatures dumped to runtime_diagnostics.json")
    end
    if imgui.button("Spawn Puppet Probe") then try_spawn_puppet() end
    imgui.same_line()
    if imgui.button("Despawn Puppet") then despawn_puppet() end

    imgui.end_window()
end

re.on_frame(function()
    local t = now()
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
    if state.status and state.status.connected then
        dump_runtime_diagnostics()
    end
    apply_remote_pose()
    draw_remote_marker()
end)

re.on_draw_ui(function()
    if imgui.tree_node("RE9 Multiplayer MVP") then
        imgui.text("Native state: " .. safe_string((state.status or {}).state or "waiting"))
        imgui.same_line()
        if imgui.button("Open##re9mp_open") then cfg.window_open = true; save_cfg() end
        imgui.tree_pop()
    end
    draw_main_window()
end)

log.info("[RE9MP] Lua bridge loaded")
