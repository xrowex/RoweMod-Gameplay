-- Audited against the installed game's Blueprint defaults and stock settings UI.
-- See docs/slider-audit.md. Named defaults are recovery values, not startup overrides.
return {
    {id="Movement", items={
        {"speedMultiplier","Acceleration multiplier",0.4,4,0.05, default=1, format="%.2fx"},
        {"gravityMultiplier","Gravity",0.25,2,0.05, default=1, format="%.2fx", hint="Scales this map's gravity. Lower values give longer airtime. Local to your game; other players keep their settings."},
        {"steeringStrengthSetting","Steering strength",0.25,2,0.05, default=1, format="%.2fx"},
        {"triggerSteering","Trigger steering","bool"},
        {"streamlinedControls","Streamlined controls","bool"},
        {"forceFeedbackStrength","Controller vibration",0,1,0.05, default=1, format="%.0f%%", scale=100},
    }},
    {id="Tricks", items={
        {"minJumpHeight","Minimum jump scale",0,1,0.25, default=1, format="%.0f%%", scale=100},
        {"jumpPrepSteering","Jump steering resistance",1,19,1, default=10, format="%.0f", hint="Lower values give stronger steering while preparing a jump."},
        {"maxFlipSpeed","Maximum flip rate",90,910,5, default=455, format="%.0f deg/s"},
        {"slomoSpeed","Slow-motion speed",0.15,0.55,0.05, default=0.25, format="%.0f%%", scale=100},
    }},
    {id="Balance", items={
        {"grindMagnetStrength","Grind assistance",0.05,1,0.05, default=0.8, format="%.0f%%", scale=100},
        {"grindMagnetSize","Grind detection size",5,70,5, default=35, format="%.0f", hint="Base trace half-width; multiplied by grind assistance. Stock: 35."},
        {"balanceIntensity","Balance difficulty",0.5,3,0.5, default=1, format="%.1fx"},
        {"baseBalanceDrift","Base balance drift",0,250,5, default=155, format="%.0f"},
        {"requiresBalance","Require balance","bool"},
        {"showBalanceMeter","Show balance meter","bool"},
        {"enableGrindSparks","Grind sparks","bool"},
    }},
}
