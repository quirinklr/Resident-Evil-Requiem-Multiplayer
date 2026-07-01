-- State, config, snapshots, and remote pose helpers extracted from pre-split runtime lines 1-628.
-- Loaded by legacy_runtime.lua concatenation to preserve local scope.

-- RE9 Multiplayer MVP bridge.
-- Native plugin: UDP lobby/networking.
-- Lua bridge: RE9 player/scene sampling, overlay UI, and best-effort remote puppet.

local MOD_VERSION = "0.1.0"
local DATA_PREFIX = "re9mp/"
local CFG_FILE = DATA_PREFIX .. "config.json"
local COMMAND_FILE = DATA_PREFIX .. "command.json"
local DEV_COMMAND_FILE = DATA_PREFIX .. "dev_command.json"
local DEV_RESULT_FILE = DATA_PREFIX .. "dev_result.json"
local SPAWN_HOOK_FILE = DATA_PREFIX .. "spawn_hook_log.json"
local LEVEL_TRACE_FILE = DATA_PREFIX .. "level_load_trace.json"
local POOL_TRACE_FILE = DATA_PREFIX .. "pool_trace.json"
local BIND_TRACE_FILE = DATA_PREFIX .. "bind_trace.json"
local RESOURCE_PROBE_FILE = DATA_PREFIX .. "resource_probe.json"
local COMPONENT_RESOURCE_PROBE_FILE = DATA_PREFIX .. "component_resource_probe.json"
local VISUAL_COMPONENT_PROBE_FILE = DATA_PREFIX .. "visual_component_probe.json"
local VISUAL_SPAWN_PROBE_FILE = DATA_PREFIX .. "visual_spawn_probe.json"
local MESH_REGISTRATION_PROBE_FILE = DATA_PREFIX .. "mesh_registration_probe.json"
GRACE_OWNERSHIP_RECIPE_FILE = DATA_PREFIX .. "grace_ownership_recipe.json"
local LOCAL_FILE = DATA_PREFIX .. "local_snapshot.json"
local STATUS_FILE = DATA_PREFIX .. "status.json"
local REMOTE_FILE = DATA_PREFIX .. "remote_snapshot.json"

local cfg = {
    window_open = true,
    join_code = "",
    command_id = 0,
    auto_spawn_puppet = false,
    draw_remote_marker = true,
    local_dummy = false,
    dummy_offset_x = nil,
    dummy_offset_y = 0,
    dummy_offset_z = nil,
    visual_clone_mode = "shared_skeleton",
    prefab_path = "",
    auto_runtime_diagnostics = false,
    level_trace_enabled = false,
    controller_trace_enabled = false,
    pool_trace_enabled = false,
    bind_trace_enabled = false,
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
    last_dev_poll = 0,
    last_spawn_hook_dump = 0,
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
    puppet_anchor_go = nil,
    puppet_root_parented = false,
    puppet_local_hierarchy = false,
    puppet_independent_root = false,
    puppet_visual_units = {},
    puppet_status = "not spawned",
    puppet_last_attempt = 0,
    clone_candidates = "",
    scene_candidates = "",
    component_summary = "",
    method_signatures = "",
    player_fields = "",
    player_methods = "",
    prefab_hints = "",
    prefab_hint_paths = {},
    prefab_hint_objects = {},
    character_spawn_status = "",
    character_spawn_diagnostics = "",
    last_spawn_components = "",
    last_diagnostic_dump = 0,
    draw_status = "not drawn yet",
    dev_last_id = 0,
    dev_status = "",
    spawn_hook_attempted = false,
    spawn_hook_enabled = false,
    spawn_hook_status = "not installed",
    spawn_hook_events = {},
    spawn_hook_dirty = false,
    level_trace_enabled = false,
    level_trace_status = "waiting",
    level_trace_events = {},
    level_trace_dirty = false,
    level_trace_started_ms = 0,
    level_trace_last_dump = 0,
    level_trace_last_scene = "",
    pool_trace_enabled = false,
    pool_trace_status = "waiting",
    pool_trace_events = {},
    pool_trace_dirty = false,
    pool_trace_started_ms = 0,
    pool_trace_last_dump = 0,
    pool_trace_last_sample = 0,
    pool_trace_last_scene = "",
    pool_trace_last_signature = "",
    bind_trace_enabled = false,
    bind_trace_attempted = false,
    bind_trace_status = "waiting",
    bind_trace_events = {},
    bind_trace_errors = {},
    bind_trace_dirty = false,
    bind_trace_started_ms = 0,
    bind_trace_last_dump = 0,
    resource_probe_status = "",
    component_resource_status = "",
    visual_probe_status = "",
    character_object_probe = "",
    last_spawn_context = nil,
    last_spawn_context_text = "",
    pending_controller_restore = nil,
    load_phase_injection_armed = false,
    load_phase_injection_done = false,
    load_phase_injection_guard = false,
    load_phase_injection_mode = "",
    load_phase_injection_status = "",
    load_phase_injection_lines = {},
    load_phase_injection_context = nil,
    load_phase_injection_context_text = "",
    load_phase_injection_pending_control = nil,
    load_phase_injection_pending_setting = nil,
    load_phase_injection_pre_lines = {},
    load_phase_injection_followup_until = 0,
    load_phase_injection_next_dump = 0,
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

function read_local_position(xform)
    local pos = nil
    pcall(function() pos = xform:call("get_LocalPosition") end)
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

function quat_conjugate(q)
    return {
        x = -(q and q.x or 0),
        y = -(q and q.y or 0),
        z = -(q and q.z or 0),
        w = q and q.w or 1,
    }
end

function quat_multiply(a, b)
    a = a or { x = 0, y = 0, z = 0, w = 1 }
    b = b or { x = 0, y = 0, z = 0, w = 1 }
    return {
        x = ((a.w or 1) * (b.x or 0)) + ((a.x or 0) * (b.w or 1)) + ((a.y or 0) * (b.z or 0)) - ((a.z or 0) * (b.y or 0)),
        y = ((a.w or 1) * (b.y or 0)) - ((a.x or 0) * (b.z or 0)) + ((a.y or 0) * (b.w or 1)) + ((a.z or 0) * (b.x or 0)),
        z = ((a.w or 1) * (b.z or 0)) + ((a.x or 0) * (b.y or 0)) - ((a.y or 0) * (b.x or 0)) + ((a.z or 0) * (b.w or 1)),
        w = ((a.w or 1) * (b.w or 1)) - ((a.x or 0) * (b.x or 0)) - ((a.y or 0) * (b.y or 0)) - ((a.z or 0) * (b.z or 0)),
    }
end

function snapshot_rotation(snap)
    return {
        x = snap and snap.qx or 0,
        y = snap and snap.qy or 0,
        z = snap and snap.qz or 0,
        w = snap and snap.qw or 1,
    }
end

function pose_rotation(pose)
    return {
        x = pose and pose.qx or 0,
        y = pose and pose.qy or 0,
        z = pose and pose.qz or 0,
        w = pose and pose.qw or 1,
    }
end

function world_delta_to_local_yaw(snap, dx, dy, dz)
    local fx, fz = yaw_forward_from_snapshot(snap)
    local side_x, side_z = fz, -fx
    return {
        x = ((dx or 0) * side_x) + ((dz or 0) * side_z),
        y = dy or 0,
        z = ((dx or 0) * fx) + ((dz or 0) * fz),
    }
end

local function update_local_dummy()
    if not cfg.local_dummy then return end
    local snap = state.local_snapshot
    if not snap or not snap.valid then return end
    local t = now()
    if t < state.dummy_last_time + 0.033 then return end
    state.dummy_last_time = t
    state.dummy_seq = state.dummy_seq + 1

    local px, py, pz, vx, vz = nil, snap.py or 0, nil, 0, 0
    if cfg.dummy_offset_x ~= nil and cfg.dummy_offset_z ~= nil then
        px = (snap.px or 0) + (tonumber(cfg.dummy_offset_x) or 0)
        py = (snap.py or 0) + (tonumber(cfg.dummy_offset_y) or 0)
        pz = (snap.pz or 0) + (tonumber(cfg.dummy_offset_z) or 0)
    else
        local fx, fz = yaw_forward_from_snapshot(snap)
        local side_x, side_z = fz, -fx
        local distance = 2.4
        local sway = math.sin(t * 1.8) * 0.45
        px = (snap.px or 0) + (fx * distance) + (side_x * sway)
        pz = (snap.pz or 0) + (fz * distance) + (side_z * sway)
        vx = (side_x * math.cos(t * 1.8) * 0.81)
        vz = (side_z * math.cos(t * 1.8) * 0.81)
    end
    local dummy = {
        valid = true,
        seq = state.dummy_seq,
        scene = snap.scene,
        px = px,
        py = py,
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

function set_static_dummy_ahead(distance)
    local snap = state.local_snapshot
    if not snap or not snap.valid then
        snap = make_local_snapshot()
    end
    if not snap or not snap.valid then
        return false, "static dummy failed: no local snapshot"
    end

    local fx, fz = yaw_forward_from_snapshot(snap)
    local d = tonumber(distance) or 2.4
    state.dummy_seq = state.dummy_seq + 1
    local t = now()
    local dummy = {
        valid = true,
        seq = state.dummy_seq,
        scene = snap.scene,
        px = (snap.px or 0) + (fx * d),
        py = snap.py or 0,
        pz = (snap.pz or 0) + (fz * d),
        qx = 0,
        qy = snap.qy or 0,
        qz = 0,
        qw = snap.qw or 1,
        vx = 0,
        vy = 0,
        vz = 0,
        flags = 1,
        motion = "static_dummy",
        stance = "static_dummy",
    }
    state.remote_samples = { { t = t, data = dummy } }
    state.remote_last_seq = nil
    cfg.local_dummy = false
    save_cfg()
    return true, string.format("static_dummy=true ahead=%.1fm", d)
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
