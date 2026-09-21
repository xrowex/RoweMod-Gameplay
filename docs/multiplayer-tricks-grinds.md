# Multiplayer: syncing tricks & grinds

Research notes for adding **remote-visible tricks and grinds** to Rollout Inline via UE4SS (RoweMod Gameplay). Not an implementation plan with dates — a map of what the game actually is, what we already know, and what still has to be reverse-engineered before any netcode is worth writing.

## Verdict

Rollout Inline ships as **single-player only** (Steam feature list: Single-player, Steam Cloud). There is **no native actor replication, lobby, or OnlineSubsystem session flow** for skaters. A multiplayer mod is not “turn on replication for grind state” — it is **build a parallel networking stack**, then drive **ghost skaters** from synced state.

Tricks and grinds are the hard part: they are continuous, physics-coupled, dual-stick, and almost certainly owned by `NewMainCharacter` + its animation graph. Cosmetics (RoweMod clothing overlays) are orthogonal and already solvable without networking.

## What this repo already touches

`ue4ss/Mods/RoweModGameplay` only mutates **feel multipliers** on the local pawn after spawn:

| Field | Role (inferred) |
|---|---|
| `CasualSpeedIncrease` / `SprintSpeedIncrease` | Ground push speed |
| `MaxLinearForce` / `MaxAngularForce` | Physics force caps |
| `Gravity` / `SlomoSpeed` | World / time feel |
| `MaxSpinSpeed` / `MaxFlipSpeed` | Air rotation caps (dump list only) |
| `JumpVelocity` / `MinJumpHeight` | Jump (dump list only) |
| `GrindMagnetStrength` | How hard the skater snaps to rails |
| `BalanceIntensity` | Grind balance difficulty |

`rowemod dump` already probes those names. None of them are a grind *stance*, trick *id*, or combo string — they are tuning knobs. Syncing them alone would not make remote players look like they are grinding.

Clothing lives in a separate kit ([RoweMod-Rollout](https://github.com/xrowex/RoweMod-Rollout)): IoStore overlay of `DT-upper` etc. Engine is **UE 5.4.4**, skeleton `main-rig` (87 bones). That matters for remote mesh attach, not for grind logic.

## Game systems that matter for sync

From Steam / play descriptions + property names:

1. **Riding** — momentum physics on wheels (linear/angular force, gravity).
2. **Dual-stick grinds** — each stick ≈ one foot; stance can change mid-rail; optional balance meter (`BalanceIntensity`).
3. **Cess slides / stalls / manuals** — stick-driven stance variants (likely same grind FSM or a sibling).
4. **Air** — free spin/flip (`MaxSpinSpeed` / `MaxFlipSpeed`), grabs, handplants.
5. **Ragdoll / bail** — failure state that must be visible remotely.
6. **Replay editor** — strong signal that the game already records a stream of pose/state somewhere; worth hunting as a sync template.

Until we have a CXX / live property dump mid-grind, treat the above as **systems to find**, not confirmed class names.

## What is missing (must dump from a live game)

Run UE4SS on a Steam install after loading a map and performing a grind + air combo. Use:

- **CXX headers** (`Ctrl+H`) — search `NewMainCharacter`, anything with `Grind`, `Rail`, `Trick`, `Grab`, `Balance`, `Combo`.
- **Object dump** (`Ctrl+J`) while on a rail.
- This mod: `rowemod dump` (scalars) and **`rowemod recon`** (full reflected props + UFunctions on the pawn).

### A. Skater pawn surface

Find on `NewMainCharacter` / related components:

| Category | What to look for | Why |
|---|---|---|
| Mode / FSM | enums like `EGrindState`, `bIsGrinding`, `MovementMode` | Discrete transitions to send reliably |
| Stance | foot L/R stick vectors, grind type name/id | Dual-stick → remote pose |
| Rail attach | rail actor ref, spline distance/alpha, magnet | Snap ghost to same ledge |
| Balance | meter 0–1, fail threshold | Visual + bail sync |
| Air tricks | grab enum, spin/flip deltas, montage name | Air look without full physics |
| Velocity / transform | location, rotation, linear/angular vel | Baseline locomotion sync |
| Anim | AnimBP class, montage slots, curve names | Drive ghost without simulating physics |
| Score/combo | combo text, multiplier | Optional UI sync |

### B. World / rail actors

Find classes for grindables (rails, ledges, pool coping). Need a **stable id** clients share (actor name, level path, or spline GUID) so “grind start” packets can say *which* rail + *where* along it.

### C. Input path

Map Enhanced Input / axis bindings for:

- Left/right stick (feet vs steer — settings allow alternate spin binds)
- Jump / plant / grab buttons

Important: **do not plan to sync raw sticks as the primary remote driver** unless you also run full local physics on every peer (expensive, desync-prone). Prefer **state + sparse continuous params**.

### D. Animation / montage assets

List montages and AnimBP notifies fired on grind enter/exit, grab, plant, bail. Remote ghosts will likely:

1. Set transform/velocity from the wire, and
2. Play the same montage / set the same AnimBP variables,

instead of re-simulating magnet + balance.

### E. Replay subsystem (bonus)

If replay stores per-frame bone or state packets, that format may be the cleanest “authoritative timeline” to mirror over the network for ghosts.

## Networking reality check (UE4SS)

| Approach | Fit for Rollout |
|---|---|
| Enable Unreal `bReplicates` on stock pawns | **Won't work** — no GameMode/PlayerState/net driver setup for multiplayer sessions. |
| Pack networked Blueprint actors into IoStore | Possible later, but still needs a session host and ownership model the shipping game never had. |
| **External session + ghost puppets** (Steam P2P / custom UDP / relay) driven by UE4SS Lua or C++ | **Practical path** for a mod. |
| Local splitscreen (`CreatePlayer`) | Exists in stock UE4SS SplitScreenMod; same machine only — useful for testing dual pawns, not online. |

UE4SS can read/write reflected properties and call UFunctions. It cannot magically invent engine replication. Plan on:

1. **Host** (listen) opens a lobby (Steamworks or custom).
2. Each peer runs the full single-player game locally.
3. Mod spawns **non-possessed ghost pawns** (or cloned meshes) for remotes.
4. Local player broadcasts a compact state stream; remotes apply it to ghosts.

### Suggested wire model for tricks & grinds

**Reliable events** (order matters):

```
GrindEnter  { railId, splineT, stanceId, vel }
GrindUpdate { splineT, stanceId, balance, stickL, stickR }  // throttled
GrindExit   { reason: jump|end|bail, exitVel }
AirGrab     { grabId }
AirSpin     { yawRate, pitchRate }   // or cumulative deltas
Land        { success, stance }
Bail        { }
```

**Unreliable / high-rate:**

```
Transform { loc, rot, linVel, angVel, tick }
```

Tricks/grinds **must** use the reliable channel (or a sequenced reliable stream). Transform alone will look like a sliding mannequin during a grind unless stance/montage is also applied.

### Authority

Start with **each peer authoritative for their own skater** (typical skate sandbox). Host only arbitrates lobby/map. Do not try server-side physics validation until a lobby exists and cheats matter.

## Implementation layers (once dumps exist)

1. **Recon** — finish mapping pawn props/functions (this PR’s `rowemod recon` / watch).
2. **Ghost spawn** — second `NewMainCharacter` or skeletal mesh proxy; strip AI/input; hide local HUD for it.
3. **Locomotion sync** — transform + velocity at ~20–30 Hz; interpolate.
4. **Grind sync** — detect local enter/exit (property watch or function hooks); send events; on remote, attach to rail id + set stance vars / play montage.
5. **Air / grab sync** — same pattern for grab enum + spin rates.
6. **Session** — Steam P2P or LAN; map agreement; clothing row ids (reuse Gallery ids).
7. **Polish** — lag compensation on grind attach, bail reconciliation, mute remote audio duplicates.

Clothing sync can reuse RoweMod row names (`DT-upper` keys) as opaque ids — separate from tricks.

## Risks

- **Physics desync**: magnet + balance + dual-stick will never match across machines if you only sync sticks. Ghost = state playback.
- **Rail id instability**: streamed/level-instance actors may need hashed level path + component index.
- **Blueprint-only logic**: grind may live entirely in BP graphs with poor Lua hook points → need C++ UE4SS mod or AnimBP notify sniffing.
- **Anti-annoyance**: README already warns not to harass others if official MP appears; keep lobbies opt-in.
- **Piracy / fake “community multiplayer” builds**: ignore untrusted redistributions claiming LAN/P2P; research against the Steam build only.

## Implementation status

Shipped in this repo (experimental):

1. **Recon** — `rowemod recon` / `watch` (F7 / F6).
2. **Ghost + sync loop** — `Scripts/mp/*` captures local transform + grind/trick edges, writes a mailbox, applies remote packets to ghost pawns.
3. **LAN bridge** — `tools/rowemod_mp.py` (UDP host/join) + `mp_host.cmd` / `mp_join.cmd`.
4. **Howto** — [multiplayer.md](multiplayer.md).

Still needs a live `rowemod recon` pass to lock real property names in `config.lua` → `mp.props`. Ghost spawn may need tweaking per UE4SS build.

## Immediate next actions (on a machine with the game)

1. Install UE4SS + this mod; load a map with a long rail.
2. `rowemod recon` → save log.
3. Enter a grind, switch stance mid-rail, bail once, land a grab → `rowemod watch` (see below) and CXX dump.
4. Grep dumps for `Grind`, `Rail`, `Balance`, `Grab`, `Trick`, `Combo`, `Montage`.
5. Fill the tables in section “What is missing” with real property/function names.
6. Only then prototype GrindEnter/Exit packets between two local processes (loopback).

## Out of scope for “tricks & grinds sync”

- Full game of SKATE ruleset
- Dedicated servers / matchmaking scale
- Replacing official future multiplayer
- Shipping ripped maps or exe packages
