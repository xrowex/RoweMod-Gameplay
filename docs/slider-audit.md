# Gameplay slider audit — 2026-09-22

The previous menu used guessed limits. Several were wrong by orders of magnitude.
This audit decoded the currently installed Rollout Inline UE 5.4 assets using
retoc and UAssetAPI with its UE4SS type mapping. Sources: `NewMainCharacter`,
`SettingsSaveGame`, `W-gameplay-settings`, and `W-slider-setting`. Extracted game
assets stay in the ignored local build folder and are not distributed.

## Corrected controls

Displayed percentages are converted from the game's 0–1 values. The menu writes
the original game units. Mouse, keyboard and controller edits share the same
step grid. Opening the menu does not write or clamp the current game value.

| Control | Game-unit range / step | Stock value | Basis |
|---|---|---|---|
| Acceleration multiplier | 0.4–4 / 0.05 | 1 | Mod range; multiplies both acceleration fields, not maximum speed |
| Gravity multiplier | 0.25–2 / 0.05 | 1 | Mod range relative to the current map's initialized physics gravity; never zero |
| Steering strength | 0.25–2 / 0.05 | 1 | Mod range around the stable character setting |
| Controller vibration | 0–1 / 0.05 | 1 | Normalized feedback strength; displayed as 0–100% |
| Minimum jump scale | 0–1 / 0.25 | 1 | Stock slider limits; displayed as 0–100% |
| Jump steering resistance | 1–19 / 1 | 10 | Stock UI uses -19 to -1 and negates the value; character divides steering force by this positive value |
| Maximum flip rate | 90–910 / 5 | 455 | Mod range: roughly 0.2–2 times the character's default |
| Slow-motion speed | 0.15–0.55 / 0.05 | 0.25 | Stock slider limits; displayed as 15–55% |
| Grind assistance | 0.05–1 / 0.05 | 0.8 | Stock slider and settings-save default; displayed as 5–100% |
| Grind detection size | 5–70 / 5 | 35 | Mod range up to twice the stock trace half-width; multiplied by assistance |
| Balance difficulty | 0.5–3 / 0.5 | 1 | Stock slider and settings-save default |
| Base balance drift | 0–250 / 5 | 155 | Mod range below the lowest native drift cap (555 × 0.5 = 277.5) |

Stock limits are taken from the shipped UI; ranges marked **Mod range** are
bounded customization choices, not claims about limits supported by the developer.
The default acceleration in the mod's config remains 1.25; 1 is unmodified.

Gravity uses the current map's initialized `WorldGravityZ` physics value. The
positive character `Gravity` field (stock 1355) is used only by
`CalculateJumpTime` and `CalculatePeakJumpHeight`; changing that field alone
does not change physics. The new slider updates physics and jump prediction
together, captures a fresh baseline on map travel, and restores the original
values on Reset. It affects local world physics, including ragdolls, and is not
enforced on other multiplayer peers. UE's gravity-cache behavior is documented
in [AWorldSettings](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/AWorldSettings).
Automated checks cover scaling, no compounding, respawn, travel, save/load and
reset. Actual in-game gravity/airtime acceptance remains pending.

## Removed misleading controls

- Raw casual/sprint acceleration had a 20,000 ceiling although the character's
  defaults are **85,555 / 105,555**. The shared acceleration multiplier handles
  this without exposing large force values or competing overrides.
- `JumpVelocity` and `MaxJumpHeight` have no corresponding character-property
  accesses in the decoded character Blueprint. The old menu advertised them as
  working controls without evidence.
- `SteerMultiplier`, `SpinMultiplier`, `FlipMultiplier`, `GrabSpinSpeedDivider`,
  `BalanceDriftIncrease`, and `BalanceDriftStrength` are written by gameplay
  logic. A periodic settings override fights those state changes.
- `MaxSpinSpeed` is changed during gameplay and reset to 355 on landing. It needs
  a separate implementation before it can be a reliable persistent control.
- The removed Camera tab's fields are also removed from saved-menu validation,
  so hidden camera overrides cannot linger in menu presets. Slow-motion speed
  is available under Tricks.

The broader manual `config.lua` remains an advanced override interface, including
legacy experimental fields. Those fields are not validated gameplay menu options.

## Existing presets and reset

On loading a menu preset, retired keys are ignored, valid values snap to the
nearest step, and finite out-of-range values recover to the stock value above
rather than jumping to the new maximum. Non-numeric and non-finite values are
rejected. The original preset file is untouched until Save; Save keeps `.bak`.

For example, jump scale 3000 becomes 1, assistance 10000 becomes 0.8, and flip
rate 1914 becomes 455. Acceleration 3.067565 becomes 3.05. The same validation
applies to supported numeric fields loaded from `config.lua`.

Reset restores the pre-mod snapshot if it is in range. An out-of-range snapshot
recovers to the audited stock value. The menu displays RESET for an out-of-range
live value rather than pretending the slider's clamped position is that value.
Restart the game after installing this script update; F8 only reloads settings.

## Verification

Automated Lua checks cover the stock values and step grids, percentages and
multipliers, rejecting infinities/NaN, old preset migration, save backups,
mouse snapping and jitter, no-write menu opening, and live API reset behavior.
These checks and Blueprint inspection do not replace an in-game feel test.
