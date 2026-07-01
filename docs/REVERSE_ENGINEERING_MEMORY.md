# RE9MP Reverse Engineering Memory

Last updated: 2026-07-01

This file is the project memory for RE9 Requiem multiplayer reverse engineering. Keep hard facts separate from hypotheses. Do not delete failed paths unless a newer fact supersedes them.

## Current Goal

- MVP target: two players in the same `Chap1_01` start area, both visible as Grace, with position/rotation/basic locomotion synchronized.
- Networking is not the current blocker. Host/client UDP over Tailscale worked and remote movement snapshots arrived.
- Current blocker: creating a visible second Grace in the RE Engine scene.

## Local Environment Facts

- RE9 install path: `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem`
- Steam AppID: `3764200`
- BuildID: `23634047`
- `re9.exe` version: `1.3.1.0`
- REFramework overlay is loaded and `reframework/autorun/re9mp.lua` is active.
- Latest pushed repo commit before this memory file: `56fbd37 Add targeted character pool trace`
- Current Lua bridge is deployed by copying `reframework/autorun/re9mp.lua` into the game install. Lua changes require REFramework `Reset scripts` or a RE9 restart.

## Working Runtime Facts

- `get_current_scene()` detects `Chap1_01` in the loaded gameplay area.
- `get_local_player_refs()` detects the local player in gameplay.
- Local player detection uses `app.CharacterManager:get_PlayerContextFast`, then `get_GameObject()` and `get_Transform()`.
- Host lobby successfully showed a join code in this format: `100.71.129.63:27777:<token>`.
- Client was able to connect from Niklas over Tailscale.
- Host received remote movement packets and computed remote relative direction/distance.
- Remote marker fallback proved that remote pose math works, but it is only a HUD/debug marker, not a world character.

## Network Facts

- Host UDP port: `27777`.
- Tailscale IP observed for Quirin/host: `100.71.129.63`.
- Tailscale IP observed for Niklas/client: `100.71.5.66` during successful in-game connection.
- Successful client status showed scene `Chap1_01`, build `23634047`, `re9.exe 1.3.1.0`, and ping around 20 ms.
- Packet counters advanced on both sides during movement, so the native networking path is functional for the MVP.

## Confirmed Real Player Load Sequence

Captured from level-load trace when entering gameplay:

- `registerSpawnGroup(app.ICharacterSpawnControl)` was called with `app.LevelPlayerCreateController`.
- The controller GameObject was named like `[LevelPlayerCreateController@bf520d7f-b15c-4689-8c36-859f7b1651f3]`.
- `readyContext(... cp_A100 ...)` was called for real Grace.
- Real player ContextID observed: `aefea84b-14da-4990-a9ff-9ca434a350d2`.
- `restoreContext(ctx, app.PlayerContext)` happened after `readyContext`.
- `registerSpawnData(app.PlayerSpawnData)` happened after `restoreContext`.
- `onChangeActivePlayer` happened after spawn-data registration.

## Character Pool Facts

- Character pool count in `Chap1_01`: `33`.
- PlayerContext count before extra probes: `1`.
- Pool index `0` is the real local Grace:
  - updater type: `app.Cp_A100Updater`
  - `used=true`
  - `finalized=true`
  - updater has valid GameObject and Transform
  - updater context is the local `app.PlayerContext`
- Other pool entries observed are non-player character updaters such as `app.Cp_E010Updater`.
- No second free `app.Cp_A100Updater` pool entry has been observed.

## Failed CharacterManager Spawn Facts

The `spawn_load_order_grace` probe tried to mimic the real load order:

- Created a new `app.ContextID`: `752faf6a-94f9-4571-91b7-6a30d2960ca3`.
- Duplicated `app.PlayerSpawnData`.
- Set duplicated spawn data fields:
  - `ContextID`
  - `CharacterKindID`
  - `ResumeType=1`
  - `IsForceTransform=true`
  - `IsFirstSpawn=true`
  - `SpawnControl`
  - `Position`
  - `Rotation`
- Patched controller fields:
  - `_SpawnContextID`
  - `IsSpawnRequestEnd=false`
  - `<HasPermittedSpawn>k__BackingField=false`
  - `_InitStateSuspended=false`
- Calls that returned without Lua-level failure:
  - `registerSpawnGroup(app.ICharacterSpawnControl)`
  - `readyContext(app.ContextID, app.CharacterKindID, System.Func<app.CharacterContext>)`
  - `registerSpawnData(app.CharacterSpawnData)`
  - `setupControlCharacter(app.LevelPlayerCreateController.CreateSetting)`
  - `setupCommonMessageKind(...)`
  - `app.ICharacterSpawnControl.requestSpawn()`
  - `app.ICharacterSpawnControl.requestResume(System.Int32)`
  - `createControlCharacter()`
- `restoreContext(app.ContextID, app.CharacterContext)` returned `false`.
- Result: the new context still had no `GameObject` and no `Updater`.
- After this probe, PlayerContext count became `2`, but PlayerContext[1] still had no GameObject/updater.
- Conclusion from facts: duplicating PlayerContext/spawn data alone is insufficient because the pool does not allocate a second A100 updater.

## Prefab And Asset Facts

- RE9 asset list exists at `.tools/REE.PAK.Tool-src/Projects/RE9_STM_Release.list`.
- Asset list size observed: `14681714` bytes.
- Search found `539` `ch0100` prefab entries.
- `ch0100` appears to be the Grace/player character asset family.
- Confirmed prefab paths from the asset list include:
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_000.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_001.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_003.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_004.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_005.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_006.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_007.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_008.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_009.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_010.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_011.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_012.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_013.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_014.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_015.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_016.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_017.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_018.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_019.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_020.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_100.pfb.18`
  - `natives/stm/character/ch/ch01/0100/01/ch0100_01_102.pfb.18`
- `ch0100` motion resources exist, including:
  - `natives/stm/animation/ch/ch01/ch0100/motbank/ch0100.motbank.4`
  - `natives/stm/animation/ch/ch01/ch0100/motbank/ch0100fps.motbank.4`
  - many `ch0100_generald_*walk*` motiondata user files
- The live `via.motion.Motion` component on the local player reported active resources under `ch0200`, not only `ch0100`:
  - `Resource[Animation/ch/ch02/ch0200/motbank/ch0200.motbank]`
  - `Resource[Animation/ch/ch02/ch0200/cambank/ch0200.mcambank]`
- The `ch0200` asset family includes many locomotion resources such as:
  - `natives/stm/animation/ch/ch02/ch0200/motbank/ch0200.motbank.4`
  - `natives/stm/animation/ch/ch02/ch0200/motbank/ch0200fps.motbank.4`
  - `natives/stm/animation/ch/ch02/ch0200/motbank/motiondata/ch0200_generald/ch0200_generald_0000_idle_caution.user.3`
  - `natives/stm/animation/ch/ch02/ch0200/motbank/motiondata/ch0200_generald/ch0200_generald_2270_walk_loop.user.3`
- Confirmed Grace mesh/material resource paths include:
  - `natives/stm/character/ch/ch01/0100/01/00/ch0100_01_00.mesh.250925211`
  - `natives/stm/character/ch/ch01/0100/01/00/ch0100_01_00_00.mdf2.51`
  - `natives/stm/character/ch/ch01/0100/01/01/ch0100_01_01.mesh.250925211`
  - `natives/stm/character/ch/ch01/0100/01/01/ch0100_01_01_00.mdf2.51`

## Current Lua Diagnostics

- Main Lua file: `reframework/autorun/re9mp.lua`.
- Runtime output folder in game install: `reframework/data/re9mp/`.
- Important runtime files:
  - `status.json`
  - `local_snapshot.json`
  - `remote_snapshot.json`
  - `dev_command.json`
  - `dev_result.json`
  - `runtime_diagnostics.json`
  - `spawn_hook_log.json`
  - `level_load_trace.json`
  - `pool_trace.json`
  - `bind_trace.json`
  - `resource_probe.json`
  - `load_order_spawn_probe.json`
  - `component_resource_probe.json`
  - `visual_component_probe.json`
- Safe dev command mechanism already exists through `dev_command.json`.
- Existing useful dev actions include:
  - `spawn_load_order_grace`
  - `resource_probe`
  - `component_resource_probe`
  - `visual_component_probe`
  - `start_bind_trace`
  - `stop_bind_trace`
  - `dump_bind_trace`

## Visual Mesh Facts

- `visual_component_probe` ran successfully in `Chap1_01`.
- The real local Grace has `PlayerMeshController.MeshUnitDictionary` with `14` entries.
- Each observed `app.MeshUnit` exposes:
  - `via.GameObject <GameObject>k__BackingField`
  - `via.render.Mesh <Mesh>k__BackingField`
  - `app.MeshController <ParentMeshController>k__BackingField`
  - `app.MeshController <MeshController>k__BackingField`
  - `via.render.Strands[] <Strands>k__BackingField`
  - `app.MeshUnit.Type <MeshType>k__BackingField`
  - `app.NameHash <Name>k__BackingField`
- `app.MeshUnit` exposes useful methods:
  - `get_GameObject()`
  - `get_Mesh()`
  - `setDrawAndUpdate(System.Boolean, System.Boolean)`
  - `setDrawDefault(System.Boolean, System.String)`
  - `setDrawShadow(System.Boolean, System.String)`
  - `changeMeshType(app.MeshUnit.Type)`
- `PlayerMeshController.MeshList` reported count `0`, while `MeshUnitDictionary` contained the live meshes. Use `MeshUnitDictionary`, not `_MeshList`, as the next visual clone source.
- Current inference: the local visible-clone path should focus on cloning/instancing MeshUnit GameObjects or building a visual-only object from those mesh units. Do not continue trying to allocate a second `Cp_A100Updater` unless new evidence appears.

## Inferences To Verify

These are not facts yet:

- The fastest path is likely a visual-only Grace clone/prefab instance rather than another full player-controlled `app.PlayerContext`.
- `via.Prefab` loading may require exact `natives/stm/...pfb.18` paths or a different resource type than current `sdk.create_resource("via.Prefab", path)` attempts.
- If direct prefab instantiate fails, the next target should be the local Grace GameObject/components for resource handles, mesh controllers, motion banks, and loaded prefab references.
- A usable MVP may start with a visual-only Grace puppet with disabled collision/input/AI, then add animation from velocity/motion state.

## Immediate Next Steps

- Do not repeat broad CharacterManager spawn probes unless a new fact changes the pool/updater picture.
- Add a targeted resource/prefab probe using the exact `natives/stm/character/ch/ch01/0100/...pfb.18` paths.
- Add a component-resource dump for the real local Grace, focused on mesh/prefab/motion/resource fields and zero-argument getters.
- Component/resource probes must only call `get_*` methods. A previous version accidentally called `via.motion.Motion:setupMotionBank()` and `via.motion.ActorMotion:clearResource()`, which disturbed the current player's animation pose until RE9/reload restored it.
- Use `visual_component_probe` to inspect the real local player's `PlayerMeshController`, `ActorPlayerMeshController`, `MeshUnitDictionary`, `_MeshList`, and related `via.render.Mesh`/`app.MeshUnit` objects.
- Use small JSON outputs only; avoid broad UI dumps that can freeze RE9.
- After Lua changes, deploy `reframework/autorun/re9mp.lua`, then user must use `Reset scripts` or restart RE9 for the new code to load.
