# RE9 Multiplayer MVP

This repository contains a REFramework-based multiplayer prototype for Resident Evil Requiem.

## What is implemented

- Native REFramework plugin `re9mp.dll` with UDP host/client networking.
- Host lobby on UDP `27777` with join code `<ip>:27777:<token>`.
- Handshake checks protocol, mod version, Steam BuildID, `re9.exe` version, and current scene.
- Lua bridge `re9mp.lua` for RE9 player/scene sampling, lobby UI, and remote transform application.
- 30 Hz movement snapshots and local interpolation buffer for remote movement.
- Tailscale-friendly Direct IP flow; no Steamworks and no public relay server.

## Current MVP boundary

The network/lobby/snapshot path is complete. The remote Grace visual is best-effort because RE9's exact runtime spawn/clone API must be confirmed in-game through REFramework's TDB/Object Explorer. The Lua bridge attempts safe clone methods and reports discovered clone candidates in the overlay.

## Build

Prerequisites:

- Resident Evil Requiem on Steam, currently tested against AppID `3764200`, BuildID `23634047`, `re9.exe` `1.3.1.0`.
- Visual Studio 2022 with C++ build tools and CMake.
- PowerShell. Run deploy scripts from an elevated PowerShell if your RE9 install is under `C:\Program Files (x86)`.
- Tailscale if the two PCs are not in the same network. This is the recommended setup.

```powershell
git clone https://github.com/quirinklr/Resident-Evil-Requiem-Multiplayer.git
cd Resident-Evil-Requiem-Multiplayer
cmake -S . -B build -A x64
cmake --build build --config Release
```

On this machine CMake selects `Visual Studio 17 2022`.

## Tailscale setup

Tailscale makes both PCs behave like they are on the same private LAN, even if they are in different houses. The mod still uses the host player's PC as the server. There is no public relay or Steamworks lobby in this mod.

Do this on both PCs:

```powershell
.\scripts\install_tailscale.ps1
```

If Tailscale reports `NeedsLogin`, run:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" up
```

That command prints a `https://login.tailscale.com/a/...` link. Open it in the browser and log in.

Both players must be in the same Tailnet:

- Fastest test: both players log into Tailscale with the same account.
- Cleaner setup: host opens the Tailscale admin console, invites the friend, and the friend accepts the invite.
- After login, both PCs should show each other in Tailscale.

Exact invite flow:

1. Host opens <https://login.tailscale.com/admin/machines>.
2. Host confirms their own PC appears under `Machines`.
3. Host opens `Users`.
4. Host clicks `Invite users`.
5. Host enters the friend's email address and sends the invite.
6. Friend opens the invite email and accepts it.
7. Friend installs Tailscale:

   ```powershell
   winget install --id Tailscale.Tailscale --exact
   ```

8. Friend logs into Tailscale with the invited account:

   ```powershell
   & "C:\Program Files\Tailscale\tailscale.exe" up
   ```

9. Host refreshes `Machines`; both `Quirin` and the friend's PC should be listed.

If the host only sees the `Add your first device` card after logging in, refresh the page after `tailscale up` succeeds. The device is only added after the desktop client is authenticated, not just after signing into the website.

Important distinction:

- `Users` means the account has joined the Tailnet.
- `Machines` means a concrete PC is connected to that Tailnet.
- For RE9MP, the friend's PC must appear under `Machines`. A user entry alone is not enough.

If the friend appears under `Users` but their PC does not appear under `Machines`, they are probably logged into Tailscale on Windows under their own Tailnet/profile. On the friend's PC, run:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" switch --list
```

If a profile for the host Tailnet appears, switch to it:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" switch "deinquirin13@gmail.com"
```

If no host Tailnet profile appears, force a fresh login and select/accept the host Tailnet in the browser:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" up --force-reauth
```

After that, the friend should verify:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
```

The output must list both machines, for example `quirin` and the friend's `desktop-*` machine.

Browser login fallback with an auth key:

If the Tailscale browser login shows a server error, the host can create a short-lived auth key in the Tailscale admin console. Auth keys register a new device without interactive browser login.

Host steps:

1. Open <https://login.tailscale.com/admin/settings/keys>.
2. In `Auth keys`, click `Generate auth key`.
3. Use a safe short-lived key:
   - `Reusable`: off
   - `Ephemeral`: off
   - `Pre-approved`: on, if the option is shown
   - Expiration: shortest practical value, such as 1 day
   - Tags: none
4. Copy the key once and send it only to the friend privately.
5. Revoke/delete the key after the friend's PC appears in `Machines`.

Friend steps:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" logout
.\scripts\install_tailscale.ps1 -AuthKey "PASTE_KEY_HERE"
& "C:\Program Files\Tailscale\tailscale.exe" status
```

Do not commit, screenshot, or paste auth keys into public chats. Treat them like passwords.

Verify on both PCs:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
& "C:\Program Files\Tailscale\tailscale.exe" ip -4
```

Expected result:

- `status` lists both machines.
- `ip -4` prints a `100.x.x.x` address.
- The host's RE9MP join code should also start with that `100.x.x.x` address.

On the host PC only, allow inbound UDP `27777`:

```powershell
.\scripts\setup_firewall.ps1
```

Run this from an elevated PowerShell if Windows asks for administrator rights. With Tailscale, no router port forwarding is expected.

To open an elevated PowerShell quickly:

1. Press `Start`.
2. Type `PowerShell`.
3. Right-click `PowerShell`.
4. Click `Run as administrator`.
5. `cd` into this repository and run `.\scripts\setup_firewall.ps1`.

## Deploy

```powershell
.\scripts\update_reframework.ps1
.\scripts\deploy.ps1
```

`update_reframework.ps1` backs up the existing `dinput8.dll`, `reframework_revision.txt`, `ref_ui.ini`, and `reframework` folder before installing REFramework Nightly 01391.

If RE9 is installed somewhere else, pass the install path to both scripts:

```powershell
.\scripts\update_reframework.ps1 -GameDir "D:\SteamLibrary\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem"
.\scripts\deploy.ps1 -GameDir "D:\SteamLibrary\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem"
```

## Usage

1. Both players install and log into Tailscale.
2. Both players verify `tailscale status` shows both machines.
3. Both players build and deploy the mod.
4. Both players start RE9 and manually load the same area.
5. Host opens the REFramework overlay, usually with `Insert`.
6. Host opens `RE9 Multiplayer MVP` and clicks `Host Lobby`.
7. Host sends the displayed join code to the client. It should look like `100.x.x.x:27777:<token>`.
8. Client pastes the join code and clicks `Join`.
9. If BuildID, EXE version, or scene differ, the connection is denied and the overlay shows why.

## Troubleshooting

- Tailscale app is not visible: run `& "C:\Program Files\Tailscale\tailscale.exe" up` from PowerShell.
- `tailscale` command is not found: use the full path `C:\Program Files\Tailscale\tailscale.exe`.
- `BackendState` is `NeedsLogin`: open the login URL printed by `tailscale up`.
- Join code does not start with `100.`: Tailscale is probably not logged in or connected.
- Client cannot connect: host should run `.\scripts\setup_firewall.ps1` and allow UDP `27777`.
- Overlay shows scene mismatch: both players must manually load the same area before joining.
- Overlay shows BuildID or EXE mismatch: both players must update RE9 to the same Steam build.
- Overlay opens but no remote Grace appears: send the host's and client's `Puppet:` and `Clone candidates:` lines from the overlay. The network path is separate from the RE9 runtime clone/spawn probe.

### Dev command bridge

After RE9 has loaded `re9mp.lua` once, safe debug commands can be sent without clicking in the REFramework UI:

```powershell
.\scripts\send_dev_command.ps1 -Action status
.\scripts\send_dev_command.ps1 -Action set_dummy -Value $true
.\scripts\send_dev_command.ps1 -Action set_marker -Value $false
.\scripts\send_dev_command.ps1 -Action despawn
```

Results are written to `reframework\data\re9mp\dev_result.json` in the RE9 folder. Loading new Lua code still requires one manual `Reset scripts` or a full RE9 restart.

### Offline remote marker test

This test works without a second PC and checks whether the Lua overlay can draw a remote-player marker in the loaded RE9 scene.

1. Start RE9 and load into gameplay until the overlay shows `Local player: detected`.
2. Open `RE9 Multiplayer MVP`.
3. Enable `Draw remote marker`.
4. Enable `Local dummy remote`.
5. Watch the `Remote:` line. It should update with a changing sequence number and distance.
6. Watch the `Draw:` line:
   - `draw ok: screen ...` means REFramework accepted the marker draw call and the marker should be on screen.
   - `draw ok: remote world point not on screen` means the dummy exists but is behind/outside the camera view.
   - `draw failed: ...` means the exact REFramework draw API error should be copied into the issue/debug log.

`Local dummy remote` only creates synthetic remote snapshots around the local player. It does not test networking and it does not spawn the real Grace puppet.

## Local install check

After deployment, these files should exist in the RE9 folder:

- `dinput8.dll`
- `reframework/plugins/re9mp.dll`
- `reframework/autorun/re9mp.lua`
- `reframework_revision.txt` containing `a0e9010fb0449dc9d824b5978ee759eeaf50f7c6`
