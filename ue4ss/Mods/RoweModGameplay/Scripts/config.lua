-- Edit these numbers, save, then press F8 in-game (or type: rowemod reload).
-- 1.0 is the game default. 1.5 is fifty percent faster.
-- Leave a field as nil to leave it alone.

return {
    -- Multiplies CasualSpeedIncrease and SprintSpeedIncrease together.
    speedMultiplier = 1.25,

    -- Speed (overrides the multiplier for that field if set)
    casualSpeedIncrease = nil,
    sprintSpeedIncrease = nil,
    maxLinearForce = nil,
    maxAngularForce = nil,
    gravity = nil,

    -- Jump
    jumpVelocity = nil,
    minJumpHeight = nil,
    maxJumpHeight = nil,
    jumpPrepSteering = nil,

    -- Grind / balance (pause Gameplay menu already has some of these)
    grindMagnetStrength = nil,
    grindMagnetSize = nil,
    balanceIntensity = nil,
    balanceDriftIncrease = nil,
    balanceDriftStrength = nil,
    baseBalanceDrift = nil,
    requiresBalance = nil, -- true / false
    showBalanceMeter = nil, -- true / false
    enableGrindSparks = nil, -- true / false

    -- Spin / flip
    maxSpinSpeed = nil,
    maxFlipSpeed = nil,
    spinMultiplier = nil,
    flipMultiplier = nil,
    grabSpinSpeedDivider = nil,

    -- Steering
    steerMultiplier = nil,
    steeringStrengthSetting = nil,
    triggerSteering = nil, -- true / false
    streamlinedControls = nil, -- true / false

    -- Slow-mo
    slomoSpeed = nil,
    slowmotion = nil, -- true / false

    -- Camera
    cameraDistance = nil,
    cameraHeight = nil,
    cameraLookUp = nil,
    cameraSideOffset = nil,
    airRotInterpSpeed = nil,

    -- Extra feel
    comboMultiplier = nil,
    forceFeedbackStrength = nil,

    -- Multiplayer (LAN ghosts). Opt-in.
    -- Same PC: tools\mp_dual_local.cmd   Two PCs: mp_host.cmd / mp_join.cmd <ip>
    -- Then F9 (or rowemod mp on). Peers must share the same map.
    mp = {
        enabled = false,
        playerName = "skater",
        -- "auto" reads host/join from the bridge status file; or set "host" / "join".
        role = "auto",
        -- nil = %TEMP%/RoweModMP  (must match the bridge --mailbox)
        mailboxDir = nil,
        transformHz = 20,
        requireSameMap = true,
        hostMapAuthority = true,
        -- If true, joiners OpenLevel when the host sends a map request.
        autoTravelToHostMap = false,

        -- Real NewMainCharacter names first, then leftover guesses.
        props = {
            grinding = { "IsGrinding", "bIsGrinding", "Grinding", "OnGrind", "bOnRail" },
            balance = { "BalanceIntensity", "Balance", "GrindBalance", "BalanceMeter" },
            stance = { "ActiveGrindType", "GrindType", "GrindStance", "CurrentGrind" },
            grab = { "GrabVariant", "IsGrabbing", "CurrentGrab", "GrabType" },
            rail = { "CurrentSpline", "NextGrind", "CurrentRail", "GrindRail" },
            splineT = { "ElapsedGrindTime", "GrindDistance", "RailAlpha", "SplineDistance" },
            bail = { "IsRagdoll", "bIsRagdoll", "bBail", "Ragdolling" },
        },
    },
}
