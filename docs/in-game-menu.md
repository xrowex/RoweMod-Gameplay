# RoweMod in-game menu

Press **F5** in Rollout to open or close the menu. You can also enter `rowemod menu` in the console.

The pause menu also gains a **ROWEMOD** button using Rollout's installed small-button widget. It opens the same menu over the pause screen; closing with F5 or controller B returns focus to that button and leaves the game paused. F5 remains available if a game update changes the stock pause layout. The new pause entry still needs native in-game acceptance.

Movement, Tricks, and Balance contain live gameplay controls. Load a park before editing. Use the mouse, or arrows and Enter. D-pad/A navigation and B to close are also implemented; controller acceptance is still pending. Select **Save Settings** to keep changes across launches. Each setting has a Reset button; **Reset This Page** restores the values captured before RoweMod overrides. Reset does not save until you choose Save Settings.

Saved settings are data in `%LOCALAPPDATA%\RoweMod\gameplay-settings.txt`; the last successful save is kept as `.bak`. They override `config.lua` on launch and F8 reload. No game asset files are redistributed: the native UMG menu references Rollout's installed Quantico font.

Sliders use audited ranges and snap to their displayed increments. Hover for range and stock value. Acceleration is a multiplier, while jump scale, grind assistance, vibration and slow-motion speed display percentages. Lower jump steering resistance means stronger steering. Excessive values from old presets recover to stock values; retired runtime-state and hidden camera controls are ignored. [Full slider audit](slider-audit.md).

**Movement > Gravity** ranges from **0.25x to 2.00x** in 0.05 steps. 1.00x is the map's original gravity; lower values give longer airtime. It changes local world physics and keeps the character's jump predictions in sync. Friends retain their own settings. Use Reset to restore the map's original gravity, and Save Settings to retain your multiplier across launches.

On **Multiplayer**, Steam starts automatically. The **Join** view finds friends and refreshes while visible. Switch to public sessions with Show Public; Join With a Code expands the optional code field. The **Host** view contains a session name, a friends/public visibility toggle and one Host Session action. Once in a session, only session information and Leave Session are shown, with the session code available on demand.

Choose Join Session and the game loads the host's stock park automatically. Subsequent host park changes are followed too. Supported parks are Outdoor Skatepark, The Big Hall and Observatory. Loading progress and failures appear in the online status area; a failed or timed-out load offers Retry Map Load. The menu closes before travel to release input and widget references. Ghost sync resumes only after arrival and player spawn. Custom maps/assets are not downloaded.

Host/join actions selected during Steam startup are completed automatically, including after closing the menu. Connection failures remain visible with a retry action and a 30-second startup timeout. Detailed companion startup errors are in `%TEMP%\RoweModMP\Steam\online-error.txt`. Leaving disconnects the game from the session. The hidden companion exits after the game closes; a manually opened desktop companion stays open until closed.

The redesigned native layout and two-PC automatic map transitions still need in-game acceptance; automated tests cover the navigation, queued actions, widget lifetime and map-loading state machine.

The UMG construction approach was informed by [ue4ss-ModMenu](https://github.com/mattdavida/ue4ss-ModMenu), MIT licensed. See [license](licenses/ModMenu.txt).

## Player list and diagnostics

F5 > Multiplayer shows the installed RoweMod version and a live player list during a session. The host and your own skater are marked. Remote status distinguishes connecting, waiting for poses, loading/another map, avatar failure, interrupted poses and an active avatar. These describe the local game's state; "Avatar active" is not a promise that the player is inside your camera view.

Player names, health, parks and counts update in place, including players joining or leaving. Session metadata also updates without rebuilding its buttons. When the list of available sessions changes, selection follows the same session ID and scroll position is retained. If the selected session disappears, focus returns to the Multiplayer tab instead of selecting another Join button.

Use **Copy Diagnostics** in the Help card to copy a bounded report from the running Steam companion. It includes local role/map, per-player traffic, pose application and avatar errors. Account IDs, display names and the session code are omitted or replaced with player aliases. Nothing is uploaded. If the clipboard is unavailable, the report is saved as `%TEMP%\RoweModMP\Steam\diagnostics-copy.txt`. A running Steam companion is required; a failed Steam startup still uses the startup error shown in the menu.
