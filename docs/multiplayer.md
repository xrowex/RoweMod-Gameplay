# Multiplayer (tricks & grinds)

Experimental LAN sync for Rollout Inline via UE4SS. Each player runs the full single-player game; a small Python bridge shuttles state; the Lua mod drives **ghost skaters**.

## Two clients on one PC

Yes — use separate mailboxes (one shared inbox would collide):

```bat
tools\mp_dual_local.cmd
```

That script:

1. Starts UDP **host** bridge on `%TEMP%\RoweModMP\A`
2. Starts UDP **join** bridge on `%TEMP%\RoweModMP\B` → `127.0.0.1`
3. Launches **two** `RollerSkate-Win64-Shipping.exe` windows (`-windowed`) with:
   - `ROUEMOD_MP_MAILBOX` / `ROUEMOD_MP_NAME` / `ROUEMOD_MP_ROLE`

In each window: same map → **F9**. Status should show `connected=1`.

Steam’s library button often refuses a second instance; launching the shipping exe directly is intentional. If the second window still fails, start the exe twice yourself after the bridges are up.

On two different PCs, keep using `mp_host.cmd` / `mp_join.cmd` instead.

## Maps (required)

Ghosts and grind rail ids only make sense in the **same level**. The mod:

1. Detects the local map (`GameplayStatics.GetCurrentLevelName` / world name).
2. Puts `mapId` on every **hello** (`H|…|mapId`).
3. Host announces the session map with **MREQ**.
4. **Gates gameplay sync** until local map == session map == peer maps (`requireSameMap = true`).

| Command | What it does |
|---|---|
| `rowemod mp map` | Show local + session map status |
| `rowemod mp map ParkName` | Host: set session map + ask peers to travel |
| `rowemod mp travel` | Travel to the host’s session map |
| `rowemod mp travel ParkName` | Travel to a named map |

Config (`config.lua` → `mp`):

```lua
requireSameMap = true,       -- block sync on mismatch (recommended)
hostMapAuthority = true,     -- host map is the session map
autoTravelToHostMap = false, -- set true to OpenLevel automatically on MREQ
```

Travel uses `OpenLevel` / `open <map>` with short names and a few `/Game/...` guesses. If travel fails, load the map in the menu manually, then `rowemod mp map` should flip to `ok=true`.

Rail ids on the wire are scoped as `mapId#railName` so two parks cannot collide.

## What syncs

| Channel | Contents |
|---|---|
| Handshake | Player name, protocol ver, **mapId** |
| Transform (~20 Hz) | Location, rotation, velocity (only if maps match) |
| Grind | Enter / update / exit |
| Air | Grab id changes |
| Bail | Ragdoll flag edge |

Property names are **guessed** in `config.lua` → `mp.props`. After `rowemod recon` / F7 mid-grind, put the real names first in that list so detection is reliable.

## Config

```lua
mp = {
    enabled = false,          -- or press F9 / rowemod mp on
    playerName = "skater",
    role = "auto",            -- auto | host | join (auto reads bridge role.txt)
    mailboxDir = nil,         -- default %TEMP%/RoweModMP — must match the bridge
    transformHz = 20,
    requireSameMap = true,
    hostMapAuthority = true,
    autoTravelToHostMap = false,
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

UE4SS Lua has no sockets, so the bridge is required. Design notes: [multiplayer-tricks-grinds.md](multiplayer-tricks-grinds.md).

## Limits (honest)

- Opt-in LAN only — not matchmaking, not anti-cheat.
- Map travel depends on guessing packaged level paths; manual load is the fallback.
- Ghost spawn depends on `SpawnActor` / fallback `CreatePlayer`; if ghosts fail, check the UE4SS log.
- Until grind bool/stance props are confirmed, grind packets may not fire (transform still will once maps match).
- Do not use this to harass anyone; lobbies are manual.

## Dev / prove connections

```bat
tools\mp_prove.cmd
python tools\mp_prove.py --suite all --out docs\proofs\latest.json
python -m unittest discover -s tests -v
```

`mp_prove.py` stands up a real UDP host + joiner on loopback, writes simulated game hello/map/transform/grind packets into both mailboxes, and asserts bidirectional delivery. Exit `0` = PASS. Latest report: [proofs/latest.json](proofs/latest.json).
