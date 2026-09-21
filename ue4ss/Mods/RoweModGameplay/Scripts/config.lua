-- Edit these numbers, save, then press F8 in-game (or type: rowemod reload).
-- 1.0 is the game default. 1.5 is fifty percent faster.

return {
    -- Multiplies CasualSpeedIncrease and SprintSpeedIncrease together.
    speedMultiplier = 1.25,

    -- Set a number to override a field instead of using the multiplier.
    -- Leave as nil to leave that field alone (except speedMultiplier).
    casualSpeedIncrease = nil,
    sprintSpeedIncrease = nil,
    maxLinearForce = nil,
    maxAngularForce = nil,
    gravity = nil,
    slomoSpeed = nil,

    -- Multiplayer (tricks / grinds / transform sync). Opt-in.
    -- 1) Start tools/rowemod_mp.py host  (or join --host <ip>)
    -- 2) In-game: rowemod mp on   (or F9)
    mp = {
        enabled = false,
        playerName = "skater",
        -- nil = %TEMP%/RoweModMP  (must match the bridge --mailbox)
        mailboxDir = nil,
        transformHz = 20,

        -- Property name guesses. After `rowemod recon`, put the real names first.
        props = {
            grinding = { "bIsGrinding", "IsGrinding", "Grinding", "OnGrind", "bOnRail" },
            balance = { "Balance", "BalanceMeter", "CurrentBalance", "GrindBalance" },
            stance = { "GrindStance", "Stance", "GrindType", "CurrentGrind" },
            grab = { "CurrentGrab", "GrabType", "Grab", "ActiveGrab" },
            rail = { "CurrentRail", "GrindRail", "Rail", "ActiveRail" },
            splineT = { "GrindDistance", "RailAlpha", "SplineDistance", "GrindAlpha" },
            bail = { "bIsRagdoll", "IsRagdoll", "bBail", "Ragdolling" },
        },
    },
}
