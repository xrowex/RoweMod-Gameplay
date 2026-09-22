# RoweMod in-game menu: resource assessment

Inspected 2026-09-21. Research only; no UI framework installed or menu injected.

## Recommended direction

Build a RoweMod UMG panel using Rollout's existing font, textures, highlight
materials and controller glyphs by referencing assets in the installed game.
Use our own settings handlers, persistence and persistent game-thread dispatcher.
Treat complete stock widgets as candidates until their initialization and
settings callbacks have been inspected; instantiating a stock widget also runs
its Blueprint logic. Do not assume a reusable slider is behavior-free.

Target a RoweMod entry under the pause menu if its layout supports injection.
A separate F5 panel is the fallback (F6-F10 already have functions). Sections:
Movement, Jump & Tricks, Grinds & Balance, Camera, Online. Include current values,
reset for each setting, Save preset and Restore defaults. Controller focus,
mouse capture, input restoration and map-change cleanup are acceptance checks.

First implementation slice: one native-looking Speed row that changes the real
setting, persists on request, and opens/closes safely with mouse and controller.
Expand only after this works with multiplayer capture active.

## Assets verified in the current installed game

Verified read-only with retoc list against the game's Content/Paks directory,
including patch precedence. Asset paths below use Unreal's /Game mount.
Existence is confirmed; runtime construction and callback rebinding are untested.

| Role | Package path |
| --- | --- |
| Pause menu | /Game/MainFolder/UI/W-pause-main |
| Settings container | /Game/MainFolder/UI/W-settings |
| Gameplay page | /Game/MainFolder/UI/W-gameplay-settings |
| Setting slider | /Game/MainFolder/UI/modular/sliders/W-slider-setting |
| Large button | /Game/MainFolder/UI/modular/buttons/W-big-button |
| Small button | /Game/MainFolder/UI/modular/buttons/W-small-button |
| Title | /Game/MainFolder/UI/modular/W-ui-title |
| Border | /Game/MainFolder/UI/modular/W-UI-border |
| Font | /Game/MainFolder/UI/fonts/Quantico-BoldItalic_Font |
| Highlight material | /Game/MainFolder/UI/materials/halftones/MI-ButtonHighlight |
| Hover sound | /Game/MainFolder/Sounds/UI/button-hover/MS-button-hover |

Additional candidates in the local asset index: UI/Textures/controls/xbox and
ps5 glyphs, tiling-button-bg-texture and tiling-button-bg-glow-texture.
Local screenshot reference: C:/Users/xrowe/rolloutrowemod/dumps/game-stock-menu.png.
Its dark textured panels, slanted white type, purple accents and yellow focus
border provide a concrete visual reference. These assets would be resolved from
the player's game installation; no extracted game assets are added to this repo.

## Open-source references

- [ue4ss-ModMenu](https://github.com/mattdavida/ue4ss-ModMenu), MIT:
  Lua/UMG shell, tabs, numeric fields, checkboxes, dropdowns and JSON settings.
  Useful fallback or implementation reference. Its documented item types do not
  yet include sliders. Controller navigation is not established by this review.
  core/input.lua supports native game-thread polling and explicitly discusses
  the same "Ref was not function" callback lifetime failure seen locally.
  Review callback ownership before adopting; not tested in Rollout.
- [Mod Options Framework](https://github.com/Elvlin/Mod-Options-Framework), MIT:
  a strong example of adding a native-style mod page to an existing Esc menu.
  It is built for Palworld, so its game-specific integration is a reference,
  not a drop-in dependency for Rollout.
- [Epic UMG widget templates](https://dev.epicgames.com/documentation/unreal-engine/creating-umg-widget-templates-in-unreal-engine):
  documents reuse of User Widgets and per-instance behavior. Both appearance
  and scripted behavior carry over.
- [Epic UMG styling](https://dev.epicgames.com/documentation/unreal-engine/umg-styling-in-unreal-engine):
  styles for buttons, sliders and other native widgets.

UE 5.4 UnrealEditor-Cmd is available locally at
E:/unreal/UE_5.4/Engine/Binaries/Win64/UnrealEditor-Cmd.exe if we need a cooked
custom Widget Blueprint. Existing retoc and game mappings are also available.

## What remains unproven

Runtime creation of the stock widgets; safe settings event binding; insertion
into the pause menu; controller navigation; persistence; safe close/travel/reopen
while multiplayer capture is active. This resource survey does not establish
those behaviors and makes no change to the running game.
