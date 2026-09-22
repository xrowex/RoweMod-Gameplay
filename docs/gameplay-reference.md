# RoweMod Gameplay

Live **speed and feel** options for [Rollout Inline](https://store.steampowered.com/app/4464990/). Unofficial. This is **not** the clothing kit.

Clothes: [xrowex/RoweMod-Rollout](https://github.com/xrowex/RoweMod-Rollout)
Shared outfits: [xrowex/RoweMod-Gallery](https://github.com/xrowex/RoweMod-Gallery)

This repo needs **UE4SS** in the game. Clothing overlays do not. Players who only want shirts can ignore this.

## Install

Download the full release ZIP (not GitHub's Source code archive), extract it, close the game, and double-click **install.cmd**. The installer includes the tested UE4SS runtime and the standalone Steam companion. It preserves personal settings and other mods and backs up files before replacing them.

Launch Rollout from Steam and press **F5**. Updates check automatically at game launch and apply after the game and companion close. See [update behavior and release publishing](auto-updates.md).

Default is **1.25×** casual + sprint acceleration. This does not directly multiply maximum speed. Edit `ue4ss\Mods\RoweModGameplay\Scripts\config.lua` and press **F8** in-game.

## In the game

| Input | What it does |
|---|---|
| **F5** | Open gameplay settings and Steam multiplayer menu |
| Numpad **+** / **-** | Speed up / slow down (0.1 steps) |
| **F8** | Reload `config.lua` |
| **F9** | Toggle multiplayer session (needs `tools/rowemod_mp.py`) |
| **F7** | Recon dump (grind/trick-hint properties + functions) |
| **F6** | Toggle watch (log grind/trick-related property changes) |
| **~** or **F10** | Console (UE4SS ConsoleEnabler) |

[In-game menu guide](in-game-menu.md): live settings, save/reset, hosting and session browser.

Console:

```
rowemod speed 1.5
rowemod dump
rowemod dump all
rowemod recon
rowemod watch on
rowemod mp on
rowemod mp status
rowemod reload
```

Green on-screen text confirms the current multiplier. `rowemod dump` prints live values. `rowemod dump all` lists every numeric/bool field on the skater.

### Multiplayer (experimental)

Steam online test build: **`tools\mp_online.cmd`** opens friends-only/public
hosting, friend joining and the session browser. See **[docs/steam-online.md](steam-online.md)**.
Local API, lobby and startup checks pass; two-account internet play is awaiting testing.

LAN host/join with independently driven remote skaters, sender-owned models/clothes/boots, and interpolated bone poses. See **[docs/multiplayer.md](multiplayer.md)**.

| Mode | Command |
|---|---|
| Same PC, 2 windows | `tools\mp_dual_local.cmd` |
| Two PCs | `mp_host.cmd` / `mp_join.cmd <ip>` |
| No game (proof) | `tools\mp_prove.cmd` |

Then load the **same map** and enter `rowemod mp on` in each game console (F10). Design notes: [docs/multiplayer-tricks-grinds.md](multiplayer-tricks-grinds.md).

## What it changes

On `NewMainCharacter` (and matching fields on `SettingsSaveGame` so the pause menu stays in sync):

The table below is the legacy manual override surface, not a list of verified sliders. Use F5 for audited controls. Several legacy fields are runtime state or lack confirmed character support; see the [slider audit](slider-audit.md) before setting them manually.

| Group | `config.lua` keys |
|---|---|
| Speed | `speedMultiplier`, `casualSpeedIncrease`, `sprintSpeedIncrease`, `maxLinearForce`, `maxAngularForce`, `gravity` |
| World gravity | `gravityMultiplier` (0.25–2, scales this map's physics and synchronizes jump prediction; legacy `gravity` only changes prediction) |
| Jump | `jumpVelocity`, `minJumpHeight`, `maxJumpHeight`, `jumpPrepSteering` |
| Grind / balance | `grindMagnetStrength`, `grindMagnetSize`, `balanceIntensity`, `balanceDriftIncrease`, `balanceDriftStrength`, `baseBalanceDrift`, `requiresBalance`, `showBalanceMeter`, `enableGrindSparks` |
| Spin / flip | `maxSpinSpeed`, `maxFlipSpeed`, `spinMultiplier`, `flipMultiplier`, `grabSpinSpeedDivider` |
| Steering | `steerMultiplier`, `steeringStrengthSetting`, `triggerSteering`, `streamlinedControls` |
| Slow-mo | `slomoSpeed`, `slowmotion` |
| Camera | `cameraDistance`, `cameraHeight`, `cameraLookUp`, `cameraSideOffset`, `airRotInterpSpeed` |
| Extra | `comboMultiplier`, `forceFeedbackStrength` |

Leave a key as `nil` to leave that field alone. Pause **Gameplay** already has grind magnet, balance, min jump, slomo, sparks, camera, and steering — the rest were hidden on the character.

Frames and wheels in the clothing catalog are meshes only. They do not store top speed. Surface friction lives on `PM-concrete` / wood / grass, not on the skater.

## Legal

MIT for this Lua. Rollout Inline belongs to its owners. Fan project. Do not use this to bother other players if a multiplayer mode exists.
