# RE9MP Reverse Engineering Memory

Last updated: 2026-07-01

This file is the project memory for RE9 Requiem multiplayer reverse engineering. Keep hard facts separate from hypotheses. Do not delete failed paths unless a newer fact supersedes them.

## Current Goal

- MVP target: two players in the same `Chap1_01` start area, both visible as Grace, with position/rotation/basic locomotion synchronized.
- Networking is not the current blocker. Host/client UDP over Tailscale worked and remote movement snapshots arrived.
- Current blocker: keeping the now-visible second Grace controllable from remote snapshots instead of relying on local parented movement.

## Local Environment Facts

- RE9 install path: `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem`
- Steam AppID: `3764200`
- BuildID: `23634047`
- `re9.exe` version: `1.3.1.0`
- REFramework overlay is loaded and `reframework/autorun/re9mp.lua` is active as a generated single-file runtime bundle.
- Runtime source chunks live in `reframework/autorun/re9mp/` while cleanup extraction continues.
- Latest pushed repo commit before this memory file: `56fbd37 Add targeted character pool trace`
- Current Lua bridge is deployed by rebuilding `reframework/autorun/re9mp.lua` from chunks, then copying it and the `reframework/autorun/re9mp/` source folder into the game install. Lua changes require REFramework `Reset scripts` or a RE9 restart.

## Working Runtime Facts

- `get_current_scene()` detects `Chap1_01` in the loaded gameplay area.
- `get_local_player_refs()` detects the local player in gameplay.
- Local player detection uses `app.CharacterManager:get_PlayerContextFast`, then `get_GameObject()` and `get_Transform()`.
- Host lobby successfully showed a join code in this format: `100.71.129.63:27777:<token>`.
- Client was able to connect from Niklas over Tailscale.
- Host received remote movement packets and computed remote relative direction/distance.
- Remote marker fallback proved that remote pose math works, but it is only a HUD/debug marker, not a world character.

## Current Visible Clone Status

- Works now:
  - `registered_player_material_lit` is the first visually acceptable Grace clone path.
  - It creates 25/25 visible mesh units, registers them through `PlayerMeshController:registerMeshUnit(...)`, copies safe material holders/names, and uses lit/depth-respecting render flags.
  - Runtime readback confirmed `ignore_depth=false`, `draw_shadow=true`, `occlusion_culling=true`, `frustum_culling=true`, `meshReady=25`, `matReady=25`, and stable RE9 process behavior after the spawn.
  - User screenshots confirmed the clone now looks graphically correct rather than like a debug/wallhack object.
- Why it appears to work:
  - The successful path combines parent hierarchy under the live local Grace, MeshUnit registration on the live `PlayerMeshController`, and safe material copying.
  - That combination likely gives cloned meshes the render/ownership context missing from earlier free `via.GameObject` holder-copy attempts.
  - Unsafe calls are intentionally avoided: no `getMaterialTexture`, no `set_SharedSkeletonGameObject`, no `notifyMeshUnitChanged`, and no `set_MaterialParamCount`.
- Known problems:
  - The clone has no locomotion animation; it is a static mesh pose assembled from live mesh units.
  - It still depends on the local Grace parent hierarchy. This makes it visible, but it is not a clean independent remote character.
  - Static dummy tests show it can visually hold a remote position when the player is still, but it glitches when local yaw/pitch/movement changes because local parent rotation fights the clone's world/remote transform updates.
- Wanted architecture:
  - A remote Grace should be its own scene-root or character-cluster, not a child of the local Grace.
  - Its transform should be driven directly from remote network snapshots, with animation selected from remote motion/velocity state.
  - Local Grace movement and camera yaw/pitch should not affect the remote clone except through normal scene/camera rendering.
- Next technical direction:
  - Stop optimizing parent-compensation as the long-term solution.
  - Use the current parented path as a bootstrap proof that mesh registration/material/render flags are valid.
  - Do not spend more runtime passes on null-detach, scene-folder detach, owned-anchor detach, or local-parent compensation. Those paths keep objects/registrations alive but lose the visible render/ownership context or keep the yaw/pitch dependency.
  - The Main Menu -> gameplay load trace has now identified the real ownership path. The next branch is no longer more parent/detach work; it is a load-phase replay/injection of the smallest missing `PlayerContext`/`Cp_A100Updater` ownership context.
  - Runtime result: `registered_player_material_lit_detach` / `spawn_visual_mesh_clone_registered_material_lit_detach` successfully created 25/25 units, registered 25/25, kept material/mesh ready 25/25, and `setParent(nil,true)` returned success after registration. RE9 stayed responsive, but user visual testing could not find the detached clone. This strongly suggests null-detach breaks the render/ownership context even though the objects still exist.
  - Control result at the same test area: `registered_player_material_lit` remained visible in front of the car and looked correct, but still glitched with local yaw/pitch/location because it is local-player-parented.
  - Implemented and tested: `registered_player_material_lit_scene_detach` / `spawn_visual_mesh_clone_registered_material_lit_scene_detach`. It first creates the known-good parented/registered/lit clone, then creates its own invisible `RE9MP Remote Grace Scene Anchor` in the scene folder, reparents the root under that owned anchor instead of `nil`, restores child local offsets under that root, and lets `apply_remote_pose()` drive the root directly from remote snapshots.
  - The first attempted scene-detach run after this change still used the old loaded runtime and selected `effect_cp_E010_14`; it did not prove the owned-anchor variant. Use `registered_player_material_lit_owned_anchor_detach` as the unambiguous reload/test mode for the owned-anchor path.
  - Runtime result for `registered_player_material_lit_owned_anchor_detach`: new mode was accepted after reload, created its own `RE9MP Remote Grace Scene Anchor` via static folder, created 25/25 mesh units, registered 25/25, kept mesh/material ready 25/25, preserved lit/depth flags, and reparented the root under the owned anchor successfully. RE9 stayed responsive after the test, but user visual testing confirmed Grace was not visible. Conclusion: both null detach and owned scene-folder detach keep the objects alive but lose the visible render/ownership context supplied by the local player parent.
  - Decision after detach tests: do not spend more time on parent-compensation or more plain scene reparenting variants. The next branch must build or borrow a proper independent render ownership context: own `MeshController`/`CharacterMeshController` cluster, or a real prefab/character-spawn instance that comes with the engine's expected ownership setup.
  - Trace result after the first `start_grace_ownership_trace` + in-level scene reload pass: `level_load_trace.json` contained only `registerSpawnData`, `storeContext`, and `unregisterSpawnData` events; `bind_trace.json` contained 1372 mesh bind events but 0 hits for `cp_A100`. This pass did not capture the real Grace build path and should not be repeated as-is.
  - A later trace started while already in gameplay was flooded by hot getter calls (`getPlayerContextRef`, `getContextRef`, `getSpawnDataRef`) and did not represent the build sequence. Those getter hooks were removed from the normal trace set.
  - The useful trace pass starts in the Main Menu before loading the save/level and stops only after Grace is controllable in `Chap1_01`; this is the pass captured at 2026-07-01 16:06 CEST.
  - Main Menu -> `Chap1_01` gameplay-load trace captured the useful path:
    - `getCharacterContextFactory(cp_A100)`
    - `readyContext(aefea84b-14da-4990-a9ff-9ca434a350d2, cp_A100, factory, false)`
    - `restoreContext(ctx, app.PlayerContext)`
    - `LevelPlayerCreateController:setupControlCharacter(CreateSetting)`
    - second `readyContext/restoreContext` for the player context during setup
    - `LevelPlayerCreateController:setupCommonMessageKind(CreateSetting, PlayerContext)`
    - `registerSpawnData(app.PlayerSpawnData)`
    - `LevelPlayerCreateController:createControlCharacter()`
    - about 833 ms later, `app.PlayerMeshController` on `cp_A100` ran `searchInitMeshUnits()` and registered the visible mesh units.
  - The real `CreateSetting` used `_ControlCharaIdCache=cp_A100`, `_MontageModelID=200`, `_MontagePresetID=4`, `_AfterFFMontageModelID=200`, `_AfterFFMontagePresetID=1`, `_MessageGroup=true`, and `_StartPoseStartPoseGroup=true`.
  - First traced player mesh registration: controller `app.PlayerMeshController` on GameObject `cp_A100`, dictionary count `0`, mesh `cp_A1_Bag_Exclusive`, mesh type `0`.
  - MeshController-only branches are now negative controls, not target architecture. `registered_own_player_controller_lit` was initially believed to be independent, but later review showed that mode still inherited the parented material path. Corrected independent variants (`registered_own_player_controller_independent_lit` and `registered_player_controller_independent_lit`) both produced 25/25 ready mesh units but were not visible to the user. Conclusion: neither an owned standalone `PlayerMeshController` nor local `PlayerMeshController` registration without the local Grace hierarchy is enough.
  - New implementation branch after that failure: `spawn_trace_order_controller_grace` follows the captured `LevelPlayerCreateController` order more closely. It sets `_SpawnContextID` to a new ContextID, keeps `IsSpawnRequestEnd=false`, `<HasPermittedSpawn>=false`, `_InitStateSuspended=false`, registers the spawn group, calls `setupControlCharacter(setting)`, then `setupCommonMessageKind(setting, context)` and `createControlCharacter()`. Unlike the old load-order probe, it does not pre-call `readyContext`/`registerSpawnData` and does not restore controller fields immediately.
  - Runtime result for `spawn_trace_order_controller_grace`: `setupControlCharacter(...)` and `createControlCharacter()` returned without Lua-level failure, but `CharacterManager:getContextRef(new ContextID)` stayed nil before and after create; no GameObject, PlayerContext, or updater was allocated. Conclusion: replaying the level-load controller calls during normal gameplay is not enough; those calls likely depend on the real chapter-init/load state.
  - Main Menu -> gameplay blackbox trace result at 2026-07-01 16:06 CEST: `level_load_trace.json` captured 380 events, `bind_trace.json` 1176 events, `pool_trace.json` 195 events, `spawn_hook_log.json` 217 events, and `grace_ownership_recipe.json` dumped 25 mesh units. The real local Grace path is now confirmed as `readyContext(cp_A100) -> restoreContext(PlayerContext) -> PlayerSpawnData -> createControlCharacter() -> Cp_A100Updater pool index 0 -> PlayerMeshController mesh registration`.
  - Current strongest inference: the independent remote Grace must be created during, or by faithfully reproducing, the engine-owned PlayerContext/Cp_A100Updater/CharacterPool path. More detached mesh roots or parent compensation are out of scope unless this engine-owned path is proven impossible.
  - Implementation added after the blackbox trace: `arm_load_phase_player_clone_injection` arms a one-shot hook for the next Main Menu -> gameplay load. It captures the real `LevelPlayerCreateController:setupControlCharacter(...)` call, then post-call attempts a second `cp_A100` setup/common/create sequence with a fresh `ContextID` while the real chapter-init/load state is active. It writes `load_phase_injection_probe.json` and polls for Context/GameObject/Updater/Pool evidence for 8 seconds after injection.
  - First `arm_load_phase_player_clone_injection setup_create` runtime pass reached the correct timing window: the injection ran directly after real `setupControlCharacter` and before real `createControlCharacter`. The result `triggered; no context=7383233d-6ed4-4ad8-8cac-016be718ac50` is not valid engine evidence because hook args were stored as raw userdata; calls failed with `attempt to index a userdata value`. Fix applied: convert captured hook args with `sdk.to_managed_object(...)` before storing controller/setting, then repeat the same Main Menu -> gameplay test.
  - Corrected `arm_load_phase_player_clone_injection setup_create` pass at 2026-07-01 16:45 CEST: captured controller/setting were valid managed objects, `registerSpawnGroup(...)`, injected `setupControlCharacter(...)`, and injected `createControlCharacter()` all returned ok. This produced `player_contexts=2` and `context_db=54`, but `getContextRef(new ContextID)` stayed nil and the second `app.PlayerContext` had no GameObject, no Transform, and no updater. Inference: controller setup can create an extra PlayerContext object, but the missing step is binding that context to the requested ContextID and/or allocating/finalizing a `Cp_A100Updater`/CharacterPool GameObject.
  - Follow-up implementation: keep `_ControlCharaId="cp_A100"` instead of accidentally blanking it with a `CharacterKindID` object; keep `_ControlCharaIdCache=cp_A100`; if `getContextRef(new ContextID)` is nil after injected setup, pick the newest inactive PlayerContext without GameObject/updater from `PlayerContextList` and pass it to `setupCommonMessageKind(...)` before `createControlCharacter()`.
  - `resource_probe` produced visible in-game `[Missing file]` overlay messages for guessed `ch0100_01_*.pfb` path variants. Treat this as a negative test for the current `sdk.create_resource("via.Prefab", guessed_path)` approach. Do not repeat the broad prefab probe during normal testing; it is noisy and did not produce a usable resource.
  - New implementation branch: `raw_gameobject_clone_probe` bypasses the visual mesh clone path and directly tests no-arg clone/copy/duplicate/instantiate methods on the real local `cp_A100` GameObject. This exists because the old `spawn_puppet` path reaches the successful visual mesh clone first and therefore hides whether RE Engine exposes a usable full-GameObject clone path.

## Current Engine-Owned Context Status

- The `PlayerContextIDHolder` path is now understood better than before:
  - `LevelPlayerCreateController:getAllManagedContextID()` is derived from `CharacterManager.<PlayerContextIDHolder>k__BackingField`, not a durable source to mutate directly.
  - A fresh `app.ContextIDReserverWithEnumeration<app.CharacterKindID>` can be constructed and placed in a managed array with `sdk.create_managed_array(...)`, but registering a second holder for the same `cp_A100` does not override the already-active mapping.
  - Mutating the existing `cp_A100` holder works only if `_RawContextID` is followed by restoring `_BindTarget="cp_A100"` and `_Cache=CharacterKindID.cp_A100`; otherwise `get_BindTarget()` and `getPlayerContextID(cp_A100)` go empty.
- Latest successful load-phase result:
  - `arm_load_phase_player_clone_injection setup_create` during Main Menu -> `Chap1_01` produced a new ContextID `07eab937-e620-4e59-a5e8-c00193692622`.
  - `getPlayerContextID(cp_A100)` temporarily returned that new ID.
  - The trace captured `readyContext(new, cp_A100, factory, false)` and `restoreContext(new, app.PlayerContext)`.
  - After `createControlCharacter()`, `CharacterManager:isUsedContext(new)` became `true`, `getContextRef(new)` returned `app.PlayerContext`, and later probing showed a valid GameObject, Transform, `app.Cp_A100Updater`, and `PlayerSpawnData`.
- Critical caveat:
  - The `setup_create` branch is not the final architecture because `createControlCharacter()` follows the local control-character path. It eventually triggered `onChangeActivePlayer(empty -> new)` and effectively made the injected context the active local player mapping.
  - This proves the engine-owned context path is reachable, but it is not yet a safe independent remote-character spawn.
- Current next branch:
  - `setup_request_spawn` now runs `setupControlCharacter(...)` to create/register the new context, then calls `CharacterManager:requestSpawn(new, cp_A100, MontageID.Invalid, 0, false, Default)` instead of `createControlCharacter()`.
  - The purpose is to test whether the engine can allocate/finalize a visible `Cp_A100Updater`/GameObject for the new context without hijacking `onChangeActivePlayer`.
  - If `setup_request_spawn` still hijacks or stays invisible, the next target is the pool/updater allocation boundary, not more mesh-parent compensation.

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
- `component_resource_probe` found live local Grace resource references that are more reliable than guessed prefab paths:
  - `Animation/ch/ch02/ch0200/motbank/ch0200.motbank`
  - `AppSystem/Character/CharacterPrefab/PlayerCommon/UserData/PlayerFPSMotionTransitionSettings.user`
  - `AppSystem/Character/CharacterPrefab/PlayerCommon/UserVariables/PlayerCommonMotionUserVariables.uvar`
  - `GameAssets/Character/CharacterPrefab/cp_A1/cp_A100/JointMap/cp_A1JointMap.jmap`
  - `Config/Physics/Filter/CharacterPlayer.cfil`
  - `VFX/Texture/RenderTargetTexture/RTT_character/record_named/RTT_cp_A100.rtex`
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

- Main Lua runtime bundle: `reframework/autorun/re9mp.lua`.
- Current Lua source chunks: `reframework/autorun/re9mp/`.
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
  - `visual_spawn_probe.json`
  - `grace_ownership_recipe.json`
- Safe dev command mechanism already exists through `dev_command.json`.
- Existing useful dev actions include:
  - `spawn_load_order_grace`
  - `spawn_visual_mesh_clone`
  - `spawn_visual_mesh_clone_registered_material`
  - `spawn_visual_mesh_clone_registered_child_material`
  - `spawn_visual_mesh_clone_registered_own_player_controller_lit`
  - `spawn_trace_order_controller_grace`
  - `raw_gameobject_clone_probe`
  - `resource_probe`
  - `component_resource_probe`
  - `visual_component_probe`
  - `start_bind_trace`
  - `stop_bind_trace`
  - `dump_bind_trace`
  - `start_grace_ownership_trace`
  - `stop_grace_ownership_trace`
  - `start_join_ownership_trace` (despite the historic name, this is now used for Main Menu -> gameplay load tracing, not network join)
  - `stop_join_ownership_trace`
  - `dump_grace_ownership_recipe`

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
- Superseded inference: the earlier "do not try a second `Cp_A100Updater`" note is no longer valid. The 2026-07-01 Main Menu -> gameplay trace showed that the visible real Grace is specifically tied to `PlayerContext` + `Cp_A100Updater` + CharacterPool ownership; this is now the path to test, while mesh-only branches remain control/negative evidence.
- Code added at 2026-07-01 08:54 CEST: `spawn_visual_mesh_clone` creates a visual-only puppet root and one `via.GameObject` per live `app.MeshUnit`, adds a `via.render.Mesh` component, copies the source mesh holder via `getMesh()`, copies `get_Material()`, copies several draw/skeleton flags, stores per-mesh world offsets, and writes `visual_spawn_probe.json`.
- This code is not yet validated in-game. The updated Lua was copied into the RE9 install, but the currently running REFramework session still had the old script loaded and returned `unknown or disabled dev action: spawn_visual_mesh_clone`.
- Runtime result at 2026-07-01 08:56 CEST after REFramework reload:
  - `spawn_visual_mesh_clone` returned `ok=true`.
  - `dev_result.json` message: `visual mesh clone spawned units=25`.
  - `visual_spawn_probe.json` reported `source_mesh_units=25` and `created_units=25`.
  - Each clone row reported `clone_create="static folder"`, `clone_mesh_component="createComponent(System.Type)"`, `source_mesh_type="via.render.Mesh"`, and `ok=true`.
  - `set_dummy=true` returned `ok=true`; a later `status` dev command reported `remote_samples=12`, so the visual clone pose path is receiving synthetic remote poses.
  - Still needs human visual confirmation: whether the result is a visible Grace-shaped duplicate, partial mesh pieces, or invisible due to skeleton/render binding.
- Screenshot feedback after this test: only `HUD fallback active` was visible. Overlay showed the dummy remote at `2.4m` away with `dx 2.4 dz -0.3`, so the marker/clone pose was mostly to Grace's +X/right side and not in the camera view. Added `set_dummy_ahead` and `set_dummy_offset` so the dummy can be placed at a fixed local world offset such as `dx=0 dz=2.4`.
- Cleanup result at 2026-07-01 08:59 CEST: `despawn` returned `ok=true`, `message=despawned`, and `puppet=despawned` for the visual mesh clone before the next required script reload.
- Runtime result at 2026-07-01 09:01 CEST after another REFramework reload:
  - `spawn_visual_mesh_clone` again resulted in `puppet=visual mesh clone spawned units=25`.
  - `set_dummy_ahead` and `set_marker=true` were accepted.
  - `config.json` confirmed `local_dummy=true`, `draw_remote_marker=true`, `dummy_offset_x=0`, `dummy_offset_y=0`, and `dummy_offset_z=2.4`.
  - `visual_spawn_probe.json` still reported `ok=true`, `source_mesh_units=25`, and `created_units=25`.
  - Screenshot feedback confirmed the HUD/overlay now shows `dx 0.0 dz 2.4`, but no second Grace is visible.
  - Inference: remote pose placement is correct; the shared-skeleton visual mesh clone path creates objects/components but does not render a separate visible character. Next test is `force_visible` mode, which disables shared skeleton on clone meshes and forces culling/depth flags toward visibility.
- Runtime result at 2026-07-01 09:06 CEST after `spawn_visual_mesh_clone_force_visible`:
  - `visual_spawn_probe.json` reported `visual_clone_mode=force_visible`, `ok=true`, `source_mesh_units=25`, and `created_units=25`.
  - Clone mesh readback for sampled units: `enabled=true`, `mesh_ready=true`, `material_ready=true`, `draw_default=true`, `draw_shadow=false`, `shared_skeleton=false`, `static_mesh=false`, `frustum_culling=false`, `occlusion_culling=false`, `ignore_depth=true`, `force_two_side=true`.
  - Source meshes also reported `mesh_ready=true`, `material_ready=true`, and `shared_skeleton=false`.
  - Screenshot feedback confirmed `force_visible` remains invisible despite the ready/enabled/culling-disabled clone mesh readback.
  - Added one final simple holder-copy variant, `force_static`, because `force_visible` left `StaticMesh=false`; `force_static` sets `StaticMesh=true` with the same visibility flags. If this remains invisible, do not repeat simple `via.render.Mesh` holder-copy tests; investigate missing engine registration through `app.MeshController`/`app.MeshUnit` ownership or prefab/hierarchy instantiation.
- Runtime result at 2026-07-01 09:15 CEST after `spawn_visual_mesh_clone_force_static`:
  - `visual_spawn_probe.json` reported `visual_clone_mode=force_static`, `ok=true`, `source_mesh_units=25`, and `created_units=25`.
  - Clone mesh readback confirmed `static_mesh=true`, `mesh_ready=true`, `material_ready=true`, `enabled=true`, `draw_default=true`, and `shared_skeleton=false`.
  - Screenshot feedback from the spawn area confirmed no Grace clone or mesh fragments visible; only HUD fallback remained visible.
  - Conclusion: do not continue simple `via.render.Mesh` holder-copy variants. The next path is `app.MeshController`/`app.MeshUnit` registration, collection ownership, or true prefab/hierarchy instantiation.
  - Added `mesh_registration_probe`, which dumps type surfaces and live object surfaces for `app.MeshController`, `app.PlayerMeshController`, `app.MeshUnit`, `via.render.Mesh`, `via.GameObject`, `via.Transform`, the live MeshUnit dictionary/list, and first live MeshUnit ownership refs.
- Runtime result at 2026-07-01 09:21 CEST after `mesh_registration_probe`:
  - Probe returned `ok=true`, `mesh registration probe dumped objects=13`.
  - Live counts: `MeshUnitDictionary=25`, `_MeshList=0`, `_MeshPartsDictionary=15`, `_PropertyValueContainers=2`.
  - `app.CharacterMeshControllerBase` exposes `registerMeshUnit(via.render.Mesh, app.MeshUnit.Type)`, `registerMeshUnitOnSubMontage(via.render.Mesh)`, `unregisterMeshUnit(System.UInt32)`, `searchInitMeshUnits()`, `notifyMeshUnitChanged()`, and `get_MeshUnitDictionary()`.
  - First live `app.MeshUnit` exposes constructor `.ctor(via.render.Mesh, app.MeshUnit.Type, app.MeshController, System.Boolean)` plus `setDrawAndUpdate`, `setDrawDefault`, and controller ownership getters.
  - Added `spawn_visual_mesh_clone_registered`, which creates clone meshes, applies force-visible flags, calls `PlayerMeshController:registerMeshUnit(cloneMesh, sourceMeshType)`, records registration before/after counts and discovered keys, and attempts `unregisterMeshUnit(key)` during `despawn`.
- Runtime result at 2026-07-01 09:23 CEST after `spawn_visual_mesh_clone_registered`:
  - `visual_spawn_probe.json` reported `visual_clone_mode=registered_player_controller`, `ok=true`, `source_mesh_units=25`, and `created_units=25`.
  - Registration readback for sampled clone rows reported `reg_attempt=true`, `reg_ok=true`, and monotonically increasing MeshUnit dictionary counts.
  - First sampled registration: `before=25`, `after=26`, `key=33161615`, `meshType=0`.
  - Last registration: `before=49`, `after=50`, `key=875920015`, `meshType=1`.
  - Clone mesh readback remained `mesh_ready=true`, `material_ready=true`, `enabled=true`, and `ignore_depth=true`.
  - User screenshot feedback still showed no visible Grace clone in front of the player. Registration alone is insufficient; next likely path is parenting/hierarchy under a renderable root or instantiating/copying the true prefab hierarchy.
- Implementation added at 2026-07-01 09:28 CEST:
  - Added `spawn_visual_mesh_clone_registered_child` / `visual_clone_mode=registered_player_child`.
  - This variant force-copies the live `via.render.Mesh` holder/material holder, parents the clone root under the live player transform, parents each clone mesh GameObject under that clone root, then registers each clone mesh through `PlayerMeshController:registerMeshUnit(cloneMesh, sourceMeshType)`.
  - `visual_spawn_probe.json` now records `root_parenting` and per-row `parenting` for this mode, so the next test can distinguish a rejected transform hierarchy from a rendering/asset issue.
- Runtime result at 2026-07-01 09:34 CEST after `spawn_visual_mesh_clone_registered_child`:
  - Reload was confirmed because the new action was accepted.
  - `dev_result.json` reported `ok=true`, `message=visual mesh clone spawned units=25`, and `scene=Chap1_01`.
  - `visual_spawn_probe.json` reported `visual_clone_mode=registered_player_child`, `created_units=25`, `root_parenting.ok=true`, `parentOk=25`, and `regOk=25`.
  - New blocker exposed by readback: all 25 source meshes had `material_ready=true` and a material holder, but only 2/25 clone meshes had `material_ready=true` and a material holder.
  - Inference: child hierarchy and MeshController registration are accepted; material binding/copy is now the highest-signal issue to test before going back to prefab instantiation.
- Implementation added at 2026-07-01 09:34 CEST:
  - Added `spawn_visual_mesh_clone_registered_child_material` / `visual_clone_mode=registered_player_child_material`.
  - `copy_mesh_component_resources` now records `resource_copy` diagnostics and retries material copy after `setMesh` and after applying force-visible flags.
  - The new material mode also runs `material_post_register` after `PlayerMeshController:registerMeshUnit(...)`.
  - Initial material copy attempts included `set_Material(via.render.MeshMaterialResourceHolder)`, `set_Material`, `set_MaterialParamCount`, wrapped `get_Materials`/`get_MaterialNames` item copies, and per-material-slot texture/float/float4 value copies. Later crash results removed the dangerous `getMaterialTexture`, `setMaterial*` slot copy, and `set_MaterialParamCount` calls from the active path.
- Runtime result at 2026-07-01 09:36 CEST after `spawn_visual_mesh_clone_registered_child_material`:
  - Reload was confirmed because the new action was accepted.
  - `dev_result.json` reported `ok=true`, `message=visual mesh clone spawned units=25`, and `scene=Chap1_01`.
  - Compact probe summary: `visual_clone_mode=registered_player_child_material`, `created=25`, `rootParentOk=true`, `parentOk=25`, `regOk=25`, `meshReady=25`, `cloneMaterialReady=25`, `cloneMaterialHolders=25`, `postMaterialReady=25`, `postMaterialHolders=25`, `sourceMaterialReady=25`, and `sourceMaterialHolders=25`.
  - First unit's material diagnostics showed `set_Material(via.render.MeshMaterialResourceHolder)` succeeded, material names copied 8/8, and per-slot values copied many float/float4/texture values; some `setMaterialTexture` calls still threw for individual variables, but overall material holder/readiness became valid.
  - User then reported the game crashed on reload. `Get-Process re9` confirmed the game had exited.
  - `re2_framework_log.txt` ended with `Exception occurred: c0000005` at 2026-07-01 09:35:59 after automatic HookManager re-registration of many observer hooks (`Hook assigned ID 818` through `851` in the log tail). This points at reload-unsafe repeated `sdk.hook` setup, not at Lua parse failure.
  - Mitigation applied immediately to the live game config: `auto_spawn_puppet=false`, `visual_clone_mode=shared_skeleton`, and `local_dummy=false`, so the next start does not immediately trigger the heavy clone path.
- Reload-safety implementation added at 2026-07-01 09:39 CEST:
  - Default `auto_spawn_puppet=false`.
  - Runtime trace states (`level_trace_enabled`, `pool_trace_enabled`, `bind_trace_enabled`) no longer initialize from persisted config on script load.
  - `re.on_frame` no longer calls `install_spawn_observer_hooks()` or `install_bind_trace_hooks()` unconditionally.
  - Spawn observer hooks now install only when `state.spawn_hook_enabled` or a live level trace is explicitly enabled.
  - Bind trace hooks now install only when bind tracing is explicitly enabled.
  - Added `start_spawn_hooks` dev action and `Install Spawn Hooks` UI button for manual diagnostics.
- Reload-safety follow-up at 2026-07-01 09:43 CEST:
  - The running `re9.exe` process was still the pre-safety Lua; `dev_result.json` still showed old `spawn_hook_status=installed 23 observer hooks` and `bind_trace_status=installed 7 bind hooks`.
  - `dev_command.json` still contained `spawn_visual_mesh_clone_registered_child_material`, which would be reprocessed after any script reload because `dev_last_id` resets to 0. Replaced it with harmless `clear_remote`.
  - Added `runtime_safety_status`, a no-clone/no-hook dev action. After the next reload, use it first to verify the safe code is active before running any clone test.
- Runtime result at 2026-07-01 09:48 CEST:
  - `runtime_safety_status` verified the reload-safe Lua was active: `auto_spawn=false`, `spawn_hook_enabled=false`, `spawn_hook_attempted=false`, `bind_trace_enabled=false`, `bind_trace_attempted=false`, and `visual_clone_mode=shared_skeleton`.
  - `set_dummy_ahead` succeeded, `set_marker=true` succeeded, and `dev_result.json` showed `scene=Chap1_01` with `remote_samples=12`.
  - Starting `spawn_visual_mesh_clone_registered_child_material` crashed the game before `dev_result.json` updated to the new command ID.
  - `re2_framework_log.txt` showed `Exception thrown in REMethodDefinition::invoke for via.render.Mesh.getMaterialTexture` immediately before `Exception occurred: c0000005`.
  - Conclusion: do not call `via.render.Mesh.getMaterialTexture` in a live spawn path. Even wrapped in `pcall`, this getter can destabilize/crash the process.
  - Mitigation: neutralized game config and pending `dev_command.json`, then disabled active per-slot material texture/float/float4 copying. The material path now relies on mesh holder, material holder, material names array, and material param count only.
- Runtime result at 2026-07-01 10:01 CEST after removing `getMaterialTexture` from the active path:
  - RE9 restarted cleanly and `runtime_safety_status` passed with hooks not attempted.
  - `set_dummy_ahead` and `set_marker=true` succeeded in `Chap1_01`.
  - `spawn_visual_mesh_clone_registered_child_material` returned `ok=true`, `message=visual mesh clone spawned units=25`, and the compact probe reported `created=25`, `parentOk=25`, `regOk=25`, `meshReady=25`, `cloneMaterialReady=25`, and `cloneMaterialHolders=25`.
  - The game still crashed immediately afterward.
  - The log no longer points to `getMaterialTexture`; it now shows `Exception thrown in REMethodDefinition::invoke for via.render.Mesh.set_SharedSkeletonGameObject`, then `Internal game exception thrown in REMethodDefinition::invoke for app.CharacterMeshControllerBase.notifyMeshUnitChanged` with `System.NullReferenceException`, then `c0000005`.
  - Mitigation added: clone mesh setup no longer calls `set_SharedSkeletonGameObject(...)`, and `register_clone_mesh_unit` no longer calls `notifyMeshUnitChanged`. `visual_spawn_probe.json` now includes `safety.clear_shared_skeleton_game_object=false` and `safety.notify_mesh_unit_changed=false`.
- Runtime result at 2026-07-01 10:13 CEST after skipping `set_SharedSkeletonGameObject(...)` and `notifyMeshUnitChanged()`:
  - `runtime_safety_status` verified `clone_safety=no_skeleton_ref_no_notify`.
  - Dummy/marker setup succeeded, then `spawn_visual_mesh_clone_registered_child_material` returned `ok=true`, `message=visual mesh clone spawned units=25`.
  - Compact probe reported `created=25`, `parentOk=25`, `regOk=25`, `meshReady=25`, `matReady=25`, and `matHolders=25`, with `safety.clear_shared_skeleton_game_object=false` and `safety.notify_mesh_unit_changed=false`.
  - RE9 still crashed a few seconds later.
  - The log now points to `Exception thrown in REMethodDefinition::invoke for via.render.Mesh.set_MaterialParamCount`, then `c0000005`.
  - Mitigation added: active material copy no longer calls `set_MaterialParamCount`; the probe records `param_count_set=false` and `param_count_skipped=disabled after via.render.Mesh.set_MaterialParamCount crash on 2026-07-01`. `runtime_safety_status` now reports `clone_safety=no_skeleton_ref_no_notify_no_material_param_count`.
- Runtime result at 2026-07-01 10:31 CEST after skipping `set_MaterialParamCount`:
  - `runtime_safety_status` verified the reload-safe build with `clone_safety=no_skeleton_ref_no_notify_no_material_param_count`.
  - `set_dummy_ahead` and `set_marker=true` succeeded in `Chap1_01`.
  - `spawn_visual_mesh_clone_registered_material` was accepted by the reloaded Lua and returned `ok=true`, `message=visual mesh clone spawned units=25`.
  - Compact probe reported `visual_clone_mode=registered_player_material`, `source=25`, `created=25`, `regOk=25`, `meshReady=25`, `matReady=25`, and `param_count_set=false`.
  - The mode uses the material-copy path and still enables child hierarchy/parenting through `material_post_mode`; this was initially interpreted as suspicious because transform readbacks after parenting reported `x=0,y=0,z=0`, but screenshot evidence proved the visible result is correct.
  - User screenshot feedback confirmed a second visible Grace in-game. The user reported: "ICH SEHE GRACE ... die hat meinem movement gefolgt mit bisschen abstand".
  - `despawn` was sent immediately after the first visible test while investigating the readback, which explains why the clone disappeared.
  - Respawning `spawn_visual_mesh_clone_registered_material` returned the same 25/25 success metrics, and RE9 remained responsive after a 6 second stability check.
  - Current conclusion: the first known working visible local Grace clone path is parented MeshUnit cloning plus PlayerMeshController registration plus safe material-holder/name copy. Preserve this path; do not "fix" away the material-post child hierarchy without replacing the visibility mechanism.
- Implementation added at 2026-07-01 10:38 CEST:
  - Added `read_local_position(...)` and `set_transform_local_pose(...)` using `via.Transform.get_LocalPosition()` and `set_LocalPosition(via.vec3)`.
  - Added `state.puppet_root_parented` so `apply_remote_pose()` can distinguish visual child-hierarchy clones from older root-only puppet attempts.
  - The first attempted active control path made `update_visual_clone_pose(...)` return early for parented roots and applied `remote pose - local pose` through `set_LocalPosition`.
  - `visual_spawn_probe.json` now records `root_local_position_after_parent`, `clone_local_position_after_parent`, and `clone_local_position_final` because world `get_Position()` can report `0,0,0` after parenting despite the rendered clone being visibly offset.
- Runtime result at 2026-07-01 10:43 CEST:
  - Reload was verified with `runtime_safety_status`, and `spawn_visual_mesh_clone_registered_material` returned `ok=true`, `created=25`, `regOk=25`, `meshReady=25`, and `matReady=25`.
  - Probe fields showed `root_local_position_after_parent` near the intended 2.4m offset, and RE9 stayed responsive after an 8 second stability check.
  - User feedback then confirmed no spawned Grace was visible. Conclusion: the early-return parent-root `LocalPosition` control path breaks visibility even though the numeric probe looks plausible.
- Implementation correction at 2026-07-01 10:46 CEST:
  - Removed the early-return parent-root control branch from `update_visual_clone_pose(...)`.
  - `apply_remote_pose()` again calls `update_visual_clone_pose(pose)` and then continues to the prior root `set_Position`/`set_Rotation` behavior.
  - Preserve the LocalPosition readback fields for diagnostics, but do not use the root-only LocalPosition branch as active control until a safer variant is proven visible.
- Runtime/user result at 2026-07-01 10:53 CEST:
  - User screenshot confirmed the `registered_player_material` debug-render path is visible again.
  - Current visual defects: no animation, weak/odd shading, clone draws through other scene geometry/people, and in offline dummy mode it moves with the local player.
  - The wallhack artifact is explained by the current `force_visible` copy mode, which sets `IgnoreDepth=true`, `IgnoreDepthTransparentCorrection=true`, `DrawDepthOcclusion=false`, `OcclusionCulling=false`, and `DrawShadowCast=false`.
- Implementation added at 2026-07-01 10:53 CEST:
  - Added `apply_lit_visible_mesh_flags(...)`.
  - Added `visual_clone_mode=registered_player_material_lit` and dev action `spawn_visual_mesh_clone_registered_material_lit`.
  - This new mode preserves the working parented MeshUnit registration plus material-holder/name-copy path, but uses `lit_visible` render flags.
  - `lit_visible` copies source `StaticMesh`, `SharedSkeleton`, `DrawShadowCast`, `DrawRaytracing`, `ForceTwoSide`, `FrustumCulling`, `OcclusionCulling`, `ReceiveUserLighting`, and `UseStencilValuePriority`, then forces `Enabled=true`, `DrawDefault=true`, `IgnoreDepth=false`, `IgnoreDepthTransparentCorrection=false`, `DrawDepthOcclusion=true`, and `DrawDepthBlocker=true`.
  - This is intended to test wallhack/shading fixes without deleting the known-visible debug path.
- Runtime/user result at 2026-07-01 12:16 CEST:
  - After RE9 restart, `set_visual_clone_mode registered_player_material_lit` was accepted, proving the new Lua was loaded.
  - `spawn_visual_mesh_clone_registered_material_lit` returned `ok=true`, `message=visual mesh clone spawned units=25`.
  - Compact probe reported `created=25`, `regOk=25`, `meshReady=25`, `matReady=25`, `matHolders=25`, and unsafe calls still disabled.
  - First clone render readback: `ignore_depth=false`, `draw_shadow=true`, `occlusion_culling=true`, `frustum_culling=true`, `draw_default=true`, `enabled=true`, `mesh_ready=true`, `material_ready=true`.
  - First source render readback matched those important flags.
  - RE9 stayed responsive after an 8 second stability check.
  - User screenshot feedback confirmed the clone now looks graphically correct.
- Implementation added at 2026-07-01 12:16 CEST:
  - Added dev action `set_dummy_static_ahead`.
  - It captures the current local pose, places one frozen remote sample 2.4m in front of the player's current yaw, disables `cfg.local_dummy`, and leaves `state.remote_samples` with a single static pose.
  - Purpose: verify that the visible clone can remain independent of local movement before wiring it to real network snapshots.

## Inferences To Verify

These are not facts yet:

- The fastest path is now the visual-only parented MeshUnit clone rather than another full player-controlled `app.PlayerContext`.
- The next high-risk unknown is control semantics: the visible clone followed local player movement through the parented hierarchy, so the next step is to keep visibility while driving the clone from remote snapshots with a stable relative transform.
- `via.Prefab` loading may require exact `natives/stm/...pfb.18` paths or a different resource type than current `sdk.create_resource("via.Prefab", path)` attempts.
- If direct prefab instantiate fails, the next target should be the local Grace GameObject/components for resource handles, mesh controllers, motion banks, and loaded prefab references.
- A usable MVP may start with a visual-only Grace puppet with disabled collision/input/AI, then add animation from velocity/motion state.

## Immediate Next Steps

- Preserve `spawn_visual_mesh_clone_registered_material_lit` only as the visible parented proof/control path. It is useful as a rendering/material control, not as the final architecture.
- The Main Menu -> gameplay ownership trace is complete. Do not repeat it unless the hook set changes; the useful files are `level_load_trace.json`, `bind_trace.json`, `pool_trace.json`, `spawn_hook_log.json`, and `grace_ownership_recipe.json`.
- Next runtime pass is the opt-in load-phase `setup_request_spawn` injection:
  - Return to the Main Menu.
  - Reload Lua, run `runtime_safety_status`, then run `arm_load_phase_player_clone_injection` with `setup_request_spawn`.
  - Load the save/level into `Chap1_01` and wait until Grace is controllable.
  - Run `dump_load_phase_injection_probe`, then inspect `load_phase_injection_probe.json`, `pool_trace.json`, and `level_load_trace.json`.
- Success criteria:
  - A fresh injected ContextID appears in `CharacterManager:getContextRef(...)`.
  - It gets a GameObject, `app.Cp_A100Updater`, and a used/finalized CharacterPool entry without `onChangeActivePlayer(empty -> new)`.
  - Visual best case: a second Grace appears without being parented to local Grace and local camera yaw/pitch no longer moves it.
- Failure criteria:
  - If the context appears but stays without GameObject/updater, test the missing pool/updater allocation step directly.
  - If the context gets GameObject/updater but becomes active local player, stop using `createControlCharacter()`-style paths for the remote clone and isolate the non-control spawn boundary.
  - If no context appears during the load window, `LevelPlayerCreateController` is likely hard-gated to the real player setup. Move next to real prefab/montage spawn using confirmed asset paths and stop trying controller replay.
- Do not run clone spawns during the listener pass.
- Do not run per-slot material texture copy again; avoid `via.render.Mesh.getMaterialTexture` in the clone spawn path.
- Do not call `via.render.Mesh.set_SharedSkeletonGameObject(...)`, `app.CharacterMeshControllerBase.notifyMeshUnitChanged()`, or `via.render.Mesh.set_MaterialParamCount` in a live clone path unless a new isolated test proves them safe.
- Use small JSON outputs only; avoid broad UI dumps that can freeze RE9.
- After Lua changes, run `scripts/build_lua_bundle.ps1`, deploy `reframework/autorun/re9mp.lua` and the `reframework/autorun/re9mp/` source folder, then user must use `Reset scripts` or restart RE9 for the new code to load.
