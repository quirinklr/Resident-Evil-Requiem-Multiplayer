# Lua Cleanup Plan

Last updated: 2026-07-01

`reframework/autorun/re9mp.lua` had grown into a combined runtime, lab notebook, trace harness, UI, network bridge, and spawn experiment runner. The first cleanup pass moved that monolith behind a small bootstrap and created the module folder layout. Cleanup should continue by extracting active subsystems out of `legacy_runtime.lua`, while preserving working evidence and failed paths.

## Objective

- Keep `reframework/autorun/re9mp.lua` as a small bootstrap/autorun entrypoint.
- Move active runtime code into named modules under `reframework/autorun/re9mp/`.
- Move old experiments into an explicit archive namespace so they are not reachable from normal commands.
- Keep all live dev commands opt-in and reload-safe.

## Current Implementation

- `reframework/autorun/re9mp.lua` is now a bootstrap that loads `re9mp/init.lua` and writes `bootstrap_error.json` on failure.
- `reframework/autorun/re9mp/init.lua` loads `legacy_runtime.lua` while extraction continues.
- `legacy_runtime.lua` now concatenates thematic chunks from `core/`, `runtime/`, `spawn/`, `tracing/`, and `archive/` so the old local scope still works without keeping one huge file.
- `scripts/deploy.ps1` deploys the bootstrap and the full Lua module folder.
- Normal visual clone commands now keep only `registered_player_material_lit` active.
- Old detach, independent controller, direct requestSpawn, controller replay, prefab, and resource probe commands return archived/disabled messages from the normal dispatcher and no longer appear as normal UI buttons.

## Proposed Module Split

- `core/`: config defaults, runtime state, data paths, JSON load/save helpers, value helpers.
- `runtime/`: native DLL status, lobby commands, network snapshot ingestion, local refs, UI, active command dispatch.
- `tracing/`: level, bind, pool, spawn hook install/dump logic and focused probes.
- `spawn/`: current visible `registered_player_material_lit` proof/control path plus `PlayerContextIDHolder`/`setup_request_spawn`.
- `archive/`: negative-control branches kept for reference but hidden from normal command flow.

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
- Keep `legacy_runtime.lua` loadable until a subsystem has been extracted and verified.

## Suggested Order

1. Convert `core/legacy_00_state_and_snapshots.lua` from concatenated chunk to a real returned module.
2. Extract active dev-command dispatch from `runtime/legacy_80_commands_ui_callbacks.lua` into `runtime/commands.lua`, keeping archived commands disabled.
3. Convert focused trace/probe chunks into returned modules with explicit dependencies.
4. Convert `registered_player_material_lit` and `setup_request_spawn` chunks into `spawn/` modules.
5. Move negative-control functions from archive chunks into documented archive modules or delete them only after their result is documented in RE memory.
