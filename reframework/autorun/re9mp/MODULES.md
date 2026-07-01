# RE9MP Lua Module Layout

This folder is the new home for RE9MP Lua runtime code.

Current migration status:

- `../re9mp.lua` is a generated runtime bundle built by `scripts/build_lua_bundle.ps1`.
- `init.lua` and `legacy_runtime.lua` are transitional loader references, not the active REFramework autorun path.
- The generated bundle concatenates the extracted legacy chunks and executes them as one Lua chunk, preserving old top-level `local` scope.
- `core/`, `runtime/`, `spawn/`, `tracing/`, and `archive/` are the target folders for the cleanup.

Extraction rule:

- Move one subsystem at a time out of the legacy chunks.
- Rebuild `../re9mp.lua` with `scripts/build_lua_bundle.ps1` after chunk edits.
- Keep active commands reload-safe after every extraction.
- Archive negative experiments instead of leaving them in normal command flow.

Current chunk map:

- `core/legacy_00_state_and_snapshots.lua`: config, state, local/remote snapshots.
- `tracing/legacy_10_trace_hooks.lua`: hook installation and trace dumping.
- `tracing/legacy_20_diagnostics_helpers.lua`: object/field/method diagnostic helpers.
- `tracing/legacy_21_character_and_visual_probes.lua`: focused character, component, visual, and mesh probes.
- `spawn/legacy_30_context_and_controller_helpers.lua`: ContextID and controller helper paths.
- `spawn/legacy_40_load_phase_injection.lua`: active engine-owned load-phase injection path.
- `spawn/legacy_50_visual_foundation.lua`: visual clone scene/GameObject helpers.
- `spawn/legacy_51_mesh_copy_and_registration.lua`: mesh/material copy and MeshUnit registration.
- `spawn/legacy_52_lit_control_clone.lua`: visible lit Grace control clone.
- `tracing/legacy_60_ownership_recipe.lua`: Grace ownership recipe traces.
- `archive/legacy_70_archived_prefab_and_spawn_probes.lua`: historical prefab/direct-spawn probes.
- `runtime/legacy_80_commands_ui_callbacks.lua`: command dispatch, UI, callbacks.
