# Multiplayer (experimental LAN)

For Steam friends and online sessions, see [Steam online](steam-online.md).

Host/join multiplayer for Rollout Inline through UE4SS and a local Python UDP bridge. Each connection owns one skater. Remote skaters use the sender's visible meshes, materials and bone poses, including the body, clothes, boots, wheels and accessories.

## Start playing

Install the current mod on both PCs. Both need the same game assets and any custom clothing packs; the connection sends asset references, not clothing files. Protocol v3 requires matching bridge and Lua versions.

Same PC, two game windows:

```bat
tools\mp_dual_local.cmd
```

Two PCs on the same LAN:

```bat
tools\mp_host.cmd
tools\mp_join.cmd <host-lan-ip>
```

Load the same map in both windows. Press **F10**, enter `rowemod mp on`, then Enter **in each game**. `rowemod mp status` only reports status; it does not connect. A connected session should report `ok=true peers=1 connected=1`.

F9 also toggles multiplayer, but console commands are easier to target when two game windows share one PC. The launcher gives each process a separate mailbox and tells Unreal to accept controller input only in the focused window. Initial spawn points can overlap; skate apart to see each other.

The dual launcher uses a unique `%TEMP%\RoweModMP\run-<id>` folder with A/B mailboxes and bridge logs. After closing both games, `tools\mp_stop_local.cmd` stops that run's bridges. Steam's library button may refuse a second instance, so the launcher starts the shipping executable directly.

## What is synchronized

- Independent per-connection identity, even when players use the same display name.
- Sender-owned body, shirt, pants, boots, wheel meshes and visible accessories.
- Material scalar, color and texture overrides, including outfit changes during a session.
- World transforms and component-space bone poses. Remote animation comes from that player, rather than running the receiving player's animation Blueprint.
- Host session map, per-peer map gating, disconnect cleanup and reconnection.

The host relays client poses while preserving their source identity. Only the host can announce the session map. Each local game continues to simulate its own player; remote avatars do not take input, own a camera, or run character physics.

## Smoothing

Capture targets up to 20 pose updates per second; actual frequency depends on game-thread load. A separate native game-thread timer requests remote rendering every 16 ms. A 120 ms buffer interpolates component positions, scale and bone rotations between received poses. Quaternion interpolation takes the shortest rotation path.

Animated clothing parameters such as `WindDirection` and `RippleHeight` update existing materials without rebuilding the skater or resetting interpolation. Model/mesh changes still replace the remote geometry.

Missing packets hold the latest available pose. Large teleports, long gaps and outfit replacement reset the buffer. This avoids extrapolating a skater through the park. The buffer delays only the remote representation, not local controls.

Matching body/clothing rigs can share Unreal leader-pose transforms, reducing repeated bone writes. Each part retains its own mesh, material and world transform, and parts with different bone poses detach and update independently. Bone-name handles are cached by mesh. Both live game instances report three shared-pose parts, and the user confirmed the result is smooth enough during play. It cannot compensate for low game FPS or prolonged network stalls.

## Commands and maps

| Command | Effect |
|---|---|
| `rowemod mp on` / `off` | Connect or remove remote avatars |
| `rowemod mp status` | Connection and map status |
| `rowemod mp reload` | Stop and reload MP scripts; follow with `rowemod mp on` |
| `rowemod mp map` | Show current/session maps |
| `rowemod mp map ParkName` | Host requests the session map |
| `rowemod mp travel ParkName` | Travel to a named map |
| `rowemod mp inspect on` / `off` | Toggle position and frame/render diagnostics |
| `rowemod mp avatar` | Write local mesh/material census to the mailbox |

Manual loading through the game's map menu is the most reliable travel path. Automatic travel is optional (`mp.autoTravelToHostMap`); packaged level path resolution can fail. Sync is gated by map name, with different-map peers excluded individually.

## Architecture and limits

```text
Local possessed pawn -> captured appearance/pose -> mailbox -> UDP host relay
Remote peer packets -> map/sequence validation -> passive mesh actor -> interpolation
```

Remote avatars are native Actors with PoseableMeshComponent/StaticMeshComponent parts. No duplicate player Blueprint is spawned. Native persistent game-thread timers keep all engine object access on the game thread and avoid the async Lua registry transfers involved in the reported UE4SS crash.

The data-only codec rejects malformed, oversized and nonfinite values. The bridge compresses and fragments pose frames, bounds reassembly, expires incomplete packets, checks source endpoints, and preserves per-connection UUIDs. This is a trusted-LAN prototype without matchmaking, encrypted sessions, shared world physics, player collisions, shared scoring or authoritative cheat prevention. Two players have been exercised in-game; the host's seven-client limit is not a tested performance claim.

Clothing assets must exist on both installations. Missing assets produce a diagnostic and a throttled retry; they are not downloaded. Actual grind, grab and ragdoll bone poses travel in the same frame stream, but full trick-by-trick visual fidelity still needs gameplay coverage. Legacy discrete trick packet helpers remain for the older proof harness and are not the current avatar renderer.

## Verification (2026-09-21)

The user confirmed that each skater moves independently and that an outfit change appears remotely. Two live game processes displayed separate avatars with different shirts; body models and boots were visible. Both processes reconnected after loading interpolation; each receiver created one eight-part remote avatar, and the render counter advanced faster than the received frame counter. After fixing animated-material rebuilds and enabling shared skeleton poses, the user confirmed: "Smooth enough now." See [the validation record](proofs/avatar-20260921/report.json).

The earlier crash repair and controlled position tests are retained under [proofs/crash-repair-20260921](proofs/crash-repair-20260921). Current tests cover identity/relay authority, fragmented packet recovery, malformed poses, independent avatar ownership, outfit replacement, reconnect cleanup, mailbox reload history, and interpolation including shortest-path rotation and teleports.

```bat
python -m unittest discover -s tests -v
tools\mp_prove.cmd
```

Lua 5.4 checks (from the repository root): `tests/test_game_thread.lua`, `tests/test_ghost.lua`, `tests/test_avatar_codec.lua`, `tests/test_interpolate.lua`, `tests/test_avatar_materials.lua`, `tests/test_avatar_shared_pose.lua`. `tests/test_mailbox.lua` also takes an empty temporary directory as its first argument. Python packet proof alone does not prove rendered gameplay.

## Open-source references

[Multivoid](https://github.com/VOTV-MP/Multivoid) is an MIT multiplayer mod for Voices of the Void and a useful example of a game-specific Unreal integration. [Valve GameNetworkingSockets](https://github.com/ValveSoftware/GameNetworkingSockets) is a BSD networking library that could replace the transport layer. Neither is integrated here, and neither automatically supplies Rollout's player/model integration. The current implementation still uses the Python UDP bridge.
