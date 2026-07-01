# Lua Cleanup Plan

Last updated: 2026-07-01

`reframework/autorun/re9mp.lua` has grown into a combined runtime, lab notebook, trace harness, UI, network bridge, and spawn experiment runner. That was useful while reverse engineering, but it is now too large to reason about safely. Cleanup should preserve working evidence and failed paths, not delete them blindly.

## Objective

- Keep `reframework/autorun/re9mp.lua` as a small bootstrap/autorun entrypoint.
- Move active runtime code into named modules under `reframework/autorun/re9mp/`.
- Move old experiments into an explicit archive namespace so they are callable only when needed.
- Keep all live dev commands opt-in and reload-safe.

## Proposed Module Split

- `re9mp/state.lua`: config defaults, runtime state, data paths, JSON load/save helpers.
- `re9mp/native_bridge.lua`: native DLL status, lobby commands, network snapshot ingestion.
- `re9mp/player_refs.lua`: local player/context/transform detection and pose helpers.
- `re9mp/ui.lua`: REFramework ImGui overlay and HUD draw helpers.
- `re9mp/dev_commands.lua`: command dispatch, safety status, reset/despawn utilities.
- `re9mp/tracing/ownership_trace.lua`: level, bind, pool, spawn hook install/dump logic.
- `re9mp/tracing/probes.lua`: character/resource/component/object diagnostic probes.
- `re9mp/visual_clone.lua`: current visible `registered_player_material_lit` proof/control path.
- `re9mp/spawn/load_phase_injection.lua`: `PlayerContextIDHolder`, `setup_request_spawn`, and engine-owned context work.
- `re9mp/experiments/archive.lua`: negative-control branches kept for reference but hidden from normal command flow.

## Keep As Active

- Native networking status and snapshot flow.
- Local player reference sampling.
- `registered_player_material_lit` as the visible render/material control.
- `arm_load_phase_player_clone_injection setup_request_spawn` and the supporting ContextID holder helpers.
- Small focused trace dumps needed for the current engine-owned context path.

## Move To Archive

- Null detach, scene-folder detach, and owned-anchor detach variants.
- Plain independent MeshController attempts that produced 25/25 ready units but remained invisible.
- Broad prefab path probes that generated `[Missing file]` overlays.
- Older controller replay attempts that did not bind a new ContextID.
- Any dev command that is useful only to explain a past negative result.

## Cleanup Rules

- Do not change runtime behavior during the first split; move functions only.
- Keep command names stable until a replacement exists.
- Every archived branch needs a one-line reason and the date/result of the negative test.
- After each extraction, run `git diff --check`, deploy Lua, `Reset scripts`, and run `runtime_safety_status`.
- Do not delete old experiments until the archive module has been committed and the current path still works.

## Suggested Order

1. Extract generic helpers/state/path/config without behavior changes.
2. Extract tracing/probe code, because it is the largest non-MVP surface.
3. Extract visual clone code and keep only the current control path in normal command flow.
4. Extract load-phase injection code last, because it is the current active research path.
5. After the split, prune command dispatch so normal use shows only active commands and archived commands require an explicit archive prefix.
