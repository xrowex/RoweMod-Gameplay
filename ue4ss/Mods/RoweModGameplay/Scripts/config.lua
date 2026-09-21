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
}
