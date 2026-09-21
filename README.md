# RoweMod Gameplay

Live **speed and feel** options for [Rollout Inline](https://store.steampowered.com/app/4464990/). Unofficial. This is **not** the clothing kit.

Clothes: [xrowex/RoweMod-Rollout](https://github.com/xrowex/RoweMod-Rollout)  
Shared outfits: [xrowex/RoweMod-Gallery](https://github.com/xrowex/RoweMod-Gallery)

This repo needs **UE4SS** in the game. Clothing overlays do not. Players who only want shirts can ignore this.

## Install

1. Install UE4SS into `RollerSkate\Binaries\Win64` (the clothing kit’s `tools\install_ue4ss.ps1`, or [UE4SS experimental](https://github.com/UE4SS-RE/RE-UE4SS) for UE 5.4).
2. Double-click **`install.ps1`** in this folder. It copies the Lua mod next to UE4SS.
3. Launch the game from Steam.

Default is **1.25×** casual + sprint speed increase. Edit `ue4ss\Mods\RoweModGameplay\Scripts\config.lua` and press **F8** in-game.

## In the game

| Input | What it does |
|---|---|
| Numpad **+** / **-** | Speed up / slow down (0.1 steps) |
| **F8** | Reload `config.lua` |
| **F9** | Toggle multiplayer session (needs `tools/rowemod_mp.py`) |
| **F7** | Recon dump (grind/trick-hint properties + functions) |
| **F6** | Toggle watch (log grind/trick-related property changes) |
| **~** or **F10** | Console (UE4SS ConsoleEnabler) |

Console:

```
rowemod speed 1.5
rowemod dump
rowemod recon
rowemod watch on
rowemod mp on
rowemod mp off
rowemod mp status
rowemod reload
```

Green on-screen text confirms the current multiplier.

### Multiplayer (experimental)

LAN ghost skaters with **map handshake** + transform + trick/grind events. See **[docs/multiplayer.md](docs/multiplayer.md)**.

1. Host: `tools\mp_host.cmd`
2. Join: `tools\mp_join.cmd <host-lan-ip>`
3. Same map (or `rowemod mp travel` after host `rowemod mp map`)
4. In-game: **F9** / `rowemod mp host` / `rowemod mp join`

Design notes: [docs/multiplayer-tricks-grinds.md](docs/multiplayer-tricks-grinds.md).

Prove the LAN path without the game: `tools\mp_prove.cmd` (writes [docs/proofs/latest.json](docs/proofs/latest.json)).


## What it changes

On `NewMainCharacter`:

- `CasualSpeedIncrease` / `SprintSpeedIncrease` (the speed multiplier)
- Optional overrides in `config.lua`: `maxLinearForce`, `maxAngularForce`, `gravity`, `slomoSpeed`

Frames and wheels in the clothing catalog are meshes only. They do not store top speed.

## Legal

MIT for this Lua. Rollout Inline belongs to its owners. Fan project. Do not use this to bother other players if a multiplayer mode exists.
