# Steam online integration

Status: first Steam implementation built and installed on 2026-09-21. The
standalone browser, private lobby lifecycle, Steam API initialization and game
startup have been checked locally. Two-account internet gameplay is awaiting
the friend test. This is an experimental test build, not a completed online
acceptance result.

Revision 2 also publishes an immediate host map request when the host leaves
the menu for a park. It repairs sessions where a joiner retained `StartMenu`
as its target after the host had already loaded a skating map.

Revision 3 queues gameplay hotkey actions for a persistent game-thread dispatcher.
On the tested UE4SS build, keys and delayed player-restart actions no longer
register transient ExecuteInGameThread callbacks during pose capture. This
addresses the callback-registry failure seen when pressing Numpad +. Local
regression coverage exercises bursts, delay, and recovery after action errors;
this is separate from two-account online acceptance.

## Play with a friend

Both players need Windows x64, Steam running under different accounts that own
Rollout Inline, the same game version, UE4SS, and this matching mod package.
The packaged launcher includes its runtime; Python is not required.

1. Extract the complete test ZIP. Close the game and run `install.cmd`.
   Existing mod files are backed up under `%LOCALAPPDATA%\RoweMod\Backups`.
   The tested UE4SS runtime is included and installed automatically.
   For the in-game browser, launch from Steam and use F5 > Multiplayer.
2. Open `START ONLINE.cmd` in the package, or `tools\mp_online.cmd` in a source
   checkout with a built launcher. Keep the companion window open while playing.
3. Host: leave **Friends only** selected and click **Host session**.
   Friend: click **Friends**, select the host, then **Join selected**.
   **Copy my lobby ID** and **Join ID** provide a direct fallback.
4. Both click **Launch Rollout** and load the same map. Multiplayer starts
   automatically for this launch. Close old LAN game windows first.
5. Confirm one remote skater, independent movement, outfit/boot changes and smooth
   movement. Begin with stock outfits, then test custom packs installed on both PCs.

For public sessions, choose **Public** before hosting. Others use **Public
sessions** to search compatible rooms. The browser shows session name, map and
player count. Sessions end when the original host leaves; there is no host migration.

In a normally launched game, `rowemod mp online` opens the companion and switches
that game to the Steam mailbox. `rowemod mp online <lobby-id>` requests a join.
`rowemod mp status` reports the game side of the connection. After updating the
mod, restart the game once so the new console command is registered.

Steam overlay join callbacks, rich-presence `Join Game`, and cold launch
`+connect_lobby` handling are implemented. The browser/direct-ID path is the
first test path; overlay delivery and cold launch still need a real friend test.

## Local evidence

`tools/steam_probe.py` initialized against Rollout Inline App ID 4464990 using
the locally installed Unreal Steamworks redistributable. Steam reported the
correct App ID, a logged-on user, accessible matchmaking/networking interfaces,
authentication availability 100 (Current), and relay availability 100 (Current).
The machine's DLL exposes SteamUser v021 although its nearby headers describe
v023; the probe supports the stable flat login query with either version.

See [probe result](proofs/steam-probe-20260921.json). This did not create a lobby,
send invitations, or establish a connection to another account. Initialization
and relay readiness do not prove a complete internet gameplay session.

To repeat with your own locally installed Steamworks redistributable:

```powershell
python tools/steam_probe.py --steam-api 'path\to\steam_api64.dll'
```

The tracked source does not include Valve binaries. The standalone test launcher
bundles the local `steam_api64.dll` redistributable and Python/Tk runtime. Source
launches require 64-bit Python with Tk and either `ROWEMOD_STEAM_API` pointing to
that DLL or `tools/deps/steam_api64.dll`. `tools/build_online.ps1` builds the
standalone executable using PyInstaller.

The later [native check](proofs/steam-native-20260921.json) created a private
lobby, read matching metadata, confirmed its owner/member count and left it.
A same-account self-send delivered bytes but produced Steam SDK pipe assertions;
it is not a valid two-peer connection test. The normal bridge excludes self
connections. The native check and public session search sent no friend invitations.

## Implemented transport

- Host a friends-only or public Steam lobby, with session name, map, player
  count, mod identifier and protocol version stored as lobby metadata.
- Join a friend's compatible lobby, accept Steam overlay join requests, and
  support cold-start `+connect_lobby` routing to the bridge.
- Browse public mod sessions using Steam lobby filters. These are player-hosted
  sessions; an always-running dedicated server is a separate feature.
- Use SteamNetworkingMessages P2P sessions for gameplay, with Steam relay
  fallback. Keep the existing avatar codec, mailbox and smoothing layer.
- Use reliable messages for session control and unreliable messages for
  replaceable movement. Appearance is included in repeated complete avatar frames,
  so a dropped frame does not permanently lose an outfit change. Full-pose
  bandwidth and fragmentation still need measurement on an internet connection.
- Bind peer identity to the authenticated Steam connection and lobby membership,
  rather than trusting the UUID inside a received packet. Limit message sizes,
  decompression, rates and peer counts before forwarding data to Lua.
- Require matching protocol/game content. Show actionable failures for full
  sessions, incompatible versions, wrong maps and failed connections.
- End the session cleanly when the host leaves. Host migration is deferred.

The companion owns Steam callbacks on its UI thread. A local instance lock and
request mailbox route additional launches to the existing companion. The game
bootstrap forwards numeric lobby launch arguments to the installed companion.
The existing LAN launchers remain available separately.

## Diagnostics

`%TEMP%\RoweModMP\Steam\steam_status.json` contains lobby, role, packet counters
and the last status message. It also records per-origin received poses, sent poses, deferred sends, rate-limit drops and numeric Steam movement-send results. `visibility.txt` in the same directory records every known player, last-pose age, applied pose count and map/asset errors, including players without an avatar. These files remain local. `game_status.txt` records game startup; the in-game
status command shows current state. Game errors remain in `ue4ss\UE4SS.log`.
No log files, Steam account identifiers or private lobby IDs are included in the
friend test ZIP. No port-forwarding configuration is needed for the intended
Steam P2P/relay path, but successful internet routing is still an acceptance gate.

## Remaining live acceptance gates

1. Private lobby create/join/leave with two different Steam accounts.
2. Authenticated host/client data exchange between two PCs on different networks,
   including a relayed connection, without manual port forwarding.
3. Friend joining and the public lobby browser, including filtering incompatible
   sessions and handling a game that is not already running.
4. Independent movement, clothing/boot changes, map gating and smoothing under
   measured latency and packet loss; reconnect and host shutdown cleanup.

Two game windows on one Steam account remain useful for LAN tests but cannot
establish the two-account Steam acceptance gate.

## Primary references

- [Steam matchmaking and lobbies](https://partner.steamgames.com/doc/features/multiplayer/matchmaking)
- [Steam networking messages](https://partner.steamgames.com/doc/api/ISteamNetworkingMessages)
- [Steam Datagram Relay](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay)
- [Steam API initialization](https://partner.steamgames.com/doc/api/steam_api)
