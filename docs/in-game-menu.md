# RoweMod in-game menu

Press **F5** in Rollout to open or close the menu. You can also enter `rowemod menu` in the console.

Movement, Tricks, and Balance contain live gameplay controls. Load a park before editing. Use the mouse, or arrows and Enter. D-pad/A navigation and B to close are also implemented; controller acceptance is still pending. Select **Save Settings** to keep changes across launches. Each setting has a Reset button; **Reset This Page** restores the values captured before RoweMod overrides. Reset does not save until you choose Save Settings.

Saved settings are data in `%LOCALAPPDATA%\RoweMod\gameplay-settings.txt`; the last successful save is kept as `.bak`. They override `config.lua` on launch and F8 reload. No game asset files are redistributed: the native UMG menu references Rollout's installed Quantico font.

On **Multiplayer**, choose **Start Steam Connection** once. The existing Steam companion runs in the background. Then host friends/public, find friends, browse public sessions, or join a lobby ID. Status includes your lobby ID, player count, and map. Both players need matching mods and the same map. Leave Session disconnects the game and leaves the Steam lobby; the background companion stays available until Rollout closes, then exits to allow updates. The desktop Online launcher can still show its window.

The UMG construction approach was informed by [ue4ss-ModMenu](https://github.com/mattdavida/ue4ss-ModMenu), MIT licensed. See [license](licenses/ModMenu.txt).
