# Multiplayer (tricks & grinds)

Experimental LAN sync for Rollout Inline via UE4SS. Each player runs the full single-player game; a small Python bridge shuttles state; the Lua mod drives **ghost skaters**.

## Quick start (two PCs on the same LAN)

1. Install this mod (`install.ps1`) on both PCs. You need **Python 3** on both.
2. **Host** (PC A), from this repo:

```bat
tools\mp_host.cmd
```

3. **Join** (PC B), using PC A’s LAN IP:

```bat
tools\mp_join.cmd 192.168.1.10
```

4. Launch the game on both PCs, same map. Press **F9** (or `rowemod mp on YourName`).

You should see a ghost for the other player. Transforms stream continuously; grind enter/update/exit, grabs, and bails go on the reliable path when the matching pawn properties resolve.

## What syncs

| Channel | Contents |
|---|---|
| Transform (~20 Hz) | Location, rotation, velocity |
| Grind | Enter / update (stance, balance, spline T) / exit |
| Air | Grab id changes |
| Bail | Ragdoll flag edge |

Property names are **guessed** in `config.lua` → `mp.props`. After `rowemod recon` / F7 mid-grind, put the real names first in that list so detection is reliable.

## Config

```lua
mp = {
    enabled = false,          -- or press F9 / rowemod mp on
    playerName = "skater",
    mailboxDir = nil,         -- default %TEMP%/RoweModMP — must match the bridge
    transformHz = 20,
    props = { ... },
}
```

If you set a custom `mailboxDir`, pass the same path to the bridge:

```bat
python tools\rowemod_mp.py host --mailbox D:\tmp\RoweModMP
```

## Architecture

```
Game (UE4SS Lua)  ↔  %TEMP%/RoweModMP mailbox  ↔  rowemod_mp.py (UDP)  ↔  peer
```

UE4SS Lua has no sockets, so the bridge is required. Details and wire format: [multiplayer-tricks-grinds.md](multiplayer-tricks-grinds.md).

## Limits (honest)

- Opt-in LAN only — not matchmaking, not anti-cheat.
- Ghost spawn depends on `SpawnActor` / fallback `CreatePlayer`; if ghosts fail, check the UE4SS log.
- Until grind bool/stance props are confirmed, grind packets may not fire (transform still will).
- Do not use this to harass anyone; lobbies are manual.

## Dev

```bat
python tests\test_mp.py
python tools\rowemod_mp.py loopback
```
