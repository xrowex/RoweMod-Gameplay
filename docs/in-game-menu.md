# RoweMod in-game menu

Press **F5** in Rollout to open or close the menu. You can also enter `rowemod menu` in the console.

Movement, Tricks, and Balance contain live gameplay controls. Load a park before editing. Use the mouse, or arrows and Enter. D-pad/A navigation and B to close are also implemented; controller acceptance is still pending. Select **Save Settings** to keep changes across launches. Each setting has a Reset button; **Reset This Page** restores the values captured before RoweMod overrides. Reset does not save until you choose Save Settings.

Saved settings are data in `%LOCALAPPDATA%\RoweMod\gameplay-settings.txt`; the last successful save is kept as `.bak`. They override `config.lua` on launch and F8 reload. No game asset files are redistributed: the native UMG menu references Rollout's installed Quantico font.

Sliders use audited ranges and snap to their displayed increments. Hover for range and stock value. Acceleration is a multiplier, while jump scale, grind assistance, vibration and slow-motion speed display percentages. Lower jump steering resistance means stronger steering. Excessive values from old presets recover to stock values; retired runtime-state and hidden camera controls are ignored. [Full slider audit](slider-audit.md).

**Movement > Gravity** ranges from **0.25x to 2.00x** in 0.05 steps. 1.00x is the map's original gravity; lower values give longer airtime. It changes local world physics and keeps the character's jump predictions in sync. Friends retain their own settings. Use Reset to restore the map's original gravity, and Save Settings to retain your multiplier across launches.

On **Multiplayer**, choose **Start Steam Connection** once. The existing Steam companion runs in the background. Then host friends/public, find friends, browse public sessions, or join a lobby ID. Status includes your lobby ID, player count, and map. Both players need matching mods and the same map. Leave Session disconnects the game and leaves the Steam lobby; the background companion stays available until Rollout closes, then exits to allow updates. The desktop Online launcher can still show its window.

Wait for **Steam ready** before hosting or browsing; this means the Steam companion is ready, not that another skater has joined. Startup errors are shown in the menu, and a launch without a response times out after 30 seconds. A failed background startup records details in `%TEMP%\RoweModMP\Steam\online-error.txt`. Tab changes now save text drafts and release widget references before detaching the old page; returning no longer reads the detached text boxes. Regression tests cover that lifetime ordering, but the reported native crash still needs retesting in-game.

The UMG construction approach was informed by [ue4ss-ModMenu](https://github.com/mattdavida/ue4ss-ModMenu), MIT licensed. See [license](licenses/ModMenu.txt).
