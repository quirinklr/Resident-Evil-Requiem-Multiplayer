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
    local_dummy = false,
    prefab_path = "",
    auto_runtime_diagnostics = false,
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

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

local function safe_string(v)
    if v == nil then return "" end
    return tostring(v)
end

local unpack_args = table.unpack or unpack

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
    dummy_seq = 0,
    dummy_last_time = 0,
    puppet_go = nil,
    puppet_xform = nil,
    puppet_status = "not spawned",
    puppet_last_attempt = 0,
    clone_candidates = "",
    scene_candidates = "",
    component_summary = "",
    method_signatures = "",
    player_fields = "",
    prefab_hints = "",
    prefab_hint_paths = {},
    prefab_hint_objects = {},
    character_spawn_status = "",
    character_spawn_diagnostics = "",
    last_spawn_components = "",
    last_diagnostic_dump = 0,
    draw_status = "not drawn yet",
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

local function yaw_forward_from_snapshot(snap)
    if not snap then return 0, 1 end
    local qx = snap.qx or 0
    local qy = snap.qy or 0
    local qz = snap.qz or 0
    local qw = snap.qw or 1
    local yaw = atan2(2.0 * ((qw * qy) + (qx * qz)), 1.0 - (2.0 * ((qy * qy) + (qz * qz))))
    local fx = math.sin(yaw)
    local fz = math.cos(yaw)
    local len = math.sqrt((fx * fx) + (fz * fz))
    if len < 0.001 then return 0, 1 end
    return fx / len, fz / len
end

local function update_local_dummy()
    if not cfg.local_dummy then return end
    local snap = state.local_snapshot
    if not snap or not snap.valid then return end
    local t = now()
    if t < state.dummy_last_time + 0.033 then return end
    state.dummy_last_time = t
    state.dummy_seq = state.dummy_seq + 1

    local fx, fz = yaw_forward_from_snapshot(snap)
    local side_x, side_z = fz, -fx
    local distance = 2.4
    local sway = math.sin(t * 1.8) * 0.45
    local px = (snap.px or 0) + (fx * distance) + (side_x * sway)
    local pz = (snap.pz or 0) + (fz * distance) + (side_z * sway)
    local vx = (side_x * math.cos(t * 1.8) * 0.81)
    local vz = (side_z * math.cos(t * 1.8) * 0.81)
    local dummy = {
        valid = true,
        seq = state.dummy_seq,
        scene = snap.scene,
        px = px,
        py = snap.py or 0,
        pz = pz,
        qx = 0,
        qy = snap.qy or 0,
        qz = 0,
        qw = snap.qw or 1,
        vx = vx,
        vy = 0,
        vz = vz,
        flags = 1,
        motion = "dummy",
        stance = "dummy",
    }
    table.insert(state.remote_samples, { t = t, data = dummy })
    while #state.remote_samples > 12 do
        table.remove(state.remote_samples, 1)
    end
end

local function lerp(a, b, f)
    return a + ((b - a) * f)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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
        local ptxt = {}
        local param_types = method:get_param_types()
        local param_names = method:get_param_names()
        if param_types then
            for i, ptype in ipairs(param_types) do
                local type_name = ptype and ptype:get_full_name() or "?"
                local pname = (param_names and param_names[i]) or ("arg" .. tostring(i))
                table.insert(ptxt, type_name .. " " .. pname)
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

local function add_unique(list, value, limit)
    if not value or value == "" then return false end
    value = tostring(value)
    for _, existing in ipairs(list) do
        if existing == value then return false end
    end
    if #list < (limit or 40) then
        table.insert(list, value)
        return true
    end
    return false
end

local function normalize_prefab_path(text)
    if not text or text == "" then return nil end
    text = tostring(text):gsub("\\", "/")
    local bracket = text:match("%[@?([^%]]+%.pfb)%]")
    local direct = text:match("([%w%p%s_%-/]+%.pfb)")
    local path = bracket or direct
    if not path then return nil end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    path = path:gsub("^natives/%w%w%w/", "")
    return path
end

local function is_effect_prefab_path(path)
    if not path then return false end
    local lower = tostring(path):lower():gsub("\\", "/")
    return lower:find("^vfx/")
        or lower:find("/vfx/")
        or lower:find("epv_")
        or lower:find("epvc")
        or lower:find("effect")
end

local function is_character_prefab_path(path)
    if not path or is_effect_prefab_path(path) then return false end
    local lower = tostring(path):lower():gsub("\\", "/")
    return lower:find("cp_a100")
        or lower:find("a100")
        or lower:find("player")
        or lower:find("character")
        or lower:find("chara")
end

local function path_from_managed_value(value)
    if value == nil then return nil end
    if type(value) == "string" then
        return normalize_prefab_path(value)
    end
    if type(value) ~= "userdata" and type(value) ~= "table" then return nil end

    local text = nil
    for _, method in ipairs({"get_Path", "ToString", "get_Name"}) do
        pcall(function()
            if not text and value.call then
                local result = value:call(method)
                if result then text = tostring(result) end
            end
        end)
        local path = normalize_prefab_path(text)
        if path then return path end
    end
    return nil
end

local function is_prefab_object(value)
    if not value or (type(value) ~= "userdata" and type(value) ~= "table") then return false end
    local ok, result = pcall(function()
        if not value.get_type_definition then return false end
        local td = value:get_type_definition()
        if not td then return false end
        local name = td:get_full_name()
        return name == "via.Prefab"
    end)
    return ok and result
end

local function collect_prefab_hints_from_object(label, obj, lines, paths, objects)
    if not obj or not obj.get_type_definition then return end

    pcall(function()
        local td = obj:get_type_definition()
        if not td then return end
        for _, field in ipairs(td:get_fields()) do
            local fname = field:get_name() or ""
            local ftype = field:get_type()
            local tname = ftype and ftype:get_full_name() or ""
            local interesting = fname:find("Prefab") or fname:find("prefab")
                or fname:find("Pfb") or fname:find("pfb")
                or fname:find("Resource") or fname:find("resource")
                or tname:find("Prefab") or tname:find("Resource")
            if interesting then
                local value = nil
                pcall(function() value = obj:get_field(fname) end)
                local path = path_from_managed_value(value)
                if path then
                    local prefix = is_effect_prefab_path(path) and "effect-only " or ""
                    if is_character_prefab_path(path) then
                        add_unique(paths, path, 24)
                    end
                    add_unique(lines, prefix .. label .. "." .. fname .. " -> " .. path, 24)
                end
                if is_prefab_object(value) and not is_effect_prefab_path(path) then
                    table.insert(objects, { label = label .. "." .. fname, prefab = value })
                end
            end
        end
    end)

    pcall(function()
        local td = obj:get_type_definition()
        if not td then return end
        for _, method in ipairs(td:get_methods()) do
            local name = method:get_name() or ""
            local ret = method:get_return_type()
            local ret_name = ret and ret:get_full_name() or ""
            local interesting = name:find("get_") == 1
                and (name:find("Prefab") or name:find("prefab") or name:find("Resource") or ret_name:find("Prefab"))
                and method:get_num_params() == 0
            if interesting then
                local value = nil
                pcall(function() value = obj:call(name) end)
                local path = path_from_managed_value(value)
                if path then
                    local prefix = is_effect_prefab_path(path) and "effect-only " or ""
                    if is_character_prefab_path(path) then
                        add_unique(paths, path, 24)
                    end
                    add_unique(lines, prefix .. label .. ":" .. name .. "() -> " .. path, 24)
                end
                if is_prefab_object(value) and not is_effect_prefab_path(path) then
                    table.insert(objects, { label = label .. ":" .. name .. "()", prefab = value })
                end
            end
        end
    end)
end

local function collect_prefab_hints(refs)
    local lines, paths, objects = {}, {}, {}
    if refs and refs.valid then
        collect_prefab_hints_from_object("PlayerContext", refs.player, lines, paths, objects)
        collect_prefab_hints_from_object("PlayerGO", refs.go, lines, paths, objects)
        pcall(function()
            local components = refs.go:call("get_Components")
            if not components then return end
            local count = components:call("get_Count") or 0
            for i = 0, math.min(count - 1, 90) do
                pcall(function()
                    local comp = components:call("get_Item", i)
                    if not comp then return end
                    local td = comp:get_type_definition()
                    local label = td and td:get_full_name() or ("Component" .. tostring(i))
                    collect_prefab_hints_from_object(label, comp, lines, paths, objects)
                end)
            end
        end)
    end

    state.prefab_hint_paths = paths
    state.prefab_hint_objects = objects
    state.prefab_hints = table.concat(lines, "\n")
end

local function type_static_lines(type_name, limit)
    local lines = {}
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then
            table.insert(lines, type_name .. ": type not found")
            return
        end
        local n = 0
        for _, field in ipairs(td:get_fields()) do
            if field:is_static() then
                local name = field:get_name()
                local value = nil
                pcall(function() value = field:get_data(nil) end)
                if value ~= nil then
                    table.insert(lines, type_name .. "." .. safe_string(name) .. "=" .. safe_string(value))
                    n = n + 1
                end
                if n >= (limit or 16) then break end
            end
        end
        if n == 0 then table.insert(lines, type_name .. ": no static enum fields visible") end
    end)
    return lines
end

local function object_field_summary(label, obj, limit)
    local lines = {}
    if not obj or not obj.get_type_definition then return lines end
    pcall(function()
        local td = obj:get_type_definition()
        table.insert(lines, label .. " type=" .. (td and td:get_full_name() or "?"))
        if not td then return end
        local n = 0
        for _, field in ipairs(td:get_fields()) do
            local name = field:get_name() or ""
            local ftype = field:get_type()
            local type_name = ftype and ftype:get_full_name() or "?"
            local interesting = name:find("Context") or name:find("Kind") or name:find("Character")
                or name:find("Chara") or name:find("Player") or name:find("Montage")
                or name:find("Spawn") or name:find("Prefab") or name:find("Resource")
                or type_name:find("Context") or type_name:find("Kind") or type_name:find("Prefab")
            if interesting then
                local value = nil
                pcall(function() value = obj:get_field(name) end)
                local path = path_from_managed_value(value)
                local text = path or safe_string(value)
                table.insert(lines, "  " .. type_name .. " " .. name .. " = " .. text)
                n = n + 1
                if n >= (limit or 28) then break end
            end
        end
    end)
    return lines
end

local function collect_character_spawn_diagnostics(refs)
    local lines = {}
    for _, type_name in ipairs({
        "app.ContextID",
        "app.CharacterKindID",
        "app.MontageID",
        "app.CharacterUsePurposeFlag",
    }) do
        for _, line in ipairs(type_static_lines(type_name, 20)) do
            table.insert(lines, line)
        end
    end

    local char_mgr = sdk.get_managed_singleton("app.CharacterManager")
    if not char_mgr then
        state.character_spawn_diagnostics = table.concat(lines, "\n")
        return
    end

    for _, id in ipairs({1, 0, 2, 13632}) do
        local data = nil
        local ok, err = pcall(function()
            data = char_mgr:call("getSpawnDataRef(app.ContextID)", id)
                or char_mgr:call("getSpawnDataRef", id)
        end)
        if ok and data then
            for _, line in ipairs(object_field_summary("getSpawnDataRef(" .. tostring(id) .. ")", data, 36)) do
                table.insert(lines, line)
            end
        elseif not ok then
            table.insert(lines, "getSpawnDataRef(" .. tostring(id) .. ") failed: " .. safe_string(err))
        end
    end

    if refs and refs.player then
        for _, line in ipairs(object_field_summary("PlayerContext", refs.player, 40)) do
            table.insert(lines, line)
        end
    end
    state.character_spawn_diagnostics = table.concat(lines, "\n")
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
    collect_prefab_hints(refs)
    collect_character_spawn_diagnostics(refs)
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
            prefab_hints = state.prefab_hints,
            prefab_hint_paths = state.prefab_hint_paths,
            character_spawn_status = state.character_spawn_status,
            character_spawn_diagnostics = state.character_spawn_diagnostics,
            last_spawn_components = state.last_spawn_components,
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

local function looks_like_grace_character(go)
    local summary = component_summary_for_go(go, 90)
    state.last_spawn_components = summary
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

    if go and not looks_like_grace_character(go) then
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
    path = tostring(path):gsub("\\", "/"):lower()

    local prefab = nil
    local ok, err = pcall(function()
        prefab = sdk.create_resource("via.Prefab", path)
    end)
    if not ok then return nil, safe_string(err) end
    if prefab and prefab.add_ref then
        pcall(function() prefab = prefab:add_ref() end)
    end
    if not prefab then return nil, "sdk.create_resource returned nil for " .. path end
    return prefab, path
end

local function try_spawn_prefab_object(prefab, label, refs)
    if not prefab then return false, "no prefab object" end
    local pose = get_spawn_pose(refs)
    local pos = make_vec3(pose.px or 0, pose.py or 0, pose.pz or 0)
    local rot = make_quat(pose.qx or 0, pose.qy or 0, pose.qz or 0, pose.qw or 1)
    local folder = get_spawn_folder(refs)
    local before = first_scene_transform()

    pcall(function() prefab:call("set_Standby", true) end)
    local calls = {
        { name = "instantiate(via.vec3, via.Quaternion, via.Folder)", args = { pos, rot, folder or 0 } },
        { name = "instantiate(via.vec3, via.Folder)", args = { pos, folder or 0 } },
        { name = "instantiate(via.vec3, via.Quaternion)", args = { pos, rot } },
        { name = "instantiate(via.vec3)", args = { pos } },
    }

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

    if #errors == 0 then
        return false, "no via.Prefab/path hints found on Grace yet"
    end
    return false, errors[1]
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
        state.puppet_status = "prefab failed: " .. safe_string(prefab_err) .. character_err .. " | clone method not found yet"
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
    local prefab_changed, prefab_value = imgui.input_text("Grace prefab path##re9mp_prefab", cfg.prefab_path or "")
    if prefab_changed then
        cfg.prefab_path = prefab_value
        save_cfg()
    end
    if state.prefab_hints ~= "" then
        imgui.text("Prefab hints dumped to runtime_diagnostics.json")
        local shown = 0
        for line in tostring(state.prefab_hints):gmatch("[^\n]+") do
            if shown >= 3 then break end
            imgui.text(line)
            shown = shown + 1
        end
    else
        imgui.text_colored("Prefab hints: none found yet", 0xFF8888FF)
    end
    if state.character_spawn_status ~= "" then
        imgui.text("CharacterManager: " .. safe_string(state.character_spawn_status))
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
    if imgui.button("Refresh Spawn Diagnostics") then
        dump_runtime_diagnostics()
    end
    if imgui.button("Probe CharacterManager Only") then try_character_manager_only() end
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
    update_local_dummy()
    if cfg.auto_runtime_diagnostics and state.local_ok then
        dump_runtime_diagnostics()
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
