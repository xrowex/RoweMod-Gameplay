# RoweMod 0.5.8 - install and play

1. Extract the entire ZIP to a normal folder. Close Rollout and RoweMod Online.
2. Double-click **install.cmd**. It finds the Steam game, installs the bundled tested UE4SS runtime, and installs RoweMod. If Windows needs administrator access to the game folder, accept the installer prompt. The skeleton body is included too. No separate UE4SS, Python, or body download is needed.
3. Launch Rollout from Steam, load a park, and press **F5**.
4. Gameplay changes apply live. **Save Settings** keeps them for next time.
5. Open Multiplayer. Steam connects and searches for friends automatically. The host loads a park and chooses **Host > Host Session**. Friends choose **Join Session**; their game loads the host's park automatically. Each player needs their own Steam account and copy of Rollout.

Select **Skeleton** under the game's **Character customization > Body** menu. Existing users get the body through the same automatic update, after closing the game and companion.

You can also use **START ONLINE.cmd** for the desktop browser and launcher. The hidden in-game companion closes automatically after Rollout exits; the visible desktop companion stays open until you close it.

**Automatic updates:** each game launch checks stable releases on GitHub. A newer release is downloaded and checked, then installed only after Rollout and RoweMod Online close. Settings and other mods are preserved, and replaced files are backed up under `%LOCALAPPDATA%\RoweMod\Backups`. An offline check never prevents playing. See `docs/auto-updates.md` for status and recovery.

This package includes UE4SS 3.0.1 Beta #0, commit f6d5f942, pinned to the runtime tested with these mods. Local tests cover LAN movement and sustained four-player relay simulation. Players have tested internet lobbies; this relay fix still needs a live four-player retest.

Check these in order:

- Open Multiplayer: Steam should start automatically. Host/join actions chosen during startup should complete when ready, including if you close the menu.
- Switch to Movement and back to Multiplayer several times. The session name and lobby-ID drafts should remain, without a crash. This exercises the repaired widget lifecycle; native crash acceptance still needs a real game test.
- With four people in one lobby, each player should see three independent remote skaters. Take turns moving while the other three stand still, including the host. Repeat with a late joiner.
- One player stands still while the other moves/jumps; the standing player stays independent.
- Switch roles and repeat, then change a stock outfit/boots and check both views.
- Join while in different stock parks: only the joiner should load the host's park. Then change the host's park and check that the joiner follows once, without a reload loop. Automatic loading supports Outdoor Skatepark, The Big Hall and Observatory; custom maps/assets are not downloaded.
- Test a grind and a fall after arrival. Skater sync should resume after the joining player's pawn has spawned.
- Leave and rejoin. There should be one skater per player, with no stuck copies.

Use stock outfits for the first connection test. Custom clothes only work when
the same assets are installed on both PCs; this mod does not transfer asset files.

If joining fails, report the browser's exact status message. For connected-but-
invisible players, enter `rowemod mp status` in the F10 console on both PCs.
Local diagnostics are in `%TEMP%\RoweModMP\Steam\steam_status.json` (per-origin receive/send counters and Steam send results), `visibility.txt` in the same folder (per-player pose, map and asset errors), and the game's
`ue4ss\UE4SS.log`. Nothing is uploaded automatically.

For a startup failure, also include the exact in-menu error or `%TEMP%\RoweModMP\Steam\online-error.txt` if that file exists. If the game crashes again, include the matching UE4SS log and crash report; the generic Fatal error dialog alone cannot identify the cause.

Public sessions and Steam overlay Join Game are also implemented; test those
after the browser/direct-ID connection works. The host must keep playing and
keep the companion open. Host migration and dedicated servers are not included.

Full implementation notes: `docs\steam-online.md`.
