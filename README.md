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

```powershell
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

## Usage

1. Both players start RE9 and manually load the same area.
2. Host opens the REFramework overlay and clicks `Host Lobby`.
3. Host sends the displayed join code to the client over Tailscale.
4. Client pastes the join code and clicks `Join`.
5. If BuildID, EXE version, or scene differ, the connection is denied and the overlay shows why.
