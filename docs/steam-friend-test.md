# RoweMod 0.5.1 - install and play

1. Extract the entire ZIP to a normal folder. Close Rollout and RoweMod Online.
2. Double-click **install.cmd**. It finds the Steam game, installs the bundled tested UE4SS runtime, and installs RoweMod. If Windows needs administrator access to the game folder, accept the installer prompt. No separate UE4SS or Python download is needed.
3. Launch Rollout from Steam, load a park, and press **F5**.
4. Gameplay changes apply live. **Save Settings** keeps them for next time.
5. For multiplayer, open the Multiplayer tab, choose **Start Steam Connection**, then **Host Friends** or **Find Friends** and Join. Both players load the same map and need their own Steam account and copy of Rollout.

You can also use **START ONLINE.cmd** for the desktop browser and launcher. The hidden in-game companion closes automatically after Rollout exits; the visible desktop companion stays open until you close it.

**Automatic updates:** each game launch checks stable releases on GitHub. A newer release is downloaded and checked, then installed only after Rollout and RoweMod Online close. Settings and other mods are preserved, and replaced files are backed up under `%LOCALAPPDATA%\RoweMod\Backups`. An offline check never prevents playing. See `docs/auto-updates.md` for status and recovery.

This package includes UE4SS 3.0.1 Beta #0, commit f6d5f942, pinned to the runtime tested with these mods. The menus and independent LAN movement have been tested locally; the complete two-account internet test is still pending.

Check these in order:

- Both browsers show one remote skater and increasing receive counts.
- One player stands still while the other moves/jumps; the standing player stays independent.
- Switch roles and repeat, then change a stock outfit/boots and check both views.
- Test a grind, a fall, and a map change. Both players manually load the same map.
- Leave and rejoin. There should be one skater per player, with no stuck copies.

Use stock outfits for the first connection test. Custom clothes only work when
the same assets are installed on both PCs; this mod does not transfer asset files.

If joining fails, report the browser's exact status message. For connected-but-
invisible players, enter `rowemod mp status` in the F10 console on both PCs.
Local diagnostics are in `%TEMP%\RoweModMP\Steam\steam_status.json` and the game's
`ue4ss\UE4SS.log`. Nothing is uploaded automatically.

Public sessions and Steam overlay Join Game are also implemented; test those
after the browser/direct-ID connection works. The host must keep playing and
keep the companion open. Host migration and dedicated servers are not included.

Full implementation notes: `docs\steam-online.md`.
