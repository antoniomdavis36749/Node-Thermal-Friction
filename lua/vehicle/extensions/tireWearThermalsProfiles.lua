-- lua/vehicle/extensions/tireWearThermalsProfiles.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- Compound spectra / standalones / DEFAULT_MODS plus load-time soft-cap and character stamps.
-- Loaded by lua/vehicle/extensions/auto/tireWearThermals.lua (not an auto-extension).
local M = {}

--[[
  ========================================================================
  TIRE PROFILE SCHEMA (mods table) — 49 knobs + runtime descriptor
  Every profile table must include all of these; normalizeProfileMods()
  backfills any missing keys from DEFAULT_MODS.

  ARCHITECTURE (Phase 5 — gates stay gates)
    Profiles  = rubber physics: spectra / standalones / the 49 knobs
                (PROFILE_POINTS, SLICK_*, UTILITY_*, COMMERCIAL_*, ATV_UTV_*,
                 VINTAGE_*, STANDALONE_MODIFIERS). Own heat/grip/wear + soft-cap
                *magnitudes* (driveSlipHeatMin / driveSlipPropMin /
                driveHighVCarcassScale).
    Purpose   = duty/use class (street, wet, winter, utility, commercial,
                circuit, drag, drift, tarmac_rally, gravel, …). Set at classify
                time; UI chips + classifyReason. Selects which soft-cap ENABLE
                pack may fire — does NOT duplicate full profile tables.
    Gates /   = vehicle/surface/state enable conditions in THERMAL_TOPOLOGY
    topology    (speed/slip/g ramps, AWD, undriven flex, brake soak, ducts,
                soft-sink). Not tire type. dutyMods lists ids only while a gate
                is actually applying after purpose filtering.

    Soft-cap enable pack by purpose (magnitudes still from profiles):
      ON  — street, wet, winter, utility, commercial
      OFF — circuit, drag, drift, tarmac_rally, gravel
            (rally rubber may keep stamped floors but purpose skips the path;
             slick spectrum floors are already 1.0 / OFF.)

  SPECTRUM INVENTORY (anchors; interpolateSpectrum lerps between neighbors)
    PROFILE_POINTS          tread 0.30/0.40/0.50/0.60/0.70/0.80/0.85/0.90/1.00
                            sport_plus → track_day → sport → standard → …
    SLICK_SPECTRUM_POINTS   softness 0.50/0.575/0.65/0.725/0.80/0.875
                            (JBeam soft 0.5/0.8/1.0 remapped onto hard/med/soft;
                             0.875 is supersoft C5 — stock 1.0 still remaps to 0.80)
    UTILITY_SPECTRUM        tread 0.50/0.60/0.70/0.85/0.95
    COMMERCIAL_SPECTRUM     tread 0.50/0.60/0.70/0.80/0.90
    ATV_UTV_SPECTRUM        tread 0.50/0.60/0.70/0.85
    VINTAGE_SPECTRUM        tread 0.50/0.575/0.65

  GRIP / COMPOUND
    adhesion            0–1  How strongly thermal grip follows the peak curve
                             (higher = more temp-sensitive sticky compound).
    gripMultiplier      Scale on total grip after thermal shaping (~0.6–1.2).
    longGripMult        Longitudinal (brake/accel) grip scale.
    latGripMult         Lateral (cornering) grip scale.
    loadSensitivity     Grip loss under overload vs static wheel load.
    pressureSensitivity Scales mild + outer pressure→grip penalties (band widths are
                             topology globals; higher = pickier compound).
    optimalPressure     Absolute hot PSI target for best patch (also UI hot target).
    casingCompliance    Sidewall flex 0–1 (camber window, pressure expand).
    waterDrainage       0–1 Wet aquaplane resistance (higher = better).
    wetGripScale        Extra wet-paved multiplier (after hydro model).
    dryGripScale        Extra dry/hard surface multiplier.
    camberSensitivity   Scales excess-camber grip penalty.
    bottomOutSensitivity Scales bump/bottom-out wear + grip hit.
    scrubSensitivity     Scales toe-scrub energy into slip heat.

  THERMAL TARGET / GRIP CURVE
    optimalTemp         °C compound peak (working_temp / green window center).
    tempPlateau         °C half-width of full-grip plateau around opt.
    coldWidth           °C Gaussian width below plateau (cold roll-off).
    hotWidth            °C Gaussian width above plateau (hot cliff).
    gripFloor           Minimum thermal multiplier at extreme temps (0–1).
    coldGripPower       Plateau-Gaussian cold-side exponent (shape; widths stay coldWidth).
    hotGripPower        Plateau-Gaussian hot-side exponent (shape; widths stay hotWidth).

  HEAT GENERATION
    slipHeatRate        Skin heat from sliding / slip energy.
    workHeatRate        Skin/carcass heat from cornering work + vertical.
    workHeatG0          g_mag below this → zero skin cornering work (default 0.22).
    rollingRes          Rolling-resistance scale (hysteresis + torque heat).
    brakeGainRate       How strongly stock brake temps soak the rim node.
    scrubSensitivity    (see above) also feeds dynamic slip energy.

  DUTY SOFT-CAP MAGNITUDES (topology enables; profiles own strength)
    driveSlipHeatMin    Floor mult on slip→skin heat at full soft-cap blend (1.0 = off).
    driveSlipPropMin    Floor mult on prop netTorque skin path at full blend (1.0 = off).
    driveHighVCarcassScale  Carcass excess/RR mult at high-V Speed1 (1.0 = no damp).
                             Street continuum ≈0.40/0.62/0.28; sport_plus ≈0.72/0.82/0.28;
                             slick spectrum = 1.0/1.0/1.0 (gate already excludes slicks).

  COOLING / CONDUCTION
    staticCoolingRate   Still-air / natural convection baseline.
    airCoolingRate      Freestream convection on skin (× v^0.8).
    skinVelCoolScale    Soft-only (etc.) multiplier on the 0.155 velCool term (1.0 = default).
    coreCoolRate        Carcass static cooling.
    coreVelCoolRate     Carcass velocity-linked cooling.
    skinCoreConductance Skin ↔ carcass lane conductance.
    airConductionRate   Cavity air ↔ carcass / rim coupling.
    trackConductivityMult  Asphalt (etc.) conduction scale into skin.

  THERMAL MASS / RESPONSE
    treadInertia        Skin thermal mass (higher = slower skin ΔT).
    carcassInertia      Carcass thermal mass.
    airThermalInertia   Cavity-air thermal mass (PSI lag dial; << carcass).
    thermalReactionRate Global rate multiplier on skin temp integration.

  TOPOLOGY KNOBS (module THERMAL_TOPOLOGY; not per-profile unless noted)
    patchFracMin/Max/Ref  Contact-patch circumferential share + heat normalize.
    patchFracHeatMin      Softer floor for patchHeatScale (load/PSI/depth can move).
    patchHeatEmaTau       Light EMA on patchHeatScale after raw compute.
    patchUtilBlend        peakForce/downForceRaw util blend into patchHeatScale (A3).
    patchUtilPeakLo/Hi    Util clamp band for peakWorkFactorEarly.
    patchDynRadiusMin/MaxFrac  dynamicRadius clamp vs static for patch length (A4).
    softSinkHeat*/Rough*  Soft-surface frictional heat damp (conduction separate).
    softSinkDefaultDepth*/Strength*/Fluid*/Stribeck*  Path A1 GM soft/wet into soft-sink.
    gmConduction*         Path A1 GM soft/wet into track conduction denom.
    dualContactBlend/WearBump  Path A2 secondary contactMaterialID2 (spike excluded).
    contactDepthEmaTau    Short EMA on contactDepth before patch blend.
    patchHertzDeflBlend   Max weight of deflection proxy vs Hertz F/P area.
    patchDeflWidthFrac    Width fraction on chord×width deflection area.
    patchLatLoadNudge     Mild live gy nudge on L/R ring weights.
    hystSkinShare         Bulk RR/flex→skin leak (NOT × patchHeatScale).
    brakeSurfSoak/CoreSoak  Rim soak from brake surface (fast ≫) / core (lag).
    brakeEffSoakFloor     Glazing/efficiency floor on rim soak scale (η soft only).
    brakeRadiantCoef      Radiant brake surface → rim (T^4); area/duct/gain applied live.
    -- Brake non-goals: no native rotor replace; no duct→brakeTypeSurfaceCoolingCoef write;
    -- no torque-fade ownership; tire-side soak/duct/read only.
    pressureColdRefreshTau / pressureTpmsDeadbandPsiS
                          Cold fill soft-refresh vs native; skip on TPMS inflate.
    pressureColdRefreshParkedOnly / MaxSpeed
                          Garage/pit only, using vehicle speed (not per-wheel hop).
                          Rolling cold slicks stay in the 8K window; hop frames
                          used to look parked and pumped Cold (27→40 PSI on fronts).
    pressureHotWritebackEnable / MaxPsiS / RecoverPsiS / DeadbandPsi
                          Rate-limited Gay-Lussac hot PSI → setGroupPressure (soft-body).
                          RecoverPsiS pulls native down faster when it is above thermal.
    freeBeltCoolMult      Free-belt convection bias on average skin.
    flexWarmGain (+gates) Gated flex energy into carcass (load/speed/g·slip).
    drivePropCruiseNm / ExcessFullNm / SkinCoef / Hyst* / Flex*
                          Excess-prop drive heat pass 4 (small bump on pass 3;
                          choke softens mid-prop; FlexExcess@FlexGateStart; SlipWorkMult).
    drivePropSlickScale   Skin excess-prop mult on slick/race only (Phase 1: 1.0).
    drivePropSlickCarcassScale  Carcass excess/RR mult on slick/race only (Phase 1: 1.0).
    cruiseRrScaleFull / Partial   Belasco straight RR soft-cap (Phase 2: 1.0 = off; was 0.48/0.72).
    cruiseDriveChokeMin   Straight cruise driveHeatGate floor (Phase 2: 1.0 = off; was 0.15).
    drivePropStreetSpeed0/1
                          High-V freestream enable ramp for profile driveHighVCarcassScale.
    driveStreetSlipSpeed0/1 / CapStart/Full / G0/G1
                          Residual long-slip soft-cap ENABLE ramps (FWD accel cook;
                          magnitudes = profile driveSlipHeatMin / driveSlipPropMin).
    drivePropMassRefKg / MassScaleMin/Max  Scale cruise/excess Nm by sqrt(mass/ref).
    drivePropAwdExcessScale / DrivenThreshNm  AWD layout damp on excessPropGate.
    drivePropFwdSoftScale / FwdSoftCarcassScale / FwdSoftSoftnessMin
                          FWD Soft-like driven-front damp LOCKED (0.58/0.48). Keeps Hot;
                          top of usable ~95–105. RWD Soft Phase1 unmute untouched.
    drivePropAwdSoftScale / AwdSoftCarcassScale
                          AWD Soft-like driven-front damp LOCKED (0.45/0.38). FR top usable;
                          FL harsh/brake ceiling. Softness gate shares FwdSoftSoftnessMin.
    skinLateralConductance  Skin L↔C↔R conductance.
    gripBlendWarm/Cold    Dynamic EffectiveTyreTemp carcass share.
    slipVelBoostStart/Full/Max  Gated |lastSlip| longComp boost (burnout/lock).
    pressureNeutralHalf / NormalUnder / NormalOver
                          Ratio bands for CalcPressureGripScales (asymmetric over; neutral deadband).
    pressureMildBase / MildSens
                          Mild-edge penalty vs pressureSensitivity (no perfect-zone bonus).
    skinSlipWorkScale     Multiplier on skin slip/work heat (default 1; compound rates own stint).
    flexWarmGain (+gates) Undriven/coast warm-up folded here (no separate undrivenRr).

  WEAR / SURFACE DAMAGE
    wearRate            Base structural wear rate.
    rollingWearCoef     Distance/rolling wear vs ω (1.0 = current tiny term; slick C4 >1).
    coldWearMult        Wear multiplier when well below opt.
    hotWearMult         Wear multiplier when above opt.
    grainTempRatio      Graining starts below opt × this (street Sport/Plus 0.88; default 0.75).
    blisterTempRatio    Blistering starts above opt × this (e.g. 1.55).
    grainRate           Cold-scrub grain accumulation rate (onset stays grainTempRatio).
    blisterRate         Overheat blister accumulation rate (onset stays blisterTempRatio).
                        Sport plus/tour: brief light-slip or loaded Hot corner; not a 4s drift.
    stintFadeRate       Hot-stint fade + heat-cycle wear/grip kinetics scale (1.0 = today).
    camberWearMult      Excess-camber wear scale only (grip camber stays camberSensitivity).
                        At 1.0 bit-identical to pre-knob wear; >1 adds mild shoulder wear.

  Runtime-only (not in DEFAULT_MODS tables):
    descriptor          Compound-facing UI label set by getInterpolatedProfile().
    purpose             Duty/use id (circuit, tarmac_rally, gravel, street, …).
    classifyReason      Why purpose/compound routed (asphalt_name, race_sku, …).
    dutyMods            Active topology/runtime gate ids (not the 49 knobs):
                        fwd_slip_softcap, sport_plus_slip_softcap, street_high_v_damp,
                        awd_prop_gate, undriven_warmup, brake_tire_soak, duct_tire_side,
                        soft_sink_damp, aero_heat_disc — only while applying after purpose
                        enable filter; Heavy UI visibility.
  ========================================================================
]]
-- PHYSICAL FALLBACK DEFAULTS (Used to protect custom modded profiles missing keys)
-- Soft-cap magnitudes default OFF (1.0); street/sport_plus packs stamped onto spectra below.
-- Compound-character knobs default to pre-expansion hardcoded constants (neutral feel).
local DEFAULT_MODS = {
    adhesion = 0.45, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
    casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
    gripMultiplier = 1.00, longGripMult = 1.0, latGripMult = 1.0, loadSensitivity = 0.04,
    optimalPressure = 32, optimalTemp = 65, pressureSensitivity = 0.5, rollingRes = 0.8,
    staticCoolingRate = 0.08, slipHeatRate = 8.925, workHeatRate = 5.1, wearRate = 0.0005,
    treadInertia = 0.46, carcassInertia = 0.75, airThermalInertia = 0.22, thermalReactionRate = 1.35,
    tempPlateau = 15, coldWidth = 55, hotWidth = 55, gripFloor = 0.24,
    coldGripPower = 1.35, hotGripPower = 2.0,
    coldWearMult = 1.8, hotWearMult = 3.5, grainTempRatio = 0.75, blisterTempRatio = 1.55,
    grainRate = 0.00042, blisterRate = 0.00028,
    stintFadeRate = 1.0, camberWearMult = 1.0, rollingWearCoef = 1.0,
    waterDrainage = 0.8, wetGripScale = 1.0, dryGripScale = 1.0, trackConductivityMult = 1.0,
    skinVelCoolScale = 1.0, workHeatG0 = 0.22,
    camberSensitivity = 1.0, bottomOutSensitivity = 1.0, scrubSensitivity = 1.0,
    -- Phase 4: duty soft-cap magnitudes (1.0 = gate may enable but scale stays unity)
    driveSlipHeatMin = 1.0, driveSlipPropMin = 1.0, driveHighVCarcassScale = 1.0
}

-- Named soft-cap packs. Stamped onto spectra/standalones.
-- Phase 5: packs are magnitudes only; purposeAllowsStreetSoftcap() selects enable.
-- Pass 5/6: floors moved toward 1.0 after root drive-heat cuts (debt paydown; enable rules unchanged).
local DRIVE_SOFTCAP_STREET = { driveSlipHeatMin = 0.90, driveSlipPropMin = 0.93, driveHighVCarcassScale = 0.80 }
-- Sport HEAT LOCKED for now (v7 + tiny slip/work bump 9.68/5.61). Between street and Plus.
local DRIVE_SOFTCAP_SPORT = { driveSlipHeatMin = 0.92, driveSlipPropMin = 0.95, driveHighVCarcassScale = 0.87 }
local DRIVE_SOFTCAP_SPORT_PLUS = { driveSlipHeatMin = 0.94, driveSlipPropMin = 0.97, driveHighVCarcassScale = 0.82 }
-- Track Day LOCKED: Plus (0.94/0.97/0.82) → Hard C2 OFF (1.0/1.0/1.0). Street gate still on.
local DRIVE_SOFTCAP_TRACK_DAY = { driveSlipHeatMin = 0.97, driveSlipPropMin = 0.985, driveHighVCarcassScale = 0.91 }
-- Vintage/bias-ply: gentler than street — historical rubber shouldn't need FWD soft-cap crutch.
local DRIVE_SOFTCAP_VINTAGE = { driveSlipHeatMin = 0.95, driveSlipPropMin = 0.97, driveHighVCarcassScale = 0.88 }
local DRIVE_SOFTCAP_OFF = { driveSlipHeatMin = 1.0, driveSlipPropMin = 1.0, driveHighVCarcassScale = 1.0 }
-- Purpose → soft-cap ENABLE pack (not a second profile table).
local STREET_SOFTCAP_PURPOSES = {
    street = true, wet = true, winter = true, utility = true, commercial = true,
}
local function purposeAllowsStreetSoftcap(purpose)
    return STREET_SOFTCAP_PURPOSES[purpose or ""] == true
end
local function stampDriveSoftcap(mods, pack)
    if type(mods) ~= "table" or type(pack) ~= "table" then return end
    for k, v in pairs(pack) do mods[k] = v end
end
local function stampSpectrumDriveSoftcap(spectrum, packOrFn)
    if type(spectrum) ~= "table" then return end
    for i = 1, #spectrum do
        local pt = spectrum[i]
        if pt and pt.mods then
            local pack = packOrFn
            if type(packOrFn) == "function" then pack = packOrFn(pt.profile) end
            stampDriveSoftcap(pt.mods, pack or DRIVE_SOFTCAP_STREET)
        end
    end
end

-- Compound-character packs (neutral = today's hardcoded rates/powers). Soft-caps stay separate.
-- Street/utility/winter/rain stay NEUTRAL so soft-sims keep absolute feel; race/sport climb.
local CHARACTER_NEUTRAL = {
    coldGripPower = 1.35, hotGripPower = 2.0,
    grainRate = 0.00042, blisterRate = 0.00028,
    stintFadeRate = 1.0, camberWearMult = 1.0,
}
local CHARACTER_SPORT = {
    coldGripPower = 1.33, hotGripPower = 2.20,
    grainRate = 0.00086, blisterRate = 0.00045,
    stintFadeRate = 1.15, camberWearMult = 1.06,
}
-- Track Day LOCKED: between Sport Plus and Hard C2 (not Plus and Sport).
-- Plus blister #7e stays Plus-only; this pack is a Plus→Hard lerp.
local CHARACTER_TRACK_DAY = {
    coldGripPower = 1.36, hotGripPower = 2.22,
    grainRate = 0.00042, blisterRate = 0.00062,
    stintFadeRate = 1.20, camberWearMult = 1.11,
}
local CHARACTER_SPORT_PLUS = {
    coldGripPower = 1.32, hotGripPower = 2.28,
    grainRate = 0.00090, blisterRate = 0.00090,
    stintFadeRate = 1.22, camberWearMult = 1.10,
}
local CHARACTER_SLICK_HARD = {
    coldGripPower = 1.40, hotGripPower = 2.15,
    grainRate = 0.00038, blisterRate = 0.00033,
    stintFadeRate = 1.18, camberWearMult = 1.12,
}
local CHARACTER_SLICK_MED = {
    coldGripPower = 1.38, hotGripPower = 2.20,
    grainRate = 0.00044, blisterRate = 0.00036,
    stintFadeRate = 1.25, camberWearMult = 1.15,
}
local CHARACTER_SLICK_SOFT = {
    coldGripPower = 1.36, hotGripPower = 2.28,
    grainRate = 0.00050, blisterRate = 0.00040,
    stintFadeRate = 1.35, camberWearMult = 1.18,
}
local CHARACTER_SLICK_SUPERSOFT = {
    coldGripPower = 1.34, hotGripPower = 2.36,
    grainRate = 0.00056, blisterRate = 0.00048,
    stintFadeRate = 1.50, camberWearMult = 1.22,
}
local CHARACTER_DRAG = {
    coldGripPower = 1.32, hotGripPower = 2.10,
    grainRate = 0.00040, blisterRate = 0.00034,
    stintFadeRate = 1.12, camberWearMult = 1.08,
}
local CHARACTER_DRIFT = {
    coldGripPower = 1.35, hotGripPower = 2.05,
    grainRate = 0.00048, blisterRate = 0.00030,
    stintFadeRate = 1.10, camberWearMult = 1.05,
}
local function stampCharacterKnobs(mods, pack)
    if type(mods) ~= "table" or type(pack) ~= "table" then return end
    for k, v in pairs(pack) do mods[k] = v end
end
local function stampSpectrumCharacter(spectrum, packOrFn)
    if type(spectrum) ~= "table" then return end
    for i = 1, #spectrum do
        local pt = spectrum[i]
        if pt and pt.mods then
            local pack = packOrFn
            if type(packOrFn) == "function" then pack = packOrFn(pt.profile, pt) end
            stampCharacterKnobs(pt.mods, pack or CHARACTER_NEUTRAL)
        end
    end
end

-- Baseline grip polynomial coeffs: grip = a + x*(b + x*(c + x*d)) with x = condition 0–1.
-- Order matters: more specific tags BEFORE shorter substrings (sport_plus before sport).
local DEFAULT_GRIP_COEFFS = {
    { "sport_plus", { 1.12, 0.22, -0.08 } },  -- Semi-slick / Scintilla lock peak ~1.26
    { "track_day", { 1.15, 0.22, -0.08 } },   -- LOCKED ~Plus+2% peak (~1.29); 200TW-ish, not 40% Plus→Hard
    { "supersoft_slick", { 1.46, 0.36, -0.12 } },
    { "soft_slick", { 1.42, 0.34, -0.12 } },
    { "medium_slick", { 1.38, 0.32, -0.12 } },
    { "hard_slick", { 1.34, 0.30, -0.11 } },
    { "slick", { 1.38, 0.32, -0.12 } },       -- Generic slick / race
    { "sport", { 1.02, 0.16, -0.06 } },       -- Performance street peak ~1.12
    { "drag", { 1.28, 0.28, -0.10 } },        -- Drag slick-ish long bias (longGripMult stacks)
    { "drift", { 0.88, 0.12, -0.05 } },       -- Intentionally lower peak
    { "rain", { 0.96, 0.14, -0.05 } },        -- Wet specialist; wetGripScale stacks
    { "rally", { 0.98, 0.14, -0.05 } },
    { "winter", { 0.90, 0.12, -0.04 } },
    { "paddle", { 0.70, 0.08, -0.02 } },
    { "donut", { 0.68, 0.08, -0.03 } },       -- Spare / space-saver
    { "mudterrain", { 0.76, 0.08, -0.02 } },
    { "allterrain", { 0.82, 0.10, -0.03 } },
    { "crawler", { 0.72, 0.06, -0.02 } },
    { "vintage", { 0.88, 0.11, -0.04 } },  -- Bias/classic radial peak ~0.95 (~91–96% of standard after gripMult)
    { "utility", { 0.84, 0.08, -0.02 } },
    { "truck", { 0.86, 0.08, -0.02 } },
    { "heavy", { 0.84, 0.08, -0.02 } },       -- heavy_duty / heavy_offroad
    { "standard", { 0.92, 0.12, -0.04 } },    -- Passenger
    { "utv", { 0.78, 0.08, -0.02 } },
}

local GRIP_COEFFS = _G.GRIP_COEFFS
if not GRIP_COEFFS or #GRIP_COEFFS == 0 then
    GRIP_COEFFS = DEFAULT_GRIP_COEFFS
end

-- STANDALONE OVERRIDES (With pre-calculated absolute physical rates and suspension sensitivities)
local STANDALONE_MODIFIERS = {
    drag = {
        adhesion = 0.58, airConductionRate = 0.018, airCoolingRate = 0.0175, brakeGainRate = 1.5,
        casingCompliance = 0.85, coreCoolRate = 0.021, coreVelCoolRate = 0.004, skinCoreConductance = 0.12,
        gripMultiplier = 1.18, longGripMult = 1.12, latGripMult = 0.92, loadSensitivity = 0.055,
        optimalPressure = 16, optimalTemp = 72, pressureSensitivity = 0.35, rollingRes = 1.55,
        staticCoolingRate = 0.08, slipHeatRate = 16.2, workHeatRate = 6.6, wearRate = 0.0018,
        treadInertia = 0.231, carcassInertia = 0.374, thermalReactionRate = 2.1, tempPlateau = 12,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 2.01,
        hotWearMult = 4.2, grainTempRatio = 0.78, blisterTempRatio = 1.48, waterDrainage = 0.1,
        wetGripScale = 0.72, dryGripScale = 1.08, trackConductivityMult = 1.15, camberSensitivity = 1.4,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.5
    },
    drift = {
        adhesion = 0.48, airConductionRate = 0.015, airCoolingRate = 0.0225, brakeGainRate = 1.2,
        casingCompliance = 0.4, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.094,
        gripMultiplier = 0.88, longGripMult = 0.95, latGripMult = 0.92, loadSensitivity = 0.05,
        optimalPressure = 26, optimalTemp = 75, pressureSensitivity = 0.35, rollingRes = 1.02,
        staticCoolingRate = 0.08, slipHeatRate = 10.0, workHeatRate = 3.6, wearRate = 0.002,
        treadInertia = 0.40, carcassInertia = 0.648, thermalReactionRate = 1.3, tempPlateau = 14,
        coldWidth = 65, hotWidth = 65, gripFloor = 0.28, coldWearMult = 1.86,
        hotWearMult = 4.5, grainTempRatio = 0.78, blisterTempRatio = 1.80, waterDrainage = 0.4,
        wetGripScale = 0.95, dryGripScale = 1, trackConductivityMult = 1.15, camberSensitivity = 0.9,
        bottomOutSensitivity = 1, scrubSensitivity = 1.3
    },
    vintage = {
        -- Pass 5: cooler historical rubber (lower slip/work heat, more RR + thermal mass).
        -- Flavor via thermal window / RR / wear — gripMultiplier held (no μ dump).
        adhesion = 0.28, airConductionRate = 0.0135, airCoolingRate = 0.02375, brakeGainRate = 0.6,
        casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,
        gripMultiplier = 0.94, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.042,
        optimalPressure = 30, optimalTemp = 58, pressureSensitivity = 0.45, rollingRes = 0.90,
        staticCoolingRate = 0.08, slipHeatRate = 6.6, workHeatRate = 5.6, wearRate = 0.0004,
        treadInertia = 0.48, carcassInertia = 0.78, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1.4
    },
    crawler = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.85, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,
        gripMultiplier = 0.78, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 9, optimalTemp = 48, pressureSensitivity = 0.18, rollingRes = 1.65,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3.3, wearRate = 0.00015,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.9, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 1,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    },
    paddle = {
        adhesion = 0.25, airConductionRate = 0.012, airCoolingRate = 0.0375, brakeGainRate = 0.45,
        casingCompliance = 0.8, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.04,
        gripMultiplier = 0.74, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.028,
        optimalPressure = 10, optimalTemp = 48, pressureSensitivity = 0.22, rollingRes = 1.95,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.6, wearRate = 0.0008,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.5, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.62,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    },
    truck = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.0325, brakeGainRate = 0.225,
        casingCompliance = 0.12, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.014,
        optimalPressure = 100, optimalTemp = 65, pressureSensitivity = 0.15, rollingRes = 0.65,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 2.7, wearRate = 0.00008,
        treadInertia = 1.89, carcassInertia = 3.06, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.832, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.8, scrubSensitivity = 1.2
    },
    truck_offroad = {
        adhesion = 0.32, airConductionRate = 0.009, airCoolingRate = 0.0375, brakeGainRate = 0.225,
        casingCompliance = 0.18, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.036,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 85, optimalTemp = 60, pressureSensitivity = 0.1, rollingRes = 0.9,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.00012,
        treadInertia = 2.016, carcassInertia = 3.264, thermalReactionRate = 1.25, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.848, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 1, camberSensitivity = 0.6,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1
    },
    heavy_duty = {
        adhesion = 0.38, airConductionRate = 0.0105, airCoolingRate = 0.03, brakeGainRate = 0.45,
        casingCompliance = 0.15, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.052,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 85, optimalTemp = 65, pressureSensitivity = 0.25, rollingRes = 0.8,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 3.3, wearRate = 0.00015,
        treadInertia = 1.008, carcassInertia = 1.632, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.75,
        wetGripScale = 1.038, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.7, scrubSensitivity = 1.2
    },
    light_truck_std = {
        adhesion = 0.42, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.6,
        casingCompliance = 0.35, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.028,
        optimalPressure = 38, optimalTemp = 62, pressureSensitivity = 0.35, rollingRes = 0.95,
        staticCoolingRate = 0.08, slipHeatRate = 8.4, workHeatRate = 4.8, wearRate = 0.0004,
        treadInertia = 0.504, carcassInertia = 0.816, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.8,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.9,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.1
    },
    light_truck_hd = {
        adhesion = 0.4, airConductionRate = 0.012, airCoolingRate = 0.02875, brakeGainRate = 0.525,
        casingCompliance = 0.25, coreCoolRate = 0.042, coreVelCoolRate = 0.0096, skinCoreConductance = 0.06,
        gripMultiplier = 0.88, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 60, optimalTemp = 65, pressureSensitivity = 0.3, rollingRes = 0.85,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 4.2, wearRate = 0.00025,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 1.1, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 2.9, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1.1
    },
    winter = {
        adhesion = 0.4, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.6,
        casingCompliance = 0.65, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,
        gripMultiplier = 0.86, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.035,
        optimalPressure = 32, optimalTemp = 38, pressureSensitivity = 0.35, rollingRes = 0.95,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 4.2, wearRate = 0.0008,
        treadInertia = 0.462, carcassInertia = 0.748, thermalReactionRate = 1.35, tempPlateau = 16,
        coldWidth = 42, hotWidth = 40, gripFloor = 0.28, coldWearMult = 1.8,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.1, dryGripScale = 0.9, trackConductivityMult = 1, camberSensitivity = 1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.2
    },
    donut = {
        adhesion = 0.3, airConductionRate = 0.0165, airCoolingRate = 0.03, brakeGainRate = 1.2,
        casingCompliance = 0.45, coreCoolRate = 0.042, coreVelCoolRate = 0.0096, skinCoreConductance = 0.064,
        gripMultiplier = 0.68, longGripMult = 0.95, latGripMult = 0.88, loadSensitivity = 0.06,
        optimalPressure = 60, optimalTemp = 60, pressureSensitivity = 0.5, rollingRes = 0.6,
        staticCoolingRate = 0.08, slipHeatRate = 11.5, workHeatRate = 6.6, wearRate = 0.002,
        treadInertia = 0.252, carcassInertia = 0.408, thermalReactionRate = 1.5, tempPlateau = 14,
        coldWidth = 55, hotWidth = 55, gripFloor = 0.22, coldWearMult = 1.68,
        hotWearMult = 4.5, grainTempRatio = 0.75, blisterTempRatio = 1.58, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 1.2,
        bottomOutSensitivity = 1.5, scrubSensitivity = 1.3
    },
    rally = {
        adhesion = 0.45, airConductionRate = 0.015, airCoolingRate = 0.0275, brakeGainRate = 1.05,
        casingCompliance = 0.55, coreCoolRate = 0.035, coreVelCoolRate = 0.008, skinCoreConductance = 0.08,
        -- latGripMult: mild turn-in bite (clog still hits both axes via tyreGrip; loose bias does the rest)
        gripMultiplier = 0.96, longGripMult = 1, latGripMult = 1.06, loadSensitivity = 0.038,
        optimalPressure = 28, optimalTemp = 68, pressureSensitivity = 0.38, rollingRes = 1.12,
        staticCoolingRate = 0.08, slipHeatRate = 9.45, workHeatRate = 5.1, wearRate = 0.0006,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.65, tempPlateau = 16,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 1.83,
        hotWearMult = 3.04, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.75,
        wetGripScale = 1.038, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1
    },
    rain = {
        adhesion = 0.50, airConductionRate = 0.0165, airCoolingRate = 0.035, brakeGainRate = 1.35,
        casingCompliance = 0.5, coreCoolRate = 0.042, coreVelCoolRate = 0.0096, skinCoreConductance = 0.094,
        gripMultiplier = 0.90, longGripMult = 1.02, latGripMult = 1.05, loadSensitivity = 0.038,
        optimalPressure = 28, optimalTemp = 58, pressureSensitivity = 0.7, rollingRes = 1.18,
        staticCoolingRate = 0.08, slipHeatRate = 9.9, workHeatRate = 5.4, wearRate = 0.0008,
        treadInertia = 0.315, carcassInertia = 0.51, thermalReactionRate = 1.65, tempPlateau = 15,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 1.92,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.22, dryGripScale = 0.92, trackConductivityMult = 1, camberSensitivity = 1.1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.4
    }
}

-- CONTINUOUS MECHANICAL TREAD SPECTRUM: Aligned with native JBeam treadCoef bands.
-- Intermediate anchors (0.40 / 0.60 / 0.85) densify sport↔standard and AT↔MT leaps.
local PROFILE_POINTS = {
    { tread = 0.30, profile = "sport_plus", mods = {
        -- Scintilla sport plus HEAT+WEAR LOCKED (#8 accepted, Belasco Track 15°C).
        -- #7 FL cook: 102°C / 60% blister / 83% tread. #8: 1-lap FL ~81, late stint ~70s–80s
        -- Normal, blister 0, worst tread ~98.5% (~1.5% wear). Do not chase FL to 76 on rights.
        -- velCool 0.50, slip/work 16.6/10.2, wearRate 0.0028. BLISTER #7e / GRIP v4 held.
        -- Grain #1 (ratio 0.88) separate — cold out-lap only. Do not nudge heat/wear.
        adhesion = 0.52, airConductionRate = 0.015, airCoolingRate = 0.011, brakeGainRate = 1.35,
        casingCompliance = 0.45, coreCoolRate = 0.038, coreVelCoolRate = 0.0095, skinCoreConductance = 0.088,
        gripMultiplier = 1.04, longGripMult = 1.05, latGripMult = 1.02, loadSensitivity = 0.040,
        optimalPressure = 31, optimalTemp = 76, pressureSensitivity = 0.75, rollingRes = 0.70,
        staticCoolingRate = 0.044, slipHeatRate = 16.6, workHeatRate = 10.2, wearRate = 0.0028,
        treadInertia = 0.441, carcassInertia = 0.714, thermalReactionRate = 1.3, tempPlateau = 14,
        coldWidth = 52, hotWidth = 32, gripFloor = 0.24, coldWearMult = 1.908,
        hotWearMult = 5.60, grainTempRatio = 0.88, blisterTempRatio = 1.22, waterDrainage = 0.58,
        wetGripScale = 0.995, dryGripScale = 1.04, trackConductivityMult = 0.75, camberSensitivity = 1.1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.15, skinVelCoolScale = 0.50, workHeatG0 = 0.04
    } },
    { tread = 0.40, profile = "track_day", mods = {
        -- Track Day HEAT+WEAR LOCKED (Belasco). Between Plus and Hard C2; street purpose.
        -- HEAT v3: slip 10.9 / work 6.20, opt 76, cooling held. Slight abuse overshoot only.
        -- GRIP v2: gm/dry 1.04, long 1.08, lat 1.0, loadSens 0.042. Poly 1.15 (~Plus+2%).
        -- Wear LOCKED (#1): 0.0033 (was immortal 0.00073; first-cut above Plus 0.0028 / ~1.5%).
        -- Character + drive soft-cap = Plus→Hard lerp. Do not nudge heat/wear.
        adhesion = 0.444, airConductionRate = 0.015, airCoolingRate = 0.020, brakeGainRate = 1.32,
        casingCompliance = 0.42, coreCoolRate = 0.036, coreVelCoolRate = 0.0083, skinCoreConductance = 0.090,
        gripMultiplier = 1.04, longGripMult = 1.08, latGripMult = 1.0, loadSensitivity = 0.042,
        optimalPressure = 31, optimalTemp = 76, pressureSensitivity = 0.71, rollingRes = 0.88,
        staticCoolingRate = 0.068, slipHeatRate = 10.9, workHeatRate = 6.20, wearRate = 0.0033,
        treadInertia = 0.471, carcassInertia = 0.763, thermalReactionRate = 1.22, tempPlateau = 16,
        coldWidth = 64, hotWidth = 52, gripFloor = 0.28, coldWearMult = 1.84,
        hotWearMult = 3.05, grainTempRatio = 0.76, blisterTempRatio = 1.59, waterDrainage = 0.43,
        wetGripScale = 0.90, dryGripScale = 1.04, trackConductivityMult = 0.90, camberSensitivity = 1.18,
        bottomOutSensitivity = 1.04, scrubSensitivity = 1.28, skinVelCoolScale = 0.80, workHeatG0 = 0.148
    } },
    { tread = 0.50, profile = "sport", mods = {
        -- Sport HEAT+WEAR LOCKED. Heat: v7 + tiny bump, Belasco native sport, Track 15°C.
        -- v7 cruise ~53 / 59 / 60 / 61 vs opt 66 (F≪R). Tiny bump ~3% slip/work 9.40/5.45 → 9.68/5.61.
        -- velCool 0.72, workHeatG0 0.16, airCool 0.020, static 0.065, DRIVE 0.92/0.95/0.87 held.
        -- Wear LOCKED (#1b): 0.0026. 22 km ~0.6–0.9% vs target ~0.8% (under Plus 0.0028 / ~1.5%). Grip v6 held.
        adhesion = 0.42, airConductionRate = 0.015, airCoolingRate = 0.020, brakeGainRate = 1.2,
        casingCompliance = 0.5, coreCoolRate = 0.035, coreVelCoolRate = 0.008, skinCoreConductance = 0.076,
        gripMultiplier = 1.00, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.036,
        optimalPressure = 33, optimalTemp = 66, pressureSensitivity = 0.55, rollingRes = 0.82,
        staticCoolingRate = 0.065, slipHeatRate = 9.68, workHeatRate = 5.61, wearRate = 0.0026,
        treadInertia = 0.483, carcassInertia = 0.782, thermalReactionRate = 1.2, tempPlateau = 18,
        coldWidth = 74, hotWidth = 55, gripFloor = 0.34, coldWearMult = 1.83,
        hotWearMult = 2.98, grainTempRatio = 0.88, blisterTempRatio = 1.55, waterDrainage = 0.72,
        wetGripScale = 1.03, dryGripScale = 1.02, trackConductivityMult = 1, camberSensitivity = 1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.1, skinVelCoolScale = 0.72, workHeatG0 = 0.16
    } },
    { tread = 0.60, profile = "standard", mods = {
        -- Mid sport↔standard (common passenger treadCoef ~0.55–0.65).
        -- Pass 5: modest slip/work cut (~6%).
        adhesion = 0.41, airConductionRate = 0.01425, airCoolingRate = 0.02575, brakeGainRate = 1.05,
        casingCompliance = 0.55, coreCoolRate = 0.03675, coreVelCoolRate = 0.0084, skinCoreConductance = 0.072,
        gripMultiplier = 1.00, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.0355,
        optimalPressure = 33, optimalTemp = 63, pressureSensitivity = 0.50, rollingRes = 0.82,
        staticCoolingRate = 0.0765, slipHeatRate = 8.25, workHeatRate = 4.85, wearRate = 0.000475,
        treadInertia = 0.4935, carcassInertia = 0.799, thermalReactionRate = 1.225, tempPlateau = 17,
        coldWidth = 66, hotWidth = 55, gripFloor = 0.30, coldWearMult = 1.80,
        hotWearMult = 2.99, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.76,
        wetGripScale = 1.04, dryGripScale = 1.01, trackConductivityMult = 1, camberSensitivity = 0.95,
        bottomOutSensitivity = 1, scrubSensitivity = 1.05
    } },
    { tread = 0.70, profile = "standard", mods = {
        -- Modest overall μ bump (~+4% gm): street default; asphalt>loose gap via applyProfileSurfaceBias
        -- (street-family dry*1.02 / gravel|dirt*0.90 / mud*0.86) — not another global gm change.
        -- Pass 5: modest slip/work cut (~6%).
        adhesion = 0.4, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
        casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
        gripMultiplier = 1.00, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.035,
        optimalPressure = 33, optimalTemp = 60, pressureSensitivity = 0.45, rollingRes = 0.82,
        staticCoolingRate = 0.08, slipHeatRate = 7.9, workHeatRate = 4.8, wearRate = 0.0005,
        treadInertia = 0.504, carcassInertia = 0.816, thermalReactionRate = 1.25, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 3, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.9,
        bottomOutSensitivity = 1, scrubSensitivity = 1
    } },
    { tread = 0.80, profile = "allterrain", mods = {
        adhesion = 0.36, airConductionRate = 0.012, airCoolingRate = 0.0325, brakeGainRate = 0.45,
        casingCompliance = 0.75, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.056,
        gripMultiplier = 0.86, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.03,
        optimalPressure = 30, optimalTemp = 56, pressureSensitivity = 0.35, rollingRes = 1.18,
        staticCoolingRate = 0.08, slipHeatRate = 7.2, workHeatRate = 4.5, wearRate = 0.00025,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.05, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.9, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 0.7, scrubSensitivity = 0.9
    } },
    { tread = 0.85, profile = "allterrain", mods = {
        -- Mid AT↔MT (JBeam tread often lands ~0.82–0.88 between AT and MT nameplates).
        adhesion = 0.34, airConductionRate = 0.01125, airCoolingRate = 0.035, brakeGainRate = 0.375,
        casingCompliance = 0.775, coreCoolRate = 0.04725, coreVelCoolRate = 0.0108, skinCoreConductance = 0.048,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.028,
        optimalPressure = 28, optimalTemp = 54, pressureSensitivity = 0.315, rollingRes = 1.30,
        staticCoolingRate = 0.08, slipHeatRate = 6.75, workHeatRate = 4.2, wearRate = 0.000225,
        treadInertia = 0.630, carcassInertia = 1.020, thermalReactionRate = 1.0, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.725,
        hotWearMult = 2.89, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.925,
        wetGripScale = 1.12, dryGripScale = 0.97, trackConductivityMult = 0.75, camberSensitivity = 0.55,
        bottomOutSensitivity = 0.65, scrubSensitivity = 0.85
    } },
    { tread = 0.90, profile = "mudterrain", mods = {
        adhesion = 0.32, airConductionRate = 0.0105, airCoolingRate = 0.0375, brakeGainRate = 0.3,
        casingCompliance = 0.8, coreCoolRate = 0.049, coreVelCoolRate = 0.0112, skinCoreConductance = 0.04,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.026,
        optimalPressure = 26, optimalTemp = 52, pressureSensitivity = 0.28, rollingRes = 1.42,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.9, wearRate = 0.0002,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.95, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.88, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    } },
    { tread = 1.00, profile = "crawler", mods = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.85, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,
        gripMultiplier = 0.78, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 9, optimalTemp = 48, pressureSensitivity = 0.18, rollingRes = 1.7,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3.3, wearRate = 0.00015,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.9, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 1,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    } }
}

-- CONTINUOUS SLICK COMPOUND SPECTRUM: Chemically Decoupled Racing Compounds
-- WC stint pass: cut slip/work heat + wear/hotWear so GT4 slicks survive many hotlaps;
-- blister/leak reserved for abuse. sport_plus / PROFILE_POINTS untouched.
-- Softness midpoints (0.575 / 0.725) densify hard↔medium↔soft without new fantasy compounds.
local SLICK_SPECTRUM_POINTS = {
    { softness = 0.50, profile = "hard_slick", mods = {
        -- Hard C2 WEAR+HEAT LOCKED (#2 accepted): Soft-like ~62/74/79/86 vs opt 90; wear
        -- ~0.9–1.4% @~22 km. velCool 0.50, workHeatG0 0.04, slip/work 13.5/7.8, rolling 50.
        -- Soft+Medium locked. Do not nudge.
        adhesion = 0.48, airConductionRate = 0.015, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.3, coreCoolRate = 0.038, coreVelCoolRate = 0.0088, skinCoreConductance = 0.110,
        gripMultiplier = 0.96, longGripMult = 1, latGripMult = 0.74, loadSensitivity = 0.11,
        optimalPressure = 28, optimalTemp = 90, pressureSensitivity = 0.95, rollingRes = 0.98,
        staticCoolingRate = 0.060, slipHeatRate = 13.5, workHeatRate = 7.8, wearRate = 0.00115,
        rollingWearCoef = 50,
        treadInertia = 0.4536, carcassInertia = 0.7344, thermalReactionRate = 1.25, tempPlateau = 14,
        coldWidth = 48, hotWidth = 48, gripFloor = 0.20, coldWearMult = 1.86,
        hotWearMult = 3.15, grainTempRatio = 0.78, blisterTempRatio = 1.65, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.55, skinVelCoolScale = 0.50, workHeatG0 = 0.04
    } },
    { softness = 0.575, profile = "hard_slick", mods = {
        -- Hard mid-anchor LOCKED (same #2 package as 0.50). Soft+Medium locked. Do not nudge.
        adhesion = 0.50, airConductionRate = 0.01575, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.275, coreCoolRate = 0.0345, coreVelCoolRate = 0.008, skinCoreConductance = 0.115,
        gripMultiplier = 0.99, longGripMult = 1, latGripMult = 0.73, loadSensitivity = 0.115,
        optimalPressure = 27.5, optimalTemp = 87, pressureSensitivity = 1.0, rollingRes = 1.00,
        staticCoolingRate = 0.060, slipHeatRate = 14.0, workHeatRate = 8.1, wearRate = 0.00130,
        rollingWearCoef = 55,
        treadInertia = 0.4263, carcassInertia = 0.6902, thermalReactionRate = 1.335, tempPlateau = 14,
        coldWidth = 47, hotWidth = 47, gripFloor = 0.20, coldWearMult = 1.905,
        hotWearMult = 3.225, grainTempRatio = 0.78, blisterTempRatio = 1.65, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.60, skinVelCoolScale = 0.50, workHeatG0 = 0.04
    } },
    { softness = 0.65, profile = "medium_slick", mods = {
        -- Medium C3 WEAR+HEAT LOCKED: Soft-like settle ~59/70s/~80/~83 vs opt 84 (Track 15°C).
        -- velCool 0.60, workHeatG0 0.04, slip/work 15/8.6, rollingWearCoef 42. Soft 0.80 locked.
        -- Do not nudge.
        adhesion = 0.52, airConductionRate = 0.0165, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.25, coreCoolRate = 0.031, coreVelCoolRate = 0.0072, skinCoreConductance = 0.120,
        gripMultiplier = 1.02, longGripMult = 1, latGripMult = 0.72, loadSensitivity = 0.12,
        optimalPressure = 27, optimalTemp = 84, pressureSensitivity = 1.05, rollingRes = 1.02,
        staticCoolingRate = 0.060, slipHeatRate = 15.0, workHeatRate = 8.6, wearRate = 0.00135,
        rollingWearCoef = 42,
        treadInertia = 0.399, carcassInertia = 0.646, thermalReactionRate = 1.42, tempPlateau = 14,
        coldWidth = 46, hotWidth = 46, gripFloor = 0.20, coldWearMult = 1.95,
        hotWearMult = 3.30, grainTempRatio = 0.78, blisterTempRatio = 1.65, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.65, skinVelCoolScale = 0.60, workHeatG0 = 0.04
    } },
    { softness = 0.725, profile = "medium_slick", mods = {
        -- Medium mid-anchor LOCKED (same package as 0.65). Soft 0.80 untouched. Do not nudge.
        adhesion = 0.535, airConductionRate = 0.016875, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.235, coreCoolRate = 0.031, coreVelCoolRate = 0.0074, skinCoreConductance = 0.122,
        gripMultiplier = 1.05, longGripMult = 1, latGripMult = 0.71, loadSensitivity = 0.125,
        optimalPressure = 26.5, optimalTemp = 83, pressureSensitivity = 1.125, rollingRes = 1.05,
        staticCoolingRate = 0.060, slipHeatRate = 15.5, workHeatRate = 8.9, wearRate = 0.00155,
        rollingWearCoef = 48,
        treadInertia = 0.3717, carcassInertia = 0.6018, thermalReactionRate = 1.485, tempPlateau = 14,
        coldWidth = 45, hotWidth = 45, gripFloor = 0.19, coldWearMult = 1.971,
        hotWearMult = 3.375, grainTempRatio = 0.78, blisterTempRatio = 1.635, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.50,
        bottomOutSensitivity = 1.15, scrubSensitivity = 1.70, skinVelCoolScale = 0.60, workHeatG0 = 0.04
    } },
    { softness = 0.80, profile = "soft_slick", mods = {
        -- Soft C4 WEAR+HEAT LOCKED (accepted): rollingWearCoef=70, airCool 0.014,
        -- skinVelCoolScale=0.85, workHeatG0=0.04. Do not nudge; F<R on RWD+DF @ Track 15°C is real.
        adhesion = 0.55, airConductionRate = 0.01725, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.22, coreCoolRate = 0.031, coreVelCoolRate = 0.0076, skinCoreConductance = 0.130,
        gripMultiplier = 1.08, longGripMult = 1, latGripMult = 0.70, loadSensitivity = 0.13,
        optimalPressure = 26, optimalTemp = 82, pressureSensitivity = 1.2, rollingRes = 1.22,
        staticCoolingRate = 0.060, slipHeatRate = 17.5, workHeatRate = 9.8, wearRate = 0.00255,
        rollingWearCoef = 70,
        treadInertia = 0.3444, carcassInertia = 0.5576, thermalReactionRate = 1.55, tempPlateau = 14,
        coldWidth = 44, hotWidth = 44, gripFloor = 0.18, coldWearMult = 2.35,
        hotWearMult = 4.70, grainTempRatio = 0.78, blisterTempRatio = 1.62, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.55,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.75, skinVelCoolScale = 0.85, workHeatG0 = 0.04
    } },
    { softness = 0.875, profile = "supersoft_slick", mods = {
        -- Supersoft C5: one 0.075 step past Soft C4 (qualify). Peakier, hotter, shorter life.
        -- Stock JBeam 1.0 still remaps to 0.80 C4; this anchor is only softnessCoef=0.875.
        adhesion = 0.565, airConductionRate = 0.017625, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.205, coreCoolRate = 0.031, coreVelCoolRate = 0.0078, skinCoreConductance = 0.138,
        gripMultiplier = 1.11, longGripMult = 1, latGripMult = 0.69, loadSensitivity = 0.135,
        optimalPressure = 25.5, optimalTemp = 80, pressureSensitivity = 1.275, rollingRes = 1.39,
        staticCoolingRate = 0.060, slipHeatRate = 19.5, workHeatRate = 10.7, wearRate = 0.00355,
        rollingWearCoef = 92,
        treadInertia = 0.3171, carcassInertia = 0.5134, thermalReactionRate = 1.615, tempPlateau = 14,
        coldWidth = 43, hotWidth = 43, gripFloor = 0.17, coldWearMult = 2.73,
        hotWearMult = 6.025, grainTempRatio = 0.78, blisterTempRatio = 1.59, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.60,
        bottomOutSensitivity = 1.25, scrubSensitivity = 1.80, skinVelCoolScale = 1.00, workHeatG0 = 0.04
    } }
}

-- CONTINUOUS LIGHT & MEDIUM DUTY SPECTRUM: Heavy Pickups, Vans, and Utility Cargo Rigs
local UTILITY_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "highway_utility_utility", mods = {
        adhesion = 0.4, airConductionRate = 0.01275, airCoolingRate = 0.02875, brakeGainRate = 0.6,
        casingCompliance = 0.3, coreCoolRate = 0.0403, coreVelCoolRate = 0.0092, skinCoreConductance = 0.064,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.022,
        optimalPressure = 44, optimalTemp = 60, pressureSensitivity = 0.32, rollingRes = 0.84,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 4.2, wearRate = 0.00032,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 2.928, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.3, scrubSensitivity = 1.1
    } },
    { tread = 0.60, profile = "highway_utility_utility", mods = {
        adhesion = 0.38, airConductionRate = 0.012375, airCoolingRate = 0.03, brakeGainRate = 0.5625,
        casingCompliance = 0.325, coreCoolRate = 0.04205, coreVelCoolRate = 0.0092, skinCoreConductance = 0.060,
        gripMultiplier = 0.87, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.024,
        optimalPressure = 40, optimalTemp = 58, pressureSensitivity = 0.30, rollingRes = 0.96,
        staticCoolingRate = 0.08, slipHeatRate = 7.612, workHeatRate = 4.05, wearRate = 0.00027,
        treadInertia = 0.609, carcassInertia = 0.986, thermalReactionRate = 1.225, tempPlateau = 17,
        coldWidth = 58, hotWidth = 52.5, gripFloor = 0.26, coldWearMult = 1.755,
        hotWearMult = 2.908, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.875,
        wetGripScale = 1.091, dryGripScale = 1, trackConductivityMult = 0.875, camberSensitivity = 0.75,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.05
    } },
    { tread = 0.70, profile = "allterrain_utility_utility", mods = {
        adhesion = 0.36, airConductionRate = 0.012, airCoolingRate = 0.03125, brakeGainRate = 0.525,
        casingCompliance = 0.35, coreCoolRate = 0.0438, coreVelCoolRate = 0.0092, skinCoreConductance = 0.056,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.026,
        optimalPressure = 36, optimalTemp = 56, pressureSensitivity = 0.28, rollingRes = 1.08,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 3.9, wearRate = 0.00022,
        treadInertia = 0.63, carcassInertia = 1.02, thermalReactionRate = 1.25, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.888, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1
    } },
    { tread = 0.85, profile = "mudterrain_utility_utility", mods = {
        adhesion = 0.32, airConductionRate = 0.01125, airCoolingRate = 0.03375, brakeGainRate = 0.45,
        casingCompliance = 0.4, coreCoolRate = 0.0473, coreVelCoolRate = 0.0108, skinCoreConductance = 0.048,
        gripMultiplier = 0.8, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.026,
        optimalPressure = 28, optimalTemp = 52, pressureSensitivity = 0.22, rollingRes = 1.35,
        staticCoolingRate = 0.08, slipHeatRate = 6.51, workHeatRate = 3.6, wearRate = 0.00018,
        treadInertia = 0.714, carcassInertia = 1.156, thermalReactionRate = 1.2, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.872, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 1, scrubSensitivity = 0.9
    } },
    { tread = 0.95, profile = "logger_utility_utility", mods = {
        adhesion = 0.3, airConductionRate = 0.0105, airCoolingRate = 0.03625, brakeGainRate = 0.375,
        casingCompliance = 0.45, coreCoolRate = 0.0508, coreVelCoolRate = 0.0116, skinCoreConductance = 0.04,
        gripMultiplier = 0.76, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.03,
        optimalPressure = 24, optimalTemp = 50, pressureSensitivity = 0.18, rollingRes = 1.55,
        staticCoolingRate = 0.08, slipHeatRate = 6.09, workHeatRate = 3.3, wearRate = 0.00014,
        treadInertia = 0.798, carcassInertia = 1.292, thermalReactionRate = 1.15, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.856, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.9, scrubSensitivity = 0.8
    } }
}

-- CONTINUOUS HEAVY-DUTY COMMERCIAL SPECTRUM: Peterbilts, Volvos, and Heavy Long-Haul Semis
local COMMERCIAL_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "highway_steer_truck", mods = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.03125, brakeGainRate = 0.225,
        casingCompliance = 0.12, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.011,
        optimalPressure = 105, optimalTemp = 62, pressureSensitivity = 0.1, rollingRes = 0.62,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 2.4, wearRate = 0.00006,
        treadInertia = 1.764, carcassInertia = 2.856, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.824, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.8, scrubSensitivity = 1.2
    } },
    { tread = 0.60, profile = "highway_trailer_truck", mods = {
        adhesion = 0.3, airConductionRate = 0.00825, airCoolingRate = 0.0325, brakeGainRate = 0.15,
        casingCompliance = 0.1, coreCoolRate = 0.056, coreVelCoolRate = 0.0128, skinCoreConductance = 0.036,
        gripMultiplier = 0.78, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.01,
        optimalPressure = 110, optimalTemp = 62, pressureSensitivity = 0.09, rollingRes = 0.58,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 2.16, wearRate = 0.00005,
        treadInertia = 2.184, carcassInertia = 3.536, thermalReactionRate = 1.1, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.82, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.9, scrubSensitivity = 1.2
    } },
    { tread = 0.70, profile = "traction_drive_truck", mods = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.0325, brakeGainRate = 0.225,
        casingCompliance = 0.15, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.014,
        optimalPressure = 95, optimalTemp = 62, pressureSensitivity = 0.13, rollingRes = 0.75,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 2.7, wearRate = 0.00008,
        treadInertia = 1.89, carcassInertia = 3.06, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.832, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.7, scrubSensitivity = 1.2
    } },
    { tread = 0.80, profile = "traction_drive_truck", mods = {
        adhesion = 0.325, airConductionRate = 0.009, airCoolingRate = 0.035, brakeGainRate = 0.225,
        casingCompliance = 0.165, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.038,
        gripMultiplier = 0.77, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.016,
        optimalPressure = 87.5, optimalTemp = 59, pressureSensitivity = 0.11, rollingRes = 0.90,
        staticCoolingRate = 0.08, slipHeatRate = 7.087, workHeatRate = 3.0, wearRate = 0.00010,
        treadInertia = 1.953, carcassInertia = 3.162, thermalReactionRate = 1.225, tempPlateau = 17,
        coldWidth = 58, hotWidth = 52.5, gripFloor = 0.26, coldWearMult = 1.695,
        hotWearMult = 2.840, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.875,
        wetGripScale = 1.085, dryGripScale = 0.97, trackConductivityMult = 0.875, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.55, scrubSensitivity = 1.15
    } },
    { tread = 0.90, profile = "heavy_offroad_truck", mods = {
        adhesion = 0.3, airConductionRate = 0.009, airCoolingRate = 0.0375, brakeGainRate = 0.225,
        casingCompliance = 0.18, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.036,
        gripMultiplier = 0.72, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 80, optimalTemp = 56, pressureSensitivity = 0.09, rollingRes = 1.05,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.00012,
        treadInertia = 2.016, carcassInertia = 3.264, thermalReactionRate = 1.25, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.848, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1.1
    } }
}

-- CONTINUOUS LIGHTWEIGHT SXS & UTV SPECTRUM: Hardpack, All-Terrain, and Deep Offroad Flotation Lugs
local ATV_UTV_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "hardpack_utv_utv", mods = {
        adhesion = 0.35, airConductionRate = 0.012, airCoolingRate = 0.0375, brakeGainRate = 0.45,
        casingCompliance = 0.8, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.04,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.055,
        optimalPressure = 14, optimalTemp = 55, pressureSensitivity = 0.25, rollingRes = 1.1,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 3.6, wearRate = 0.0025,
        treadInertia = 0.336, carcassInertia = 0.544, thermalReactionRate = 1.65, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 3.8, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    } },
    { tread = 0.60, profile = "hardpack_utv_utv", mods = {
        adhesion = 0.325, airConductionRate = 0.011625, airCoolingRate = 0.03875, brakeGainRate = 0.4125,
        casingCompliance = 0.825, coreCoolRate = 0.04725, coreVelCoolRate = 0.0108, skinCoreConductance = 0.038,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.0575,
        optimalPressure = 12, optimalTemp = 52.5, pressureSensitivity = 0.225, rollingRes = 1.175,
        staticCoolingRate = 0.08, slipHeatRate = 6.562, workHeatRate = 3.45, wearRate = 0.00215,
        treadInertia = 0.357, carcassInertia = 0.578, thermalReactionRate = 1.575, tempPlateau = 17,
        coldWidth = 58, hotWidth = 52.5, gripFloor = 0.26, coldWearMult = 1.695,
        hotWearMult = 3.66, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.085, dryGripScale = 1, trackConductivityMult = 0.875, camberSensitivity = 0.45,
        bottomOutSensitivity = 0.55, scrubSensitivity = 0.8
    } },
    { tread = 0.70, profile = "allterrain_utv_utv", mods = {
        adhesion = 0.3, airConductionRate = 0.01125, airCoolingRate = 0.04, brakeGainRate = 0.375,
        casingCompliance = 0.85, coreCoolRate = 0.049, coreVelCoolRate = 0.0112, skinCoreConductance = 0.036,
        gripMultiplier = 0.8, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.06,
        optimalPressure = 10, optimalTemp = 50, pressureSensitivity = 0.2, rollingRes = 1.25,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.0018,
        treadInertia = 0.378, carcassInertia = 0.612, thermalReactionRate = 1.5, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 3.52, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.8
    } },
    { tread = 0.85, profile = "mud_utv_utv", mods = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.9, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,
        gripMultiplier = 0.76, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.065,
        optimalPressure = 7, optimalTemp = 48, pressureSensitivity = 0.15, rollingRes = 1.4,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3, wearRate = 0.0014,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.35, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 3.36, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    } }
}

-- CONTINUOUS RETRO SPECTRUM: Flexible Cross-Ply Bias overlays up to Classic Radial Belts
-- Pass 5: lower race-like heat gen, more RR + thermal mass (historical rubber; no gm dump).
local VINTAGE_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "vintage_biasply_vintage", mods = {
        adhesion = 0.28, airConductionRate = 0.0135, airCoolingRate = 0.02375, brakeGainRate = 0.6,
        casingCompliance = 0.65, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,
        gripMultiplier = 0.92, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.042,
        optimalPressure = 24, optimalTemp = 56, pressureSensitivity = 0.45, rollingRes = 0.94,
        staticCoolingRate = 0.08, slipHeatRate = 6.5, workHeatRate = 5.7, wearRate = 0.0004,
        treadInertia = 0.50, carcassInertia = 0.82, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1.4
    } },
    { tread = 0.575, profile = "vintage_biasply_vintage", mods = {
        adhesion = 0.315, airConductionRate = 0.013875, airCoolingRate = 0.025, brakeGainRate = 0.675,
        casingCompliance = 0.60, coreCoolRate = 0.03765, coreVelCoolRate = 0.0086, skinCoreConductance = 0.076,
        gripMultiplier = 0.945, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.04,
        optimalPressure = 27, optimalTemp = 58, pressureSensitivity = 0.435, rollingRes = 0.91,
        staticCoolingRate = 0.08, slipHeatRate = 6.9, workHeatRate = 5.45, wearRate = 0.000475,
        treadInertia = 0.49, carcassInertia = 0.80, thermalReactionRate = 1.22, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.99, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.6,
        wetGripScale = 1.0, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.6,
        bottomOutSensitivity = 0.85, scrubSensitivity = 1.3
    } },
    { tread = 0.65, profile = "classic_radial_vintage", mods = {
        adhesion = 0.35, airConductionRate = 0.01425, airCoolingRate = 0.02625, brakeGainRate = 0.75,
        casingCompliance = 0.55, coreCoolRate = 0.0368, coreVelCoolRate = 0.0084, skinCoreConductance = 0.072,
        gripMultiplier = 0.97, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.038,
        optimalPressure = 30, optimalTemp = 60, pressureSensitivity = 0.42, rollingRes = 0.88,
        staticCoolingRate = 0.08, slipHeatRate = 7.4, workHeatRate = 5.05, wearRate = 0.00055,
        treadInertia = 0.48, carcassInertia = 0.78, thermalReactionRate = 1.28, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 3.02, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.7,
        wetGripScale = 1.025, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.7,
        bottomOutSensitivity = 0.9, scrubSensitivity = 1.2
    } }
}

-- Phase 4/5: stamp duty soft-cap magnitudes onto spectra / street-like standalones.
-- Street continuum: Sport HEAT LOCKED (own pack) → Plus → Track Day (Plus→Hard lerp). Hard C2 / slicks OFF.
-- Vintage gentler pack; drag/drift/rally keep DEFAULT 1.0 (purpose skips the enable path).
stampSpectrumDriveSoftcap(PROFILE_POINTS, function(name)
    if name == "sport_plus" then return DRIVE_SOFTCAP_SPORT_PLUS end
    if name == "track_day" then return DRIVE_SOFTCAP_TRACK_DAY end
    if name == "sport" then return DRIVE_SOFTCAP_SPORT end
    return DRIVE_SOFTCAP_STREET
end)
stampSpectrumDriveSoftcap(SLICK_SPECTRUM_POINTS, DRIVE_SOFTCAP_OFF)
stampSpectrumDriveSoftcap(UTILITY_SPECTRUM_POINTS, DRIVE_SOFTCAP_STREET)
stampSpectrumDriveSoftcap(COMMERCIAL_SPECTRUM_POINTS, DRIVE_SOFTCAP_STREET)
stampSpectrumDriveSoftcap(ATV_UTV_SPECTRUM_POINTS, DRIVE_SOFTCAP_STREET)
stampSpectrumDriveSoftcap(VINTAGE_SPECTRUM_POINTS, DRIVE_SOFTCAP_VINTAGE)
do
    -- Street-like duties only. Rally/drag/drift intentionally omit — purpose gate is the
    -- enable pack; magnitudes stay OFF so soft-sims don't depend on purpose alone for those.
    -- Vintage standalone uses gentler VINTAGE pack (not aggressive street debt floors).
    local streetLike = {
        crawler = true, paddle = true, truck = true, truck_offroad = true,
        heavy_duty = true, light_truck_std = true, light_truck_hd = true, winter = true,
        donut = true, rain = true,
    }
    for name, mods in pairs(STANDALONE_MODIFIERS) do
        if name == "vintage" then
            stampDriveSoftcap(mods, DRIVE_SOFTCAP_VINTAGE)
        elseif streetLike[name] then
            stampDriveSoftcap(mods, DRIVE_SOFTCAP_STREET)
        end
    end
end

-- Compound-character stamps (after soft-caps). Street continuum = NEUTRAL (today's constants);
-- sport/slick climb blister/stint/hot cliff; winter/rain stay NEUTRAL (wet behavior intact).
stampSpectrumCharacter(PROFILE_POINTS, function(name)
    if name == "sport_plus" then return CHARACTER_SPORT_PLUS end
    if name == "track_day" then return CHARACTER_TRACK_DAY end
    if name == "sport" then return CHARACTER_SPORT end
    return CHARACTER_NEUTRAL
end)
stampSpectrumCharacter(SLICK_SPECTRUM_POINTS, function(name, pt)
    local soft = (pt and pt.softness) or 0.65
    if soft >= 0.84 or name == "supersoft_slick" then return CHARACTER_SLICK_SUPERSOFT end
    if soft >= 0.75 or name == "soft_slick" then return CHARACTER_SLICK_SOFT end
    if soft >= 0.62 or name == "medium_slick" then return CHARACTER_SLICK_MED end
    return CHARACTER_SLICK_HARD
end)
stampSpectrumCharacter(UTILITY_SPECTRUM_POINTS, CHARACTER_NEUTRAL)
stampSpectrumCharacter(COMMERCIAL_SPECTRUM_POINTS, CHARACTER_NEUTRAL)
stampSpectrumCharacter(ATV_UTV_SPECTRUM_POINTS, CHARACTER_NEUTRAL)
stampSpectrumCharacter(VINTAGE_SPECTRUM_POINTS, CHARACTER_NEUTRAL)
do
    for name, mods in pairs(STANDALONE_MODIFIERS) do
        if name == "drag" then
            stampCharacterKnobs(mods, CHARACTER_DRAG)
        elseif name == "drift" then
            stampCharacterKnobs(mods, CHARACTER_DRIFT)
        else
            -- winter / rain / rally / utility / vintage / … keep absolute neutral feel
            stampCharacterKnobs(mods, CHARACTER_NEUTRAL)
        end
    end
end

M.DEFAULT_MODS = DEFAULT_MODS
M.STANDALONE_MODIFIERS = STANDALONE_MODIFIERS
M.PROFILE_POINTS = PROFILE_POINTS
M.SLICK_SPECTRUM_POINTS = SLICK_SPECTRUM_POINTS
M.UTILITY_SPECTRUM_POINTS = UTILITY_SPECTRUM_POINTS
M.COMMERCIAL_SPECTRUM_POINTS = COMMERCIAL_SPECTRUM_POINTS
M.ATV_UTV_SPECTRUM_POINTS = ATV_UTV_SPECTRUM_POINTS
M.VINTAGE_SPECTRUM_POINTS = VINTAGE_SPECTRUM_POINTS
M.purposeAllowsStreetSoftcap = purposeAllowsStreetSoftcap
M.GRIP_COEFFS = GRIP_COEFFS
return M
