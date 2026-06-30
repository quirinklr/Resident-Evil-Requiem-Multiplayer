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
- Tailscale or another LAN-like overlay if the two PCs are not in the same network.

```powershell
git clone https://github.com/quirinklr/Resident-Evil-Requiem-Multiplayer.git
cd Resident-Evil-Requiem-Multiplayer
cmake -S . -B build -A x64
cmake --build build --config Release
```

On this machine CMake selects `Visual Studio 17 2022`.

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

1. Both players start RE9 and manually load the same area.
2. Host opens the REFramework overlay and clicks `Host Lobby`.
3. Host sends the displayed join code to the client over Tailscale.
4. Client pastes the join code and clicks `Join`.
5. If BuildID, EXE version, or scene differ, the connection is denied and the overlay shows why.

The host must allow inbound UDP `27777` in Windows Firewall. With Tailscale, no router port forwarding is expected.

## Local install check

After deployment, these files should exist in the RE9 folder:

- `dinput8.dll`
- `reframework/plugins/re9mp.dll`
- `reframework/autorun/re9mp.lua`
- `reframework_revision.txt` containing `a0e9010fb0449dc9d824b5978ee759eeaf50f7c6`
