-- lua/vehicle/extensions/auto/tireWearThermals.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

-- Toggle real-time log prints to the BeamNG game console (open with ~ key)
local DEBUG_THERMALS = false

local function tryRequire(modName, globalName)
    local ok, mod = pcall(require, modName)
    if ok and mod ~= nil then return mod end
    return _G[globalName or modName]
end
local beamstate = tryRequire("beamstate")
local fire = tryRequire("fire")

-- BeamNG spike-strip ground material ID (wheels.lua updateWheelsGFX puncture path).
-- OWNERSHIP: native wheels.lua owns spike pressure writes (wd.isPunctured →
-- setGroupPressure at wd.punctureLeakRate). ReSpin only tracks UI/condition and
-- must NOT call applyPressureLeakPa for the same group while isPunctured.
local SPIKE_STRIP_MATERIAL_ID = 32
-- sounds.lua scales slipEnergy ≈ *5e-6 for a 0..1 working range
local NATIVE_SLIP_ENERGY_SCALE = 0.000005
local NATIVE_SLIP_VEL_SCALE = 0.0125

-- Safe JSON fallback mapping
local jsonDecode = _G.jsonDecode or (json and json.decode) or function(str) return {} end
local deserialize = _G.deserialize or _G.unserialize or function(str) return nil end

local function decodeMailbox(raw)
    if raw == nil or raw == "" then return nil end
    local ok, decoded = pcall(deserialize, raw)
    if ok and type(decoded) == "table" then return decoded end
    ok, decoded = pcall(jsonDecode, raw)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

local function vecLen(vel)
    local fn = vel and vel.length
    if type(fn) ~= "function" then return nil end
    local ok, len = pcall(fn, vel)
    if ok and type(len) == "number" then return len end
end

-- Protected obj:method(...). Returns false when missing; else pcall results.
local function objPcall(name, ...)
    local fn = obj and obj[name]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

-- Same fence, but returns values only on success (nil / no values on miss/error).
local function objCall(name, ...)
    local ok, a, b, c, d = objPcall(name, ...)
    if not ok then return end
    return a, b, c, d
end

-- Local math and vector aliases for hot path performance
local quat, vec3 = _G.quat, _G.vec3
local quatFromDir = _G.quatFromDir or (type(_G.quat) == "table" and _G.quat.fromDir) or nil
local sensors = _G.sensors -- Localized sensor registry to eliminate global hot path lookups

-- Robust local math aliases to eliminate global namespace lookups on hot path calls
local min, max, abs, sqrt, exp, cos, sin, deg, acos, asin, pi = math.min, math.max, math.abs, math.sqrt, math.exp, math.cos, math.sin, math.deg, math.acos, math.asin, math.pi

-- Chassis speed (m/s) from obj:getVelocity — shared by airspeed ref + GFX sample.
local function objChassisSpeed()
    local len = vecLen(objCall("getVelocity"))
    return len and max(0, len) or 0
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Declare local tables instead of polluting the global namespace
local groundCache = { models = {}, lut = {} }
-- groundCache.models / .lut (tireWearThermalsGround.lua)

-- REALISTIC THERMAL CONSTANTS (BALANCED DEFAULT BASELINES)
local WORKING_TEMP = 85
local ENV_TEMP = 21
local TORQUE_ENERGY_MULTIPLIER = 0.25
local RUBBER_EMISSIVITY = 0.94
local STEFAN_BOLTZMANN = 5.670374e-8
local ASPHALT_CONDUCTIVITY = 1.35
local THERMAL_BOUNDARY_LAYER = 0.002
local CORE_REACTION_RATE = 0.08 -- Global carcass integration rate (was a dead per-profile knob)
-- 8-node thermal topology (Lua 1-based):
--   temp[1..3] skin L/C/R | temp[4..6] carcass L/C/R | temp[7] rim | temp[8] cavity air
-- Refinements (P0–P2): contact-patch heat fraction + free-belt cool bias; gated flex
-- warm-up into carcass; skin lateral conductance; dedicated airThermalInertia; cold-
-- biased dynamic skin/carcass grip blend. Packed table keeps CalcTyreWear upvalues safe.
local TEMP_NODE_COUNT = 8
local RIM_THERMAL_INERTIA = 1.35
local RIM_REACTION_RATE = 0.10
local RIM_CARCASS_CONDUCTANCE = 0.042
local RIM_AIR_CONDUCTANCE = 0.028
local CARCASS_LATERAL_CONDUCTANCE = 0.050
local THERMAL_TOPOLOGY = {
    -- P0-1: slip/work/torque heat deposits on patch-resident arc; free belt cools more
    -- Phase B: street Hertz F/P often yields rawFrac≈0.04–0.07; old Min=0.09 glued heatScale.
    -- Heat uses softer floor (patchFracHeatMin); free-belt/display keep patchFracMin.
    -- Path A5: freer floors after A3/A4; street Hertz≈0.045 → heatScale≈0.66 (still ~0.64 band)
    -- Path A6 (Soft C4 WCU): slip/work/airCool/RR stacks weak after Phase1+2 unmute — pin is
    --   patchHeatScale attenuating ALL frictionalGain. Fronts still Hertz-starved near floor.
    patchFracMin = 0.032,      -- geometric/cool floor (was 0.035)
    patchFracHeatMin = 0.026,  -- was 0.022; keep heatMin/ref ratio ~0.60 under A6 ref
    patchFracMax = 0.22,       -- high-downforce / deep-defl ceiling
    -- Pass 7j: Pitwall hard_slick WCU — fronts pegged patchHeatScale 0.40 (Hertz under heatMin);
    -- raise floor + lower patchFracRef so skin frictionalGain isn't permanently halved.
    -- Path A6: Soft C4 4-lap stuck ~57/69/73/80 vs opt 82 — lower ref again so mid Hertz isn't ~0.6×.
    patchFracRef = 0.043,      -- was 0.050; raw ~0.032 → ~0.74 before floor (was ~0.64)
    patchHeatEmaTau = 0.10,    -- s; light EMA on patchHeatScale (depth EMA alone insufficient)
    freeBeltCoolMult = 1.00,   -- convection boost as freeFrac → 1 (was 1.32; Pass 7f)
    -- P0-2: gated flex/hysteresis into carcass (cruise RR soft-cap still owns straights)
    -- Coast-axle / undriven warm-up folded into flexWarm (no separate undrivenRrMult).
    flexWarmGain = 0.00125,    -- was 0.00108; absorbs former ~1.18 coast-axle RR into gated flex
    flexWarmLoad0 = 120,       -- load_kg gate start
    flexWarmLoad1 = 400,       -- load_kg gate full
    flexWarmSpeed0 = 2.0,      -- m/s freestream gate start
    flexWarmSpeed1 = 20.0,     -- m/s gate full
    flexWarmG0 = 0.24,         -- mild corner work opens earlier (straights still choked)
    -- Skin slip/work scale (compound slipHeatRate/workHeatRate own stint warm-up; no WC fudge)
    -- Pass 7f: WCU Scintilla GT3 — scale 1.60 ≈ no lift (slip/work add-on minority of
    --   skin heat); cut free-belt cool bias; revert skinSlipWorkScale to 1.0.
    skinSlipWorkScale = 1.0,
    -- Excess propulsion: open drive heat on hard throttle (RWD track accel) without Belasco cruise cook
    -- Pass 2: cruiseNm 650→480, excessFullNm 1100→850, skin 0.021→0.030, hyst 1.1e-7→1.9e-7,
    --   flexExcess@gate>0.3; rears still cold on Scintilla.
    -- Pass 3 (aggressive; did not overshoot on drive-heat retest):
    --   cruiseNm 480→280, excessFullNm 850→520, skin 0.030→0.058 (>> brake 0.025),
    --   hystExcess 1.9e-7→5e-7, flexExcess↑ + gate 0.3→0.15, slip/work ×1.22@gate=1,
    --   cruise choke softens above half cruiseNm (idle/coast still ×0.15).
    -- Pass 4 (small ~10–20% bump; not another pass-3 jump):
    --   cruiseNm 280→250, skin 0.058→0.066, hystExcess 5e-7→6e-7,
    --   flexExcess 0.00048→0.00054 + gate 0.15→0.12, slip/work ×1.22→×1.28.
    -- Pass 5 (soft-cap debt paydown): cut root excess drive heat so street soft-cap floors
    --   can move toward 1.0. Walks back Pass 4 + partial Pass 3 (not a full Pass-2 restore).
    --   cruiseNm 250→310, excessFull 520→560, skin 0.066→0.048, hystExcess 6e-7→3.8e-7,
    --   flexExcess 0.00054→0.00040 + gate 0.12→0.18, slip/work ×1.28→×1.14.
    -- Pass 6 (soft-cap debt paydown #2): modest further root cut (smaller step than Pass 5)
    --   so soft-cap floors can move closer to 1.0. Path A untouched.
    --   cruiseNm 310→340, excessFull 560→585, skin 0.048→0.041, hystExcess 3.8e-7→3.1e-7,
    --   flexExcess 0.00040→0.00034 + gate 0.18→0.21, slip/work ×1.14→×1.08.
    -- Pass 7: small restore of drive-torque skin heat for high-power / low-slip drive
    --   axles after Pass 5/6 root cut (colder rear warm-up). Soft-cap floors untouched.
    --   cruiseNm 340→305, skin 0.041→0.052, slip/work ×1.08→×1.16.
    -- Pass 7b: skinCoef 0.052→0.062 toward Pass-4 (0.066) after WCU live test —
    --   fronts warm via brake/scrub, rears still cold; soft-cap floors still untouched.
    -- Pass 7c: cruiseNm 305→275 — open excessPropGate earlier after WCU live test
    --   (ΔT still 15–19° cold rears; hold skinCoef 0.062; soft-cap floors untouched).
    -- Pass 7d: WCU Scintilla+GT3 slick — both axles under opt + F/R ΔT; raise shared slip/work
    --   + ease Pass-6 slick drive scales; soft-cap floors untouched.
    drivePropCruiseNm = 275,   -- |prop| floor (Nm/wheel); below → excess gate shut (was 305)
    drivePropExcessFullNm = 585,  -- span above cruise to excessGate=1 (was 560)
    drivePropSkinCoef = 0.062, -- skin netTorque prop scale (was 0.052; brake stays 0.025)
    drivePropHystBase = 5e-8,  -- torque hysteresis at excessGate=0
    drivePropHystExcess = 3.1e-7, -- torque hysteresis at excessGate=1 (was 3.8e-7)
    drivePropFlexGateStart = 0.21, -- excessFlex begins above this gate (was 0.18)
    drivePropFlexExcess = 0.00034, -- carcass flex add when excessGate>FlexGateStart (was 0.00040)
    drivePropSlipWorkMult = 1.16, -- skin slip/work scale at excessGate=1 (1=off; driven via prop)
    -- Slick/race spectrum only: Pass 3/4 excess drive heat was tuned for sport_plus (Scintilla).
    -- Historical GT4/RWD overcook used slick-only mutes (0.52/0.29 → 0.60/0.34). Phase 1:
    -- unmute to 1.0 — character moves to SLICK_SPECTRUM / Soft C4 live A/B (balance mutes → profiles).
    -- sport_plus / street already 1.0; burnout slipVelBoost unchanged. Path A patch math kept.
    drivePropSlickScale = 1.0,            -- was 0.60; Phase 1 Soft C4 A/B (no slick drive mute)
    drivePropSlickCarcassScale = 1.0,     -- was 0.34; Phase 1 Soft C4 A/B (no slick carcass mute)
    -- Phase 2 Soft C4: unmute Belasco cruise balance mutes (character → profiles / live).
    -- Was hardcoded cruiseRR 0.48/0.72 and driveHeatGate choke floor 0.15.
    cruiseRrScaleFull = 1.0,             -- was 0.48 (low slip+g+no brake RR)
    cruiseRrScalePartial = 1.0,          -- was 0.72 (mild slip/g band)
    cruiseDriveChokeMin = 1.0,           -- was 0.15; 1.0 = straight cruise choke off
    -- Street/non-slick high-V + residual-slip soft-cap ENABLE gates (magnitudes on profiles):
    -- driveHighVCarcassScale / driveSlipHeatMin / driveSlipPropMin live on mods tables.
    -- Phase 5: purposeAllowsStreetSoftcap(purpose) must also pass (street/wet/winter/
    -- utility/commercial). Circuit/drag/drift/tarmac_rally/gravel never enable this path.
    -- Slicks already use drivePropSlickCarcassScale; high-V ramp only shapes freestream eligibility.
    drivePropStreetSpeed0 = 78.0,         -- m/s (~175 mph): street carcass damp begins
    drivePropStreetSpeed1 = 112.0,        -- m/s (~250 mph): full street carcass damp
    -- Street driven-wheel residual slip soft-cap ENABLE (FWD hard-accel cook):
    -- Soft-cap slip→skin (+ mild prop skin) only when: non-slick, driven (|prop|), rolling
    -- (not stationary burnout), and low lateral g (not drift/corner). Profile floors own strength;
    -- sport_plus milder floors live on sport_plus PROFILE_POINTS (not separate topo keys).
    driveStreetSlipSpeed0 = 3.5,          -- m/s freestream: below → full heat (burnout/launch)
    driveStreetSlipSpeed1 = 14.0,         -- m/s: full soft-cap eligibility (~30 mph)
    driveStreetSlipCapStart = 0.16,       -- slipEnergy where soft-cap begins
    driveStreetSlipCapFull = 0.52,        -- slipEnergy at full soft-cap
    driveStreetSlipG0 = 0.32,             -- g_mag: soft-cap starts fading (corner/drift)
    driveStreetSlipG1 = 0.58,             -- g_mag: soft-cap fully off
    -- P1 spectrum: mass-scale absolute Nm gates (Civic ≠ hypercar); AWD per-wheel excess damp.
    drivePropMassRefKg = 1500,            -- massScale = sqrt(mass/ref); Belasco GT≈1.0
    drivePropMassScaleMin = 0.78,         -- light hatch: gates open earlier
    drivePropMassScaleMax = 1.35,         -- heavy: raise cruise/excess floors (Belasco cruise safe)
    drivePropAwdExcessScale = 0.62,       -- excessPropGate mult when 4 driven (lerp from 2→4)
    drivePropDrivenThreshNm = 40,         -- |prop| counts wheel as driven for layout count
    -- FWD Soft-like topology LOCKED (accepted): FWD Soft edge case before damp FR/FL ~106/120
    -- Hot vs opt 82; after damp ~97 Normal (top of usable ~95–105). Keeps Hot under abuse.
    -- Layout-only: driveLayout=fwd + soft-like + driven front. Soft compound knobs untouched.
    -- RWD Soft Phase1 unmute stays 1.0. Do not nudge.
    drivePropFwdSoftScale = 0.58,         -- skin excess/drive mult when FWD + soft-like + driven front
    drivePropFwdSoftCarcassScale = 0.48,  -- carcass excess/hyst mult (same gate)
    drivePropFwdSoftSoftnessMin = 0.72,   -- remapped softness ≥ this, or soft_slick profile
    -- AWD Soft-like front damp LOCKED (#2 accepted): FR ~96 Normal (top of usable); FL ~109 Hot
    -- (brake soak ~620°C + harsh-drive ceiling — do not chase with more AwdSoft). Scales 0.45/0.38.
    -- Soft/FWD Soft/compound locks untouched. Do not nudge.
    drivePropAwdSoftScale = 0.45,         -- was 0.58 (#1)
    drivePropAwdSoftCarcassScale = 0.38,  -- was 0.48 (#1)
    -- P4 climate edges: mild direct solar→skin (track still owns bulk sun); wet film evaporative
    -- on tread (don't over-cool dry asphalt — film/rain gated).
    solarSkinGain = 0.026,                -- midday clear ≈ this frictionalGain-equivalent (speed-damped)
    solarSkinSpeedDamp = 0.05,            -- / (1 + v * damp); park soak > highway
    wetEvapSkinCoef = 0.014,              -- +tempDelta*coef*film into convection when wet/rain
    -- P1-1: skin L↔C↔R conductance (mirrors carcass); soft equalizer mostly retired
    skinLateralConductance = 0.042,
    skinEqualizerRetain = 0.05, -- leftover avg soft mix (was 0.20)
    -- P2: grip thermometer — more carcass when cold, skin-led in-window/hot
    gripBlendWarm = 0.18,      -- carcass share near/above opt
    gripBlendCold = 0.36,      -- carcass share when well below opt
    -- Fix A: gated |lastSlip| → longComp boost (burnout/lock smoke without cruise cook)
    -- Ramp is 0 below start (corner/cruise untouched); smoothstep to full by slipVelBoostFull.
    slipVelBoostStart = 8.0,   -- m/s |lastSlip| where boost begins
    slipVelBoostFull = 24.0,   -- m/s |lastSlip| at full boost (hard spin / lock slide)
    slipVelBoostMax = 9.0,     -- extra longComp mult at full (total = 1 + max*ramp)
    -- Extreme slip (lock slide / yaw spinout): saturate slidingWear so a few seconds
    -- of lock does not grind condition into cords-puncture (flatspot feature removed).
    -- Cruise slipEnergy ~0.2 is ~6% down; unbounded native slipEnergy can no longer dump condition.
    slideWearEnergySat = 0.35,
    -- Toe speed-cap: soft-saturation Vref (m/s). Scrub = v*sin(toe) / (1+v/Vref).
    -- At v=Vref scrub is half the linear extrapolation; effect persists at mid-high speed
    -- without a hard cliff. Raised from implicit 45 m/s hard-cap to 70 m/s soft-sat.
    toeScrubVref = 70.0,       -- m/s; real toe scrub saturates ~highway speed, not motorway
    -- Pressure→grip bands: see pressureNeutralHalf / pressureNormal* / pressureMild* below
    -- Aero: native triangle forces feed HUD/CSV (sampleNativeAero). Heat treats aero
    -- newtons in wd.downForce like weight (1 N = 1 N). aeroHeatScale 1.0 = no mute.
    -- 0.55 was a fake anti-cook shortcut (old speed×48% ramp). Do not bring it back
    -- without an explicit A/B; if GT3 cooks, fix RR/cool, not an aero fudge.
    aeroHeatScale     = 1.0,  -- realism: aero load→heat = mechanical
    aeroHeatSpeedStart = 15.0, -- m/s; only used if scale < 1
    aeroHeatSpeedFull  = 52.0, -- unused (old fake ramp)
    aeroHeatMaxFrac    = 0.48, -- cap if a mute is ever re-enabled
    -- Thermal oddities (carcass>>skin / spawn fight / elevation noise):
    skinCoreConductanceScale = 1.85, -- raise skin↔carcass coupling (keeps relative compound ranking)
    skinCoreConductanceFloor = 0.070, -- floor so ultra-low compounds still equilibrate
    carcassCoolVelCoef = 0.28,       -- was hardcoded 0.18 on coreVelCool term
    carcassCoolStaticCoef = 0.20,    -- was hardcoded 0.12 on coreCool term
    -- Phase C: bulk RR/flex → carcass; this leak warms skin WITHOUT × patchHeatScale
    -- (slip/work/torque already patch-scaled — avoid double-warm of hysteresis on the patch).
    -- Pass 7g: after 7f free-belt cut (skin flat, carcass +5°C), route more RR/flex heat
    --   to skin for WCU Scintilla GT3 under-opt test (0.21→0.28).
    hystSkinShare = 0.28,            -- RR/flex→skin (front warm without carcass cook)
    -- Pressure→grip bands (ratio error = currentPSI/hotTgt - 1). Hot tgt is seeded from
    -- native cold fill per pressure group (seedHotTargetPSI); spectrum optimalPressure is design.
    -- stock BeamNG cold fills often sit at/above opt, then Gay-Lussac warm pushes further over —
    -- so the normal OVER band is wider than under. pressureSensitivity scales mild + outer only.
    -- Neutral deadband near opt (no perfect-zone grip bonus); mild/outer still punish miss.
    pressureNeutralHalf = 0.04,      -- |offset| ≤ this → scale 1.0 (no bonus)
    pressureNormalUnder = 0.14,      -- under-pressure still "normal" (mild)
    pressureNormalOver = 0.32,       -- over-pressure still "normal" (asymmetric for stock highs)
    pressureMildBase = 0.028,        -- mild penalty at normal-band edge (before sens)
    pressureMildSens = 0.022,        -- +sens contribution to mild edge (≈3.9% @ sens 0.5)
    -- Behind-native coupling (contactDepth / ducts / pressure seed)
    -- BRAKE NON-GOALS (tire-side only — native owns rotors):
    --   * Do not replace/reimplement native brake thermals.
    --   * Do not write brakeTypeSurfaceCoolingCoef for duct boost (restore-only).
    --   * Do not own torque fade / pad μ / ABS; η is display + soft soak scale only.
    --   * No arcade brake-bite long-grip hack on this track.
    contactDepthEmaTau = 0.08,       -- s; short EMA so gravel/kerb depth doesn't jitter patchFrac
    patchHertzDeflBlend = 0.35,      -- max weight of deflection proxy vs Hertz F/P area
    patchDeflWidthFrac = 0.55,       -- effective width fraction of chord×width deflection area
    patchLatLoadNudge = 0.05,        -- mild live lateral (gy) nudge on L/R ring weights
    -- Path A3: peakForce / downForceRaw util → patchHeatScale (smoothed load keeps Hertz stable;
    --   contactDepth + patchHeatScale EMA still kill kerb jitter). Prefer raw load as util denom.
    patchUtilBlend = 0.20,           -- was 0.12; stronger useful coupling (not raw peak noise)
    patchUtilPeakLo = 0.82,          -- util clamp floor (was hardcoded 0.85)
    patchUtilPeakHi = 1.40,          -- util clamp ceil (was 1.35)
    -- Path A4: patch length prefers dynamicRadius vs static; clamp absurd deflation
    patchDynRadiusMinFrac = 0.55,    -- dynR floor as fraction of static radius
    patchDynRadiusMaxFrac = 1.06,    -- dynR ceil vs static (rare grow / squat)
    -- Phase D: soft sink / rough — conduction denom already; optional frictional heat damp
    softSinkHeatCoef = 1.2,          -- frictionalGain /= (1 + depth×coef + rough×roughCoef)
    softSinkRoughCoef = 0.35,
    softSinkHeatFloor = 0.72,        -- min damp mult (keep some heat on deep gravel)
    -- Path A1: wire unused GM fields into soft-sink / conduction (asphalt dry ≈ no-op:
    --   strength≈1, defaultDepth≈0, fluidDensity≈0, stribeck≈1). Soft/rough/wet diverge.
    softSinkDefaultDepthCoef = 2.2,  -- +GM defaultDepth into soft-sink heat denom
    softSinkStrengthRef = 1.0,       -- strength below ref → extra soft plough damp
    softSinkStrengthCoef = 0.40,
    softSinkFluidCoef = 0.0007,      -- fluidDensity (water~1000) → wet fluid heat damp
    softSinkStribeckRef = 1.0,       -- lower stribeckVelocity → mild sticky/wet damp
    softSinkStribeckCoef = 0.035,
    gmConductionDefaultDepthCoef = 2.5, -- +defaultDepth into track conduction denom
    gmConductionStrengthCoef = 0.30,
    gmConductionFluidCoef = 0.0005,
    -- Path A2: dual contactMaterialID2 blend (kerb+asphalt). Spike mat 32 excluded.
    dualContactBlend = 0.32,         -- secondary mat weight on μ/rough/soft GM fields
    dualContactWearBump = 0.18,      -- max wear bump when secondary is rougher
    brakeSurfSoak = 0.022,           -- was 0.016; P3 trail-brake rim feel (tire-side only)
    brakeCoreSoak = 0.0032,          -- was 0.0025; lag path still ≪ surf
    brakeEffSoakFloor = 0.92,        -- glazed/low-efficiency floor on soak scale (η soft only)
    brakeRadiantCoef = 2.8e-11,      -- was 2.2e-11; mild radiant bump with surf soak
    pressureColdRefreshTau = 2.5,    -- s; soft cold-fill refresh toward native when parked
    pressureTpmsDeadbandPsiS = 8.0,  -- |dP/dt| above this → active inflate/TPMS; skip cold refresh / hot WB
    pressureColdRefreshParkedOnly = true, -- never adopt native while rolling (cold slicks never leave 8K window)
    pressureColdRefreshMaxSpeed = 4.0, -- m/s vehicle speed; hop/airborne frames are NOT "parked"
    -- Safe hot PSI → native pressure-group write-back (Gay-Lussac → soft-body stiffness).
    -- Native BeamNG has no thermo→PSI; ReSpin rate-limits so warm tires stiffen without slam/TPMS fight.
    pressureHotWritebackEnable = true,       -- master switch (ON with conservative rate/deadband)
    pressureHotWritebackMaxPsiS = 0.35,      -- max |ΔPSI|/s toward Lua hot target (slow approach)
    pressureHotWritebackRecoverPsiS = 2.5,   -- faster pull-down when native is well above thermal PSI
    pressureHotWritebackDeadbandPsi = 0.15,  -- skip setGroupPressure when |Lua−Nat| below this
}
local topo = THERMAL_TOPOLOGY -- module-level alias; avoids one function local in CalcTyreWear

-- REALISM FEATURE FLAGS (safe defaults for BeamNG 0.35–0.38 compatibility)
local MAX_DUCT_AIR_FACTOR = 1.45       -- Max tyre/rim air-cooling boost at 100% duct open (NOT native rotors)
local DUCT_DEFAULT_PCT = 1             -- Tuning default: closed (stock cars have no ducts)
local SLICK_PREHEAT_BLEND = 0.25       -- Race slicks: mild blanket preheat toward optTemp
local STREET_PREHEAT_BLEND = 0.34      -- Street/garage soak (was 0.50; reduced to ease spawn cool fight)
local SKIN_PREHEAT_FRAC = 0.55         -- Skin starts cooler than carcass (blend*frac); carcass keeps soak
local SPAWN_CONV_GRACE_S = 14.0        -- Soften freestream convection for first N seconds after init
local ENV_SMOOTH_RATE = 0.40           -- 1/s toward raw env (was dt*2.0 ≈ tau 0.5s; now ~2.5s)
local ENV_MAX_DELTA_PER_SEC = 2.5      -- Clamp |dEnv/dt| so altitude/mailbox spikes don't yank skin
-- (telemetry locals moved into telem table below)
-- Lockup: full-ring slide heat is physically wrong (recovery μ floor removed — felt like ABS).
local LOCKUP_OMEGA_THRESH = 1.0        -- rad/s — below this, treat as locking/locked
local LOCKUP_HEAT_FLOOR = 0.22         -- Cap lock-slide tread cook; not full L/C/R heat

-- UI streaming throttling (30 Hz): queueStream-only + cached hasQueueStream keeps flush cheap.
-- Single vehicle stream rate for all apps — 15 Hz felt laggy; 30 Hz restores snappy HUD feel.
local sendTimer = 0
local SEND_INTERVAL = 1.0 / 30.0 -- ~0.0333 s = 30 Hz
-- Cached once in onInit: prefer queueStream alone (0.39+); else trigger. Avoid per-flush type() checks.
local hasQueueStream = false
local hasGuiTrigger = false

-- FIXED-TIMESTEP SIMULATION ACCUMULATOR (Locks GFX-rate physical integration to a constant 100Hz)
local gfxAccumulator = 0
local FIXED_DT = 0.01 -- 0.01 seconds = 100Hz stable time step
-- Grip/friction at half rate (50Hz): thermals stay smooth; friction API is heavier than ΔT
local GRIP_STEP_INTERVAL = 2
local gripStepCounter = 0
-- Bump bands for thermal PSI bump-vol + grip (live suspension sim lives in tireWearThermalsWheel.lua)
local SUSP_SOFT_BUMP_M = 0.022
local SUSP_HARD_BUMP_M = 0.065

-- Hot-path scratch buffers (vehicle Lua is single-threaded; avoids per-step table alloc)
local scratchSkinSnap = { 0, 0, 0 }
local scratchCarcassSnap = { 0, 0, 0 }
local scratchCarcassWeights = { 0, 0, 0 }

--[[
  Compound tables live in lua/vehicle/extensions/tireWearThermalsProfiles.lua
  (schema, DEFAULT_MODS, spectra, standalones, load-time stamps). THERMAL_TOPOLOGY
  stays here so the hot chunk can upvalue it without another require on the 100 Hz path.
]]
local DEFAULT_MODS, STANDALONE_MODIFIERS, PROFILE_POINTS, GRIP_COEFFS
local SLICK_SPECTRUM_POINTS, UTILITY_SPECTRUM_POINTS, COMMERCIAL_SPECTRUM_POINTS
local ATV_UTV_SPECTRUM_POINTS, VINTAGE_SPECTRUM_POINTS
local purposeAllowsStreetSoftcap
do
    local P = require("tireWearThermalsProfiles")
    DEFAULT_MODS = P.DEFAULT_MODS
    STANDALONE_MODIFIERS = P.STANDALONE_MODIFIERS
    PROFILE_POINTS = P.PROFILE_POINTS
    GRIP_COEFFS = P.GRIP_COEFFS
    SLICK_SPECTRUM_POINTS = P.SLICK_SPECTRUM_POINTS
    UTILITY_SPECTRUM_POINTS = P.UTILITY_SPECTRUM_POINTS
    COMMERCIAL_SPECTRUM_POINTS = P.COMMERCIAL_SPECTRUM_POINTS
    ATV_UTV_SPECTRUM_POINTS = P.ATV_UTV_SPECTRUM_POINTS
    VINTAGE_SPECTRUM_POINTS = P.VINTAGE_SPECTRUM_POINTS
    purposeAllowsStreetSoftcap = P.purposeAllowsStreetSoftcap
end

local Surface = require("tireWearThermalsSurface")
local Aero = require("tireWearThermalsAero")
local Telemetry = require("tireWearThermalsTelemetry")
local Temp = require("tireWearThermalsTemp")
local Draft = require("tireWearThermalsDraft")
local Classify = require("tireWearThermalsClassify")
local PhysicsLoop = require("tireWearThermalsPhysicsLoop")
local Hud = require("tireWearThermalsHud")
local Ground = require("tireWearThermalsGround")
local Pressure = require("tireWearThermalsPressure")
local Wear = require("tireWearThermalsWear")
local Wheel = require("tireWearThermalsWheel")
local NodeWear = require("tireWearThermalsNodeWear")
local NodeProbe = require("tireWearThermalsNodeProbe")


-- Module-level variables
local tyreGripTable = {}
local tyreData = {}
local wheelCache = {}
local baseBrakeCoolings = {} -- Native brakeTypeSurfaceCoolingCoef snapshot per wheel
local vehicleMass = 1500
local wheelCount = 4 -- Dynamically calculated in initTyreData
local drivenWheelCount = 2 -- wheels with |prop| > thresh this frame (AWD layout damp)
local driveLayoutMode = "coast" -- "fwd"|"rwd"|"awd"|"coast" from front/rear prop this frame
local waterFilmDepth = 0 -- 0..1 global film from rain (no native BeamNG film API)
local stintDistanceM = 0 -- mod trip meter (m); resets on initTyreData / vehicle reload
-- Telemetry state packed (frees ~10 main-chunk locals for Lua 200-cap)
local telem = {
    csvEnabled = false,    -- Optional CSV dump (user can enable)
    interval = 1.0,        -- Seconds between samples when enabled
    armMarker = "mods/unpacked/Tire-Wear-and-Thermals-ReSpin-dev/tools/TELEMETRY_CSV_ARMED",
    timer = 0,
    path = nil,
    csvBuffer = {},
    csvBufCount = 0,
    headerReady = false,
    lastFlushClock = 0,
    flushWallSec = 45,
    flushMaxLines = 200,
    -- Legacy cols (keep order): wall..film. Appended UI-stream cols for mute-removal / heat tuning
    -- (same sources as TireWearThermals / flushGuiStream). rim/air already cover rimTemp/airTemp.
    -- String fields with commas (dutyMods, profiles) are CSV-escaped via F.csvEscape.
    csvHeader = "wall,t,wheel,cond,o,m,i,carcL,carcC,carcR,rim,air,psi,grip,longGrip,latGrip,clog,grain,blister,cycles,stint,leak,film,profile,profile1,profile2,purpose,classifyReason,patchFrac,patchHeatScale,aeroLoadN,totalDownforceN,aeroFracPct,dutyMods,driveHeatGate,streetSlipScale,utilNudge,aeroDragN,aeroFrontN,aeroRearN,copPct\n",
}
local brakeDuctSettings = { DUCT_DEFAULT_PCT, DUCT_DEFAULT_PCT } -- Front, Rear (1..100%)
local lastDuctMailbox = nil

-- Pack-air / wake thermals (single table: frees ~19 main-chunk locals for Lua 200-cap):
--  Pre-0.39: LuuksDraftingMod mailbox/setDraftWake -> convection cut + ambient rise
--  0.39+: native core_interAero owns drag (setWindAero). We INFER wake from
--    airspeed vs airflowspeed and only add pack-air ambient (no convection cut).
local draft = {
    coolingReduction = 0.28,   -- max forced-convection cut (legacy companion only)
    airTempCap = 5.0,          -- safety cap (C)
    staleSec = 1.5,            -- decay if companion stops publishing
    nativeAirTempMax = 4.0,    -- pack-air rise at full inferred wake (C)
    inferMinSpeed = 8.0,       -- m/s - ignore crawl / garage
    inferDeadband = 0.04,      -- ignore small ambient-tailwind noise (frac of speed)
    inferDeadbandMin = 0.8,    -- m/s absolute floor on deadband
    inferRefFrac = 0.45,       -- deficit / (speed*this) -> wake 1.0
    inferSmooth = 2.5,         -- 1/s toward inferred target
    wake = 0, side = 0, push = 0,
    airTempDelta = 0,
    coolingWake = 0,
    lastRxClock = 0,
    lastMailbox = nil,
    hasNativeInterAero = false, -- obj.setWindAero present (0.39+)
    inferredWake = 0,           -- 0..1 from airspeed - airflowspeed
    convectionMult = 1.0,       -- applied in CalcTyreWear (1 = no companion cut)
    airTempEffective = 0,       -- ambient bump after native coexistence scale
}

-- Native triangle aero (aeroDebug.lua APIs). HUD/CSV. Heat uses full load (scale 1.0).
local nativeAero = {
    ok = false, liftN = 0, dragN = 0, sideN = 0,
    frontN = 0, rearN = 0, frontPct = 0, rearPct = 0, copPct = 0,
    fracPct = 0, totalLoadN = 0, nFront = 0, nRear = 0,
}

-- Rolling tracker parameters to evaluate level environment profile fluctuations
local rawEnvMin = 100
local rawEnvMax = -100

-- Track Environment State Cache (reused to prevent GC overhead)
local trackEnv = { timeOfDay = 0.5, cloudCover = 0.2 }
-- One track-surface sample per GFX frame (CalcTyreWear runs ~4×/frame; tod/cloud are slow)
local frameTrackTemp = 21
local frameChassisSpeed = 0 -- m/s from obj:getVelocity(); garage PSI gates must not use per-wheel hop

-- High Performance Pre-allocated GUI Data Structures (Reduces GC allocations to 0 per frame)
local guiStream = { data = {} }
local wheelIndexMap = {}
-- Increments on vehicle spawn / reset / deserialize so HUD drops lerp of the previous life.
local resetGen = 0

-- Local Cache states to prevent constant pattern matching / deserialization overhead
local classifyCache = { vehicleType = nil, rallyDamper = nil, typeRetryCount = 0 }
local lastTrackEnvMailbox = nil
local lastEnvMailbox = nil

-- Function table: one chunk local instead of N forward decls (Lua ~200 local cap)
local F = {}

-- =============================================================================
-- F TABLE — SURFACE/AERO WRAPPERS, MP/STREAM, ENV HELPERS
-- =============================================================================

-- Cold-path modules (load once; thin wrappers keep hot-path call sites unchanged).
F.classifySurfaceGrip = Surface.classifySurfaceGrip
F.getSurfaceSanityScale = Surface.getSurfaceSanityScale
F.fillSurfaceFlags = Surface.fillSurfaceFlags
F.resolveWheelSurface = Surface.resolveWheelSurface
F.applyProfileSurfaceBias = Surface.applyProfileSurfaceBias
F.wheelAxleKey = Aero.wheelAxleKey
F.resetNativeAero = function() Aero.reset(nativeAero) end
F.sampleNativeAero = function()
    Aero.sample(nativeAero, { obj = obj, wheels = wheels, wheelCache = wheelCache })
end
F.nativeAeroWheelShare = function(name, loadN)
    return Aero.wheelShare(nativeAero, name, loadN)
end
F.aeroHeatThermalFrac = function(data, name, loadRaw, airspeed)
    return Aero.heatThermalFrac(nativeAero, data, name, loadRaw, airspeed, topo)
end

-- BeamMP: own cars are "L", remotes are "R". Nil in singleplayer → full sim.
-- Remotes must not write grip/pressure (local interpolated physics) or HUD-stream
-- (every auto-extension was publishing TireWearThermals with no vehicle id).
F.isRemoteMpVehicle = function()
    local t = (v and v.mpVehicleType) or (obj and obj.mpVehicleType)
    return t == "R" or t == "r"
end

-- Only the vehicle the local player is seated in should feed Apps.
F.isHudPublisher = function()
    if F.isRemoteMpVehicle() then return false end
    if playerInfo ~= nil and type(playerInfo.anyPlayerSeated) == "boolean" then
        return playerInfo.anyPlayerSeated
    end
    return true
end

F.streamVehicleId = function()
    return objectId or objCall("getID") or 0
end

-- HUD instance tag for this vehicle Lua VM (BeamNG game object id).
F.streamTag = function()
    return "TWTRS-" .. tostring(F.streamVehicleId())
end

F.bumpResetGen = function()
    resetGen = (tonumber(resetGen) or 0) + 1
    guiStream.resetGen = resetGen
end

F.stampStreamIdentity = function()
    guiStream.vehId = F.streamVehicleId()
    guiStream.streamTag = F.streamTag()
    guiStream.resetGen = resetGen
    guiStream.mpRemote = false
end


-- Cleanly filters ambient temperature. BeamNG native env is Kelvin; mailboxes are usually Celsius.
-- Never silently treat hot desert Celsius (e.g. 48C) as Fahrenheit.
F.sanitizeEnvTemp = function(rawTemp)
    if not rawTemp then return 21 end
    local temp = tonumber(rawTemp) or 21
    -- Kelvin from obj:getEnvTemperature or GE absolute scale
    if temp > 180 then
        temp = temp - 273.15
    end
    return max(-40, min(60, temp))
end

local DOESNT_EXIST_DATA = { name = "DOESNT EXIST", nameLower = "doesnt exist", staticFrictionCoefficient = 1, slidingFrictionCoefficient = 1 }

-- =============================================================================
-- ENV / CLIMATE / PRESSURE-GRIP HELPERS (cold path)
-- =============================================================================

-- Three-band pressure→grip: neutral deadband, wide mild normal (asymmetric over), progressive outer.
-- pOffset = currentPSI/optimalPressure - 1. Returns longScale, latScale.
F.CalcPressureGripScales = function(pOffset, sensitivity, isLooseSurface)
    local sens = max(0.05, sensitivity or 0.5)
    if isLooseSurface then
        -- Loose: keep under-inflation flotation; over uses same banded outer as paved
        if pOffset < 0 then
            local progress = -pOffset
            local flotationGripBonus = 1.0 + 0.15 * sin(progress * pi)
            local latPressureScale = flotationGripBonus * max(0.70, 1.0 - 0.35 * (progress * progress))
            return flotationGripBonus, latPressureScale
        end
    end

    local tb = THERMAL_TOPOLOGY
    local neutralHalf = tb.pressureNeutralHalf or tb.pressurePerfectHalf or 0.04
    local normalUnder = tb.pressureNormalUnder or 0.14
    local normalOver = tb.pressureNormalOver or 0.32
    local mildMax = (tb.pressureMildBase or 0.028) + (tb.pressureMildSens or 0.022) * sens
    local ao = abs(pOffset)

    if ao <= neutralHalf then
        return 1.0, 1.0
    end

    if pOffset < 0 then
        if pOffset >= -normalUnder then
            local t = (-pOffset - neutralHalf) / max(1e-6, normalUnder - neutralHalf)
            local lat = 1.0 - mildMax * t * 1.15
            local long = 1.0 - mildMax * t * 0.55
            return long, lat
        end
        local excess = -pOffset - normalUnder
        local edgeLat = 1.0 - mildMax * 1.15
        local edgeLong = 1.0 - mildMax * 0.55
        local den = 1.0 + sens * 1.5 * (excess * excess + 1.8 * excess * excess * excess)
        return max(0.30, edgeLong / den), max(0.15, edgeLat / den)
    end

    if pOffset <= normalOver then
        local t = (pOffset - neutralHalf) / max(1e-6, normalOver - neutralHalf)
        local pen = 1.0 - mildMax * (t ^ 1.15)
        return pen, pen
    end

    local excess = pOffset - normalOver
    local edge = 1.0 - mildMax
    local den = 1.0 + sens * 1.5 * (excess * excess + 2.4 * excess * excess * excess)
    local pen = max(0.35, edge / den)
    return pen, pen
end


-- Track surface temperature: asphalt often runs well above air in sun (+20–35C typical)
F.getTrackTemp = function(envTemp, tod, cloudCover)
    tod = tod or 0.5
    if tod > 1.0 then tod = tod / 24.0 end
    
    local solarAngleFactor = max(0, cos((tod - 0.5) * 2 * pi))
    local cloudScale = max(0, min(1, cloudCover or 0.2))
    
    -- Sol-air style gain: up to ~32C above ambient under clear midday sun
    local solarGain = solarAngleFactor * (1.0 - cloudScale * 0.85) * 32.0
    
    local isRaining = electrics and electrics.values and type(electrics.values.rainState) == "number" and electrics.values.rainState > 0
    if isRaining or waterFilmDepth > 0.35 then
        -- Wet asphalt stays near ambient (evaporative cooling)
        return envTemp + solarGain * 0.15 - 1.5
    end
    
    local nightCooling = (1.0 - solarAngleFactor) * 6.0
    return envTemp + solarGain - nightCooling
end

-- =============================================================================
-- AIRSPEED & DEFLATE (shared by thermals / wear / pressure)
-- =============================================================================

F.getFreestreamAirspeed = function()
    local ev = electrics and electrics.values
    if not ev then return 0 end
    -- Brake thermals use airflowspeed; fall back to airspeed
    local a = tonumber(ev.airflowspeed) or tonumber(ev.airspeed) or 0
    return max(0, a)
end

-- Chassis G + yaw for Pitwall (same sensors path as thermals g_mag).
-- Convention in this mod: gx ≈ long, gy ≈ lat (see patchLatLoadNudge / GFX sample).
F.getChassisDynamicsSnapshot = function()
    local gx = (sensors and (sensors.gx2 or sensors.gx) or 0) / 9.80665
    local gy = (sensors and (sensors.gy2 or sensors.gy) or 0) / 9.80665
    local yawRad = tonumber(objCall("getYawAngularVelocity"))
    if yawRad == nil then
        local ok, _, _, yaw = objPcall("getRollPitchYawAngularVelocity")
        if ok then yawRad = tonumber(yaw) end
    end
    yawRad = yawRad or 0
    return {
        gLong = gx,
        gLat = gy,
        gMag = sqrt(gx * gx + gy * gy),
        yawRateDeg = yawRad * (180.0 / pi),
    }
end

F.getVehicleAirspeedRef = function()
    -- Chassis velocity first: electrics.airspeed can read 0 in a hop/wake while the car is at 170 mph,
    -- which made Cold fill think we were in the garage and pump fronts 27→38 PSI.
    if frameChassisSpeed and frameChassisSpeed > 0.5 then
        return frameChassisSpeed
    end
    local ev = electrics and electrics.values
    if ev then
        local a = tonumber(ev.airspeed)
        if a and a > 0.5 then return a end
        local w = tonumber(ev.wheelspeed)
        if w and w > 0.5 then return w end
    end
    return objChassisSpeed()
end


-- Prefer wheels.deflateTire (0.39 surface) then beamstate fallback
F.deflateTireCompat = function(wheelID)
    if wheels and type(wheels.deflateTire) == "function" then
        wheels.deflateTire(wheelID)
        return true
    end
    if beamstate and type(beamstate.deflateTire) == "function" then
        beamstate.deflateTire(wheelID)
        return true
    end
    return false
end

-- =============================================================================
-- THERMAL INTEGRATOR (ctw scratch + prepare / step / wear bridge)
-- =============================================================================

local ctw = {}
-- DEBUG_THERMALS: one-shot Wear contract check after first prepare (respawn resets via clearSharedCaches).
local ctwWearContractChecked = false
local CTW_WEAR_REQUIRED_KEYS = {
    -- damage
    "avgWeightedTemp", "current_optimal_temp", "current_working_temp", "tempDistWeighted",
    "isAirborne", "loadRaw", "slipEnergy", "sideSlipEnergy", "g_mag", "tyreWidthCoeff",
    "propulsionTorque", "brakeTorque", "angularVel", "wearRate", "coldWearMult", "hotWearMult",
    "bottomOutSens", "wLeft", "wCenter", "wRight", "casing_compliance", "contactDepth",
    "rawJBeamTread", "gmName", "treadCoef", "grainTempRatio", "blisterTempRatio", "tyreWidth",
    "isRaining", "isWetSurface", "isDryPaved", "isLooseSurface", "isMudSurface", "isSnowSurface",
    "isSandSurface", "isGravelSurface", "isDirtGrassSurface", "isIceSurface", "vehNotParked",
    "sf", "groundModel", "rollingWearCoef", "dualContactBlend", "dualRoughDelta",
    -- pressure
    "vehicleSpeed", "currentTempK", "initialTempK", "warmAbsolutePressurePSI",
    "thermalAbsPSI", "dynamicPressurePSI", "avgCarcassTemp",
}

local function assertCtwWearContractOnce()
    if ctwWearContractChecked or not DEBUG_THERMALS then return end
    ctwWearContractChecked = true
    local missing = {}
    for i = 1, #CTW_WEAR_REQUIRED_KEYS do
        local k = CTW_WEAR_REQUIRED_KEYS[i]
        if ctw[k] == nil then
            missing[#missing + 1] = k
        end
    end
    if #missing > 0 then
        print("tireWearThermals CTW WEAR CONTRACT FAIL — missing keys after ctwPrepareThermals: "
            .. table.concat(missing, ", "))
    else
        print("tireWearThermals CTW wear contract OK (" .. tostring(#CTW_WEAR_REQUIRED_KEYS) .. " keys)")
    end
end

F.ctwPrepareDriveGates = function(data, mods, slipEnergy, g_mag, brakeTorque, propulsionTorque, safeAirspeed, rollingResistance, flexModifier, vehNotParked)
    -- Propulsion torque at steady cruise is mostly aero/RR balance — do not treat as slip work.
    -- Gate drive-torque heating by slip + lateral load so highway throttle does not cook the tread.
    local propAbs = abs(propulsionTorque)
    -- P1: mass-scale absolute Nm gates (light hatch opens earlier; heavy raises cruise floor).
    local massRef = topo.drivePropMassRefKg or 1500
    local massScale = max(topo.drivePropMassScaleMin or 0.78,
        min(topo.drivePropMassScaleMax or 1.35, sqrt(max(400, vehicleMass) / max(400, massRef))))
    local cruiseNm = topo.drivePropCruiseNm * massScale
    local excessFullNm = topo.drivePropExcessFullNm * massScale
    local driveHeatGate = min(1.0, (slipEnergy * 2.5) + (g_mag * 0.45) + (abs(brakeTorque) > 40 and 1.0 or 0))
    -- Straight-line cruise choke (Phase 2: cruiseDriveChokeMin=1.0 → off for Soft C4 A/B).
    -- When min<1: idle/coast stay cold; softens once |prop| > half cruiseNm.
    if slipEnergy < 0.06 and g_mag < 0.28 and abs(brakeTorque) < 40 then
        local chokeMin = topo.cruiseDriveChokeMin or 1.0
        if chokeMin < 0.999 then
            local halfCruise = cruiseNm * 0.5
            driveHeatGate = driveHeatGate * (propAbs > halfCruise and (chokeMin + (1.0 - chokeMin) * max(0, min(1.0, (propAbs - halfCruise) / max(1.0, halfCruise)))) or chokeMin)
        end
    end
    -- Excess propulsion opens gate after cruise choke: hard throttle warms driven tires
    -- (Scintilla RWD track accel) while |prop|≤cruiseNm keeps Belasco highway soft.
    local excessPropGate = max(0, min(1.0, (propAbs - cruiseNm) / max(1.0, excessFullNm)))
    -- AWD / multi-driven: damp per-wheel excess so 4×driven doesn't stack cook vs RWD.
    if drivenWheelCount >= 3 then
        local awdT = max(0, min(1.0, (drivenWheelCount - 2) / 2.0))
        local awdScale = 1.0 + ((topo.drivePropAwdExcessScale or 0.62) - 1.0) * awdT
        excessPropGate = excessPropGate * awdScale
    end
    -- Slick/race spectrum: damp Pass 3/4 excess only (sport_plus / non-slick keep full at low V).
    -- Split skin vs carcass — rears were still cooking carcass after skin-only 0.55 relief.
    local slickDriveScale = 1.0
    local slickCarcassScale = 1.0
    local p1Lower = data.profile1Lower or ""
    local p2Lower = data.profile2Lower or ""
    -- Milder soft-cap duty id for sport_plus only (Track Day uses its own Plus→Hard stamp).
    local isSportPlusProf = not not (string.find(p1Lower, "sport_plus", 1, true) or string.find(p2Lower, "sport_plus", 1, true))
    if string.find(p1Lower, "slick", 1, true) or string.find(p2Lower, "slick", 1, true) then
        slickDriveScale = topo.drivePropSlickScale or 1.0
        slickCarcassScale = topo.drivePropSlickCarcassScale or 1.0
    end
    -- Soft-like driven-front damp: FWD LOCKED (0.58/0.48); AWD LOCKED (0.45/0.38).
    -- Soft compound knobs stay locked; RWD Phase1 unmute stays 1.0.
    local fwdSoftDamp = false
    local awdSoftDamp = false
    if data.isFront and propAbs > (topo.drivePropDrivenThreshNm or 40) then
        local softMin = topo.drivePropFwdSoftSoftnessMin or 0.72
        local isSoftLike = string.find(p1Lower, "soft_slick", 1, true) or string.find(p2Lower, "soft_slick", 1, true)
            or ((data.softnessRemap or 0) >= softMin)
        if isSoftLike then
            if driveLayoutMode == "fwd" then
                local fwdSkin = topo.drivePropFwdSoftScale or 0.58
                local fwdCarc = topo.drivePropFwdSoftCarcassScale or 0.48
                if fwdSkin < 0.999 then
                    slickDriveScale = slickDriveScale * fwdSkin
                    fwdSoftDamp = true
                end
                if fwdCarc < 0.999 then
                    slickCarcassScale = slickCarcassScale * fwdCarc
                    fwdSoftDamp = true
                end
            elseif driveLayoutMode == "awd" then
                local awdSkin = topo.drivePropAwdSoftScale or 0.45
                local awdCarc = topo.drivePropAwdSoftCarcassScale or 0.38
                if awdSkin < 0.999 then
                    slickDriveScale = slickDriveScale * awdSkin
                    awdSoftDamp = true
                end
                if awdCarc < 0.999 then
                    slickCarcassScale = slickCarcassScale * awdCarc
                    awdSoftDamp = true
                end
            end
        end
    end
    -- Street/non-slick high-V: damp carcass excess when freestream opens prop-hold cook.
    -- Magnitude from profile driveHighVCarcassScale; Phase 5 purpose selects enable pack.
    local streetCarcassScale = 1.0
    local highVCarcassFull = mods.driveHighVCarcassScale or 1.0
    local softcapPurposeOk = purposeAllowsStreetSoftcap(mods.purpose)
    if softcapPurposeOk and highVCarcassFull < 0.999 then
        local v0 = topo.drivePropStreetSpeed0 or 78.0
        local v1 = topo.drivePropStreetSpeed1 or 112.0
        local vRamp = max(0, min(1.0, (safeAirspeed - v0) / max(1.0, v1 - v0)))
        streetCarcassScale = 1.0 + (highVCarcassFull - 1.0) * vRamp
    end
    local carcassPropScale = slickCarcassScale * streetCarcassScale
    local excessPropGateEff = excessPropGate * slickDriveScale
    local excessPropGateCarcass = excessPropGate * carcassPropScale
    local driveHeatGateSkin = max(driveHeatGate, excessPropGateEff)
    local driveHeatGateCarcass = max(driveHeatGate, excessPropGateCarcass)
    driveHeatGate = driveHeatGateSkin -- skin path + legacy readers
    data.lastDriveHeatGate = driveHeatGateSkin
    data.lastDriveHeatGateCarcass = driveHeatGateCarcass
    -- Driven residual long-slip soft-cap ENABLE (topo ramps) + profile floors.
    -- Uses freestream safeAirspeed (not ω-mixed) so spinning-in-place still cooks.
    -- Purpose pack must allow; sport_plus milder floors come from profile stamp.
    local streetSlipHeatScale = 1.0
    local streetSlipPropScale = 1.0
    local heatMin = mods.driveSlipHeatMin or 1.0
    local propMin = mods.driveSlipPropMin or 1.0
    if softcapPurposeOk and slickDriveScale >= 0.999 and abs(brakeTorque) < 40
        and propAbs > (cruiseNm * 0.5)
        and (heatMin < 0.999 or propMin < 0.999) then
        local v0 = topo.driveStreetSlipSpeed0 or 3.5
        local v1 = topo.driveStreetSlipSpeed1 or 14.0
        local speedRamp = max(0, min(1.0, (safeAirspeed - v0) / max(1.0, v1 - v0)))
        speedRamp = speedRamp * speedRamp * (3.0 - 2.0 * speedRamp)
        local g0 = topo.driveStreetSlipG0 or 0.32
        local g1 = topo.driveStreetSlipG1 or 0.58
        local gGate = 1.0 - max(0, min(1.0, (g_mag - g0) / max(1e-3, g1 - g0)))
        local s0 = topo.driveStreetSlipCapStart or 0.16
        local s1 = topo.driveStreetSlipCapFull or 0.52
        local slipRamp = max(0, min(1.0, (slipEnergy - s0) / max(1e-3, s1 - s0)))
        slipRamp = slipRamp * slipRamp * (3.0 - 2.0 * slipRamp)
        local blend = speedRamp * gGate * slipRamp
        if blend > 1e-4 then
            streetSlipHeatScale = 1.0 + (heatMin - 1.0) * blend
            streetSlipPropScale = 1.0 + (propMin - 1.0) * blend
        end
    end
    data.lastStreetSlipHeatScale = streetSlipHeatScale
    local netTorque = vehNotParked * abs(propulsionTorque * topo.drivePropSkinCoef * driveHeatGateSkin * streetSlipPropScale - brakeTorque * 0.025) * 0.075 * rollingResistance * flexModifier
    ctw.propAbs = propAbs
    ctw.cruiseNm = cruiseNm
    ctw.excessPropGate = excessPropGate
    ctw.excessPropGateEff = excessPropGateEff
    ctw.excessPropGateCarcass = excessPropGateCarcass
    ctw.carcassPropScale = carcassPropScale
    ctw.streetCarcassScale = streetCarcassScale
    ctw.streetSlipHeatScale = streetSlipHeatScale
    ctw.driveHeatGateCarcass = driveHeatGateCarcass
    ctw.fwdSoftDamp = fwdSoftDamp
    ctw.awdSoftDamp = awdSoftDamp
    ctw.isSportPlusProf = isSportPlusProf
    ctw.netTorque = netTorque
end

-- Prepare thermal inputs into ctw scratch (own 200-local budget)
F.ctwPrepareThermals = function(wheelID, dt, localEnvTemp, wd, w, data, mods)
    -- Read cached environmental dynamics (frameTrackTemp set once in updateGFX)
    local groundModel = w.groundModel or DOESNT_EXIST_DATA
    local trackTemp = frameTrackTemp
    local isAirborne = w.isAirborne
    

    -- DYNAMIC CLIMATE PROFILE ADAPTATION
    local baseEnv = 21.0
    local tempDiff = localEnvTemp - baseEnv
    
    -- Compound optimal temp is fixed; ambient only changes heat/cool rates
    local current_optimal_temp = max(35, mods.optimalTemp or WORKING_TEMP)
    
    -- Scale heat-generation and cooling with climate (not the grip peak)
    local heatAdaptationFactor = max(0.85, min(1.25, 1.0 - tempDiff * 0.008))
    local coolAdaptationFactor = max(0.75, min(1.30, 1.0 + tempDiff * 0.010))

    local wearRate = mods.wearRate or 0.0005
    local slipHeatRate = (mods.slipHeatRate or 8.925) * heatAdaptationFactor
    local workHeatRate = (mods.workHeatRate or 5.1) * heatAdaptationFactor
    local staticCoolingRate = (mods.staticCoolingRate or 0.08) * coolAdaptationFactor
    local airCoolingRate = (mods.airCoolingRate or 0.0275) * coolAdaptationFactor
    local skinCoreConductance = mods.skinCoreConductance or 0.068
    skinCoreConductance = max(topo.skinCoreConductanceFloor or 0.070,
        skinCoreConductance * (topo.skinCoreConductanceScale or 1.85))
    local coreVelCoolRate = (mods.coreVelCoolRate or 0.0088) * coolAdaptationFactor
    local coreCoolRate = (mods.coreCoolRate or 0.0385) * coolAdaptationFactor
    local brakeGainRate = mods.brakeGainRate or 0.9
    local airConductionRate = mods.airConductionRate or 0.0135
    local thermalReactionRate = mods.thermalReactionRate or 1.35
    local casing_compliance = mods.casingCompliance or 0.6
    local bottomOutSens = mods.bottomOutSensitivity or 1.0
    local trackConductivityMult = mods.trackConductivityMult or 1.0
    local coldWearMult = mods.coldWearMult or 1.8
    local hotWearMult = mods.hotWearMult or 3.5
    local grainTempRatio = mods.grainTempRatio or 0.75
    local blisterTempRatio = mods.blisterTempRatio or 1.55

    local rawJBeamTread = wd.treadCoef or 0.5
    local treadCoef = rawJBeamTread 
    
    -- Cold fill: prefer seeded group Pa (stock fill); fall back to wd.pressure
    local initialPressurePSI = max(1.0, data.coldPressurePSI or wd.pressure or 25.0)

    -- Stock BeamNG construction + brake thermal factors
    local bf = data.baseFactors
    if not bf then
        bf = F.collectBaseWheelFactors(wd)
        data.baseFactors = bf
    end

    local brakeSurfaceTemp, brakeCoreTemp = F.getNativeBrakeTemps(wd, localEnvTemp)
    -- Read-only brake efficiency / glazing (no torque override); tiny soak scale when glazed
    local brakeThermalEff = 1.0
    if type(wd.brakeThermalEfficiency) == "number" then
        brakeThermalEff = max(0.35, min(1.0, wd.brakeThermalEfficiency))
    elseif type(wd.brakeThermal) == "table" and type(wd.brakeThermal.efficiency) == "number" then
        brakeThermalEff = max(0.35, min(1.0, wd.brakeThermal.efficiency))
    end
    data.brakeThermalEfficiency = brakeThermalEff
    local brakeEffSoak = (topo.brakeEffSoakFloor or 0.92) + (1.0 - (topo.brakeEffSoakFloor or 0.92)) * brakeThermalEff

    -- Tuning-menu brake ducts (default closed). Tire-side only — native rotors unchanged.
    -- Air path: skin velCool, carcassCoolCoef, rimCool (+ venting / G / draft / underwater).
    -- Soak path: brake→rim conduction+radiant, rim↔carcass (ductSoakCondFactor).
    local ductPct = F.getBrakeDuctPercent(data.isFront)
    local ductAirCoolFactor, ductSoakCondFactor = F.ductPercentToFactors(ductPct)
    -- Multiply with stock venting so race vented discs + open ducts stack correctly
    local ventingMult = max(0.35, min(2.0, bf.brakeVentingCoef or 1.0))
    ductAirCoolFactor = ductAirCoolFactor * lerp(1.0, ventingMult, 0.35)
    data.ductPercent = ductPct
    data.ductAirCoolFactor = ductAirCoolFactor
    data.ductSoakCondFactor = ductSoakCondFactor
    -- Working air factor accumulates transient modifiers (G / water / draft) below
    local airCoolingFactor = ductAirCoolFactor

    -- Snapshot stock native brake cooling; restore every tick (tyre-side ducts only).
    -- Writing duct-boosted brakeTypeSurfaceCoolingCoef double-cooled rotors vs Lua convection.
    if wd and baseBrakeCoolings[wheelID] == nil then
        baseBrakeCoolings[wheelID] = wd.brakeTypeSurfaceCoolingCoef or 1.0
    end
    if wd and baseBrakeCoolings[wheelID] then
        wd.brakeTypeSurfaceCoolingCoef = baseBrakeCoolings[wheelID]
    end
    
    local slipEnergy = isAirborne and 0 or (w.dynamicSlipEnergy or 0)
    local longSlipEnergy = isAirborne and 0 or (w.longSlipEnergy or 0)
    local sideSlipEnergy = isAirborne and 0 or (w.sideSlipEnergy or 0)
    local peakForce = isAirborne and 0 or (w.peakForce or 0)
    -- Short EMA on contactDepth so gravel/kerbs don't jitter patchFrac / heat
    local rawContactDepth = isAirborne and 0 or (w.contactDepth or 0)
    local depthTau = max(0.02, topo.contactDepthEmaTau or 0.08)
    local depthAlpha = min(1.0, dt / depthTau)
    local contactDepth = (data.contactDepthSmooth or rawContactDepth)
        + (rawContactDepth - (data.contactDepthSmooth or rawContactDepth)) * depthAlpha
    data.contactDepthSmooth = contactDepth
    local propulsionTorque = isAirborne and 0 or (wd.propulsionTorque or 0) * (wd.wheelDir or 1)
    local brakeTorque = isAirborne and 0 or (wd.brakeTorque or 0) * (wd.wheelDir or 1)
    -- A3: smoothed downForce for Hertz/thermal mass; downForceRaw for util spikes
    local loadRaw = isAirborne and 0 or (wd.downForce or wd.downForceRaw or w.downForceRaw or 0)
    local loadUtil = loadRaw
    if not isAirborne then
        local rawN = wd.downForceRaw or w.downForceRaw or 0
        if rawN > 100 then loadUtil = rawN end
    end
    local angularVel = isAirborne and 0 or abs(wd.angularVelocity or 0)

    local tyreWidth = bf.tireWidth or wd.tireWidth or wd.tyreWidth or wd.width or 0.2
    -- A4: prefer dynamicRadius for patch length; clamp absurd deflation vs static
    local staticRadius = bf.radius or wd.radius or 0.3
    local dynRadius = (w.dynamicRadius and w.dynamicRadius > 0.05) and w.dynamicRadius or staticRadius
    local tyreRadius = max(staticRadius * (topo.patchDynRadiusMinFrac or 0.55),
        min(staticRadius * (topo.patchDynRadiusMaxFrac or 1.06), dynRadius))
    local airspeed = F.getFreestreamAirspeed()

    -- PHYSICAL AIRSPEED & ROTATIONAL HEADING COMBINATION MODEL (Forced Convection)
    local safeAirspeed = max(0, airspeed)
    -- Prefer freestream; rotation only adds mixing (avoid double-counting v≈ωr on cruise)
    local combinedAirspeed = safeAirspeed + angularVel * tyreRadius * 0.35
    local effectiveAirspeed = combinedAirspeed / (1.0 + combinedAirspeed / 220.0)

    -- Calculate horizontal G-force magnitude from actual BeamNG accelerometer vectors
    local gx = (sensors and (sensors.gx2 or sensors.gx) or 0) / 9.80665
    local gy = (sensors and (sensors.gy2 or sensors.gy) or 0) / 9.80665
    local g_mag = sqrt(gx * gx + gy * gy)

    local suspVel = w.suspensionVelocity or 0
    local underWater = w.underWater and true or false

    -- Yaw / sideslip cooling asymmetry (crossflow increases convection on the windward side)
    airCoolingFactor = airCoolingFactor * (1.0 + min(0.25, abs(gx) * 0.08 + abs(gy) * 0.05))
    if underWater then
        airCoolingFactor = airCoolingFactor * 1.55
        staticCoolingRate = staticCoolingRate * 1.8
    end

    -- Pack / slipstream convection: companion LuuksDraftingMod only when native
    -- 0.39 interAero is absent (draft.convectionMult precomputed in refreshDraftCompat).
    if draft.convectionMult < 1.0 then
        effectiveAirspeed = effectiveAirspeed * draft.convectionMult
        airCoolingFactor = airCoolingFactor * draft.convectionMult
    end

    -- Thermal mass from stock tire/hub node weights (not just geometry)
    local heatMassScale = max(0.55, min(2.4, (1 + ((tyreWidth / 0.2) * (tyreRadius / 0.3) - 1) * 0.45) * max(0.55, min(2.2, (bf.tireMass / 8.0) * 0.65 + (bf.hubMass / 6.0) * 0.35))))
    
    -- Convert raw vertical load from Newtons to kgf to match the non-linear curve's expected scaling.
    local load_kg = loadRaw / 9.81
    load_kg = ((400 + load_kg) * load_kg / (100 + load_kg) - 0.15 * load_kg)
    -- Align with stock noLoad/fullLoad friction curve (lighter load → slightly more heat per N work)
    local loadFrictionScale = 1.0
    if bf.noLoadCoef and bf.fullLoadCoef then
        loadFrictionScale = max(0.75, min(1.35, lerp(bf.noLoadCoef, bf.fullLoadCoef, min(1.0, max(0, loadRaw) * (bf.loadSensitivitySlope or 0.00015) * 8.0))))
        load_kg = load_kg * (0.85 + 0.15 * loadFrictionScale)
    end

    -- Thermal load: aero mute is off (scale 1.0). Helper stays for an explicit A/B later.
    local load_kg_thermal = load_kg * F.aeroHeatThermalFrac(data, wd.name, loadRaw, safeAirspeed)

    data.working_temp = current_optimal_temp

    -- Vehicle speed, not per-wheel contact: a hopping front at 170 mph used to look
    -- "parked" (airborne → angularVel 0, airflow can drop) and pumped Cold fill.
    local vehicleSpeed = F.getVehicleAirspeedRef()
    local vehNotParked = (vehicleSpeed < 1.0 and safeAirspeed < 1.0 and angularVel < 0.4 and not isAirborne) and 0 or 1
    local initialTempK = w.initialTempK or (localEnvTemp + 273.15)
    
    local currentTempK = (data.temp[8] or localEnvTemp) + 273.15
    -- Gay-Lussac from cavity air only. Do NOT fold suspStress / damper chatter into PSI:
    -- that term was meant for hard bottom-out volume loss, but at speed it treated aero
    -- squat and hub-Z noise as a sustained +7 PSI (fronts 27→34 with ~30°C rubber).
    -- Real bump volume is a brief spike; write-back must stay on thermal PSI so native
    -- groups don't get pumped up on a straight.
    local thermalAbsPSI = (initialPressurePSI + 14.696) * (1.0 + (currentTempK / initialTempK - 1.0) * (1.0 - casing_compliance))
    local hardBumpM = max(0, (w.suspCompression or 0) - SUSP_HARD_BUMP_M)
    local bumpVol = min(0.04, hardBumpM * 0.7 * bottomOutSens)
    local warmAbsolutePressurePSI = thermalAbsPSI * (1.0 + bumpVol)
    local dynamicPressurePSI = max(0.1, warmAbsolutePressurePSI - 14.696)
    
    local pressureRatio = max(0.01, dynamicPressurePSI / initialPressurePSI)
    local flexModifier = lerp(2.0, 0.5, max(0.01, min(1.0, pressureRatio)))
    local tyreWidthCoeff = (3.5 * tyreWidth) * 0.5 + 0.5

    -- Pass pressure ratio to warp edge load calculations dynamically based on inflation states
    local wLeft, wCenter, wRight = F.CalcBiasWeights(w.combinedBias, pressureRatio)
    -- Mild live lateral load nudge (gy) toward loaded shoulder — not a soft-body node map
    do
        local nudge = max(-1.0, min(1.0, gy)) * (topo.patchLatLoadNudge or 0.05)
        if abs(nudge) > 1e-5 then
            wLeft = max(0.05, wLeft * (1.0 - nudge))
            wRight = max(0.05, wRight * (1.0 + nudge))
            local wSum = wLeft + wCenter + wRight
            if wSum > 1e-6 then
                wLeft, wCenter, wRight = wLeft / wSum, wCenter / wSum, wRight / wSum
            end
        end
    end

    -- Detect surfaces via shared classifier cache (must match CalculateTyreGrip)
    local isRaining = electrics and electrics.values and type(electrics.values.rainState) == "number" and electrics.values.rainState > 0
    local surfaceTypeHeat, sf = F.resolveWheelSurface(w, groundModel, isRaining) --luacheck: ignore surfaceTypeHeat
    local isLooseSurface = sf.loose
    local isIceSurface = sf.ice
    local isMudSurface = sf.mud
    local isSandSurface = sf.sand
    local isGravelSurface = sf.gravel
    local isSnowSurface = sf.snow
    local isDirtGrassSurface = sf.dirtGrass
    local isWetSurface = sf.wet
    local isDryPaved = sf.dryPaved
    local gmName = sf.gmName or (groundModel.nameLower or "")
    
    local avgWeightedTemp = F.TempRingsToAvgTemp(data.temp, w.combinedBias, pressureRatio, localEnvTemp)
    local avgCarcassTemp = F.TempCarcassToAvgTemp(data.temp, w.combinedBias, pressureRatio, localEnvTemp)
    
    local rollingResistance = (mods.rollingRes or 0.8) * (bf.rrFromSidewall or 1.0) * max(0.7, min(1.4, (bf.dragCoef or 5) / 5.0))
    -- topo = THERMAL_TOPOLOGY (module-level alias)
    F.ctwPrepareDriveGates(data, mods, slipEnergy, g_mag, brakeTorque, propulsionTorque, safeAirspeed, rollingResistance, flexModifier, vehNotParked)
    local propAbs = ctw.propAbs
    local cruiseNm = ctw.cruiseNm
    local excessPropGate = ctw.excessPropGate
    local excessPropGateEff = ctw.excessPropGateEff
    local excessPropGateCarcass = ctw.excessPropGateCarcass
    local carcassPropScale = ctw.carcassPropScale
    local streetCarcassScale = ctw.streetCarcassScale
    local streetSlipHeatScale = ctw.streetSlipHeatScale
    local driveHeatGateCarcass = ctw.driveHeatGateCarcass
    local fwdSoftDamp = ctw.fwdSoftDamp
    local awdSoftDamp = ctw.awdSoftDamp
    local isSportPlusProf = ctw.isSportPlusProf
    local netTorque = ctw.netTorque
    -- Pass 3+: boost slip/work skin heat with excess prop (driven tires only — undriven gate≈0)
    local tempDistWeighted = avgWeightedTemp / (data.working_temp > 0 and data.working_temp or 1)

    -- Contact patch area: blend Hertz F/P with deflection proxy from EMA contactDepth × dynamicRadius.
    -- Soft-surface conduction still applies its own depth penalty separately (not via area shrink).
    local hertzArea = max(0.004, min(tyreWidth * 0.24, loadRaw / max(10000, dynamicPressurePSI * 6894.76)))
    local deflArea = hertzArea
    if not isAirborne and contactDepth > 1e-4 and tyreRadius > 0.05 and tyreWidth > 0.04 then
        local d = min(contactDepth, tyreRadius * 0.35)
        local chord = 2.0 * sqrt(max(0, 2.0 * tyreRadius * d - d * d))
        deflArea = max(0.004, min(tyreWidth * 0.28, tyreWidth * chord * (topo.patchDeflWidthFrac or 0.55)))
    end
    local depthBlend = 0
    if not isAirborne then
        depthBlend = max(0, min(1.0, (contactDepth - 0.005) / 0.040)) * (topo.patchHertzDeflBlend or 0.35)
    end
    local estimatedContactArea = hertzArea * (1.0 - depthBlend) + deflArea * depthBlend

    local current_working_temp = (data.working_temp and data.working_temp > 0) and data.working_temp or WORKING_TEMP

    local treadInertia = heatMassScale * (mods.treadInertia or DEFAULT_MODS.treadInertia) * max(0.7, min(1.5, bf.tireMass / 8.0))
    local carcassInertia = heatMassScale * (mods.carcassInertia or DEFAULT_MODS.carcassInertia) * max(0.7, min(1.6, (bf.tireMass * 0.55 + bf.hubMass * 0.2) / 6.0))
    local airInertia = heatMassScale * (mods.airThermalInertia or DEFAULT_MODS.airThermalInertia) * max(0.65, min(1.5, bf.tireMass / 8.0))
    local rimInertia = heatMassScale * RIM_THERMAL_INERTIA * max(0.6, min(2.5, bf.brakeMass / 8.0)) * max(0.75, min(1.4, bf.brakeDiameter / 0.30))
    local adjustedChangeRate = thermalReactionRate / max(0.05, treadInertia)
    local conductanceTreadScale = lerp(2.0, 1.0, treadCoef)
    local surfaceAreaScale = lerp(0.85, 1.15, treadCoef)
    local carcassRate = CORE_REACTION_RATE / max(0.05, carcassInertia)
    local rimRate = RIM_REACTION_RATE / max(0.05, rimInertia)

    -- P0-1: contact-patch fraction of circumference (skin nodes are belt averages)
    -- Phase B: separate geometric cool floor from softer heat floor so street load/PSI/depth move scale.
    local patchFracRaw = 0
    if not isAirborne and tyreWidth > 0.04 and tyreRadius > 0.05 then
        patchFracRaw = (estimatedContactArea / tyreWidth) / max(0.4, 2.0 * pi * tyreRadius)
    end
    local patchFrac = max(topo.patchFracMin, min(topo.patchFracMax, patchFracRaw))
    local patchFracHeat = max(topo.patchFracHeatMin or topo.patchFracMin, min(topo.patchFracMax, patchFracRaw))
    -- Depth boost still useful when area blend is small vs kerb/soft sink (kept after Phase B unstick)
    local depthHeatBoost = 1.0
    if not isAirborne and contactDepth > 0.006 then
        depthHeatBoost = 1.0 + min(0.16, (contactDepth - 0.006) * 2.0)
    end
    -- Path A3: peakForce / downForceRaw util nudge on patch heat (EMA still damps kerb noise)
    local peakWorkFactorEarly = 1.0
    if peakForce and peakForce > 100 and loadUtil > 100 then
        peakWorkFactorEarly = max(topo.patchUtilPeakLo or 0.82, min(topo.patchUtilPeakHi or 1.40, peakForce / max(loadUtil, 1)))
    end
    local utilNudge = 1.0 + ((peakWorkFactorEarly - 1.0) * (topo.patchUtilBlend or 0))
    -- Pass 7j: floor 0.40→0.58 — hard_slick WCU fronts stuck at Patch/Heat 0.032×0.40
    -- Path A6: floor 0.58→0.70 — Soft C4 fronts still Hertz-starved after unmute; lift peg without
    --   another slip/work or airCool nudge (those multiply the same attenuated path).
    local patchHeatScaleRaw = max(0.70, min(1.20, (patchFracHeat / max(0.05, topo.patchFracRef)) * depthHeatBoost * utilNudge))
    -- Light EMA on heat scale (depth EMA alone insufficient when geom was floor-clamped)
    local patchHeatScale = patchHeatScaleRaw
    do
        local hsTau = max(0.02, topo.patchHeatEmaTau or 0.10)
        local hsAlpha = min(1.0, dt / hsTau)
        local hsPrev = data.patchHeatScaleSmooth
        if hsPrev == nil then hsPrev = patchHeatScaleRaw end
        patchHeatScale = hsPrev + (patchHeatScaleRaw - hsPrev) * hsAlpha
        data.patchHeatScaleSmooth = patchHeatScale
    end
    -- Phase A / Path A diagnostics (streamed to Heavy SURFACE CONTACT)
    data.lastPatchFrac = patchFrac
    data.lastPatchFracRaw = patchFracRaw
    data.lastPatchHeatScale = patchHeatScale
    data.lastDepthHeatBoost = depthHeatBoost
    data.lastHertzArea = hertzArea
    data.lastDeflArea = deflArea
    data.lastDepthBlend = depthBlend
    data.lastUtilNudge = utilNudge
    data.lastLoadUtil = loadUtil

    -- Stock friction multipliers shape heat generation
    local jbeamMu = max(0.4, min(1.8, bf.frictionCoef or 1.0))
    local jbeamSlideMu = max(0.35, min(1.8, bf.slidingFrictionCoef or jbeamMu))
    local peakWorkFactor = peakWorkFactorEarly

    -- Suspension damper / bump-stop heat into carcass (power ~ load·|v| + bump stress)
    local verticalCarcassHeat = 0
    if not isAirborne then
        verticalCarcassHeat = abs(suspVel) * (loadRaw / 1200) * 0.55
            + (w.suspBump or 0) * (loadRaw / 800) * 1.2
            + (w.suspStress or 0) * 1.8 * bottomOutSens
        if abs(suspVel) < 0.04 then
            verticalCarcassHeat = verticalCarcassHeat * 0.35 -- ignore micro-chatter
        end
    end

    -- CLIMATE PLAYABILITY ADAPTATION (reuses baseEnv/tempDiff from above)
    local climateScale = max(0.6, min(1.4, 1.0 + (tempDiff * 0.012)))


        -- Persist prepare outputs for node/wear scopes
        ctw.adjustedChangeRate = adjustedChangeRate
        ctw.airConductionRate = airConductionRate
        ctw.airCoolingFactor = airCoolingFactor
        ctw.airCoolingRate = airCoolingRate
        ctw.airInertia = airInertia
        ctw.angularVel = angularVel
        ctw.avgCarcassTemp = avgCarcassTemp
        ctw.avgWeightedTemp = avgWeightedTemp
        ctw.bf = bf
        ctw.blisterTempRatio = blisterTempRatio
        ctw.bottomOutSens = bottomOutSens
        ctw.brakeCoreTemp = brakeCoreTemp
        ctw.brakeEffSoak = brakeEffSoak
        ctw.brakeGainRate = brakeGainRate
        ctw.brakeSurfaceTemp = brakeSurfaceTemp
        ctw.brakeTorque = brakeTorque
        ctw.carcassPropScale = carcassPropScale
        ctw.carcassRate = carcassRate
        ctw.casing_compliance = casing_compliance
        ctw.climateScale = climateScale
        ctw.coldWearMult = coldWearMult
        ctw.conductanceTreadScale = conductanceTreadScale
        ctw.contactDepth = contactDepth
        ctw.coreCoolRate = coreCoolRate
        ctw.coreVelCoolRate = coreVelCoolRate
        ctw.cruiseNm = cruiseNm
        ctw.current_optimal_temp = current_optimal_temp
        ctw.current_working_temp = current_working_temp
        ctw.driveHeatGateCarcass = driveHeatGateCarcass
        ctw.ductPct = ductPct
        ctw.ductSoakCondFactor = ductSoakCondFactor
        ctw.dynamicPressurePSI = dynamicPressurePSI
        ctw.effectiveAirspeed = effectiveAirspeed
        ctw.estimatedContactArea = estimatedContactArea
        ctw.excessPropGate = excessPropGate
        ctw.excessPropGateCarcass = excessPropGateCarcass
        ctw.excessPropGateEff = excessPropGateEff
        ctw.flexModifier = flexModifier
        ctw.g_mag = g_mag
        ctw.gmName = gmName
        ctw.grainTempRatio = grainTempRatio
        ctw.groundModel = groundModel
        ctw.heatMassScale = heatMassScale
        -- Path A1/A2: blend GM soft/friction into ctw scratch (pass table — helper is above local ctw decl)
        F.blendGroundThermal(w, groundModel, isAirborne, ctw)
        data.lastDualContactBlend = ctw.dualContactBlend or 0
        ctw.hotWearMult = hotWearMult
        ctw.isAirborne = isAirborne
        ctw.isDirtGrassSurface = isDirtGrassSurface
        ctw.isDryPaved = isDryPaved
        ctw.isGravelSurface = isGravelSurface
        ctw.isIceSurface = isIceSurface
        ctw.isLooseSurface = isLooseSurface
        ctw.isMudSurface = isMudSurface
        ctw.isRaining = isRaining
        ctw.isSandSurface = isSandSurface
        ctw.isSnowSurface = isSnowSurface
        ctw.isSportPlusProf = isSportPlusProf
        ctw.isWetSurface = isWetSurface
        ctw.jbeamMu = jbeamMu
        ctw.jbeamSlideMu = jbeamSlideMu
        ctw.loadRaw = loadRaw
        ctw.load_kg = load_kg
        ctw.load_kg_thermal = load_kg_thermal
        ctw.longSlipEnergy = longSlipEnergy
        ctw.netTorque = netTorque
        ctw.patchFrac = patchFrac
        ctw.patchHeatScale = patchHeatScale
        ctw.peakWorkFactor = peakWorkFactor
        ctw.pressureRatio = pressureRatio
        ctw.propAbs = propAbs
        ctw.propulsionTorque = propulsionTorque
        ctw.rawJBeamTread = rawJBeamTread
        ctw.rimRate = rimRate
        ctw.rollingResistance = rollingResistance
        ctw.safeAirspeed = safeAirspeed
        ctw.sf = sf
        ctw.sideSlipEnergy = sideSlipEnergy
        ctw.skinCoreConductance = skinCoreConductance
        ctw.slipEnergy = slipEnergy
        ctw.slipHeatRate = slipHeatRate
        ctw.staticCoolingRate = staticCoolingRate
        ctw.streetCarcassScale = streetCarcassScale
        ctw.streetSlipHeatScale = streetSlipHeatScale
        ctw.surfaceAreaScale = surfaceAreaScale
        ctw.tempDistWeighted = tempDistWeighted
        ctw.trackConductivityMult = trackConductivityMult
        ctw.trackTemp = trackTemp
        ctw.treadCoef = treadCoef
        ctw.tyreWidth = tyreWidth
        ctw.tyreWidthCoeff = tyreWidthCoeff
        ctw.vehNotParked = vehNotParked
        ctw.verticalCarcassHeat = verticalCarcassHeat
        ctw.wCenter = wCenter
        ctw.wLeft = wLeft
        ctw.wRight = wRight
        ctw.wearRate = wearRate
        ctw.rollingWearCoef = mods.rollingWearCoef or DEFAULT_MODS.rollingWearCoef or 1.0
        ctw.skinVelCoolScale = mods.skinVelCoolScale or DEFAULT_MODS.skinVelCoolScale or 1.0
        ctw.workHeatG0 = mods.workHeatG0 or DEFAULT_MODS.workHeatG0 or 0.22
        -- Pitwall reload-proof chips (profile knobs, pre-climate / pre-width display)
        data.lastAirCoolProfile = mods.airCoolingRate or 0
        data.lastSkinVelCoolScale = ctw.skinVelCoolScale
        data.lastWorkHeatG0 = ctw.workHeatG0
        data.lastSlipHeatProfile = mods.slipHeatRate or 0
        data.lastWorkHeatProfile = mods.workHeatRate or 0
        data.lastTrackCondMult = mods.trackConductivityMult or 1.0
        data.lastStaticCoolProfile = mods.staticCoolingRate or 0
        ctw.workHeatRate = workHeatRate
        ctw.currentTempK = currentTempK
        ctw.initialTempK = initialTempK
        ctw.thermalAbsPSI = thermalAbsPSI
        ctw.warmAbsolutePressurePSI = warmAbsolutePressurePSI
        ctw.fwdSoftDamp = fwdSoftDamp
        ctw.awdSoftDamp = awdSoftDamp
        ctw.vehicleSpeed = vehicleSpeed
end


-- Integrate 8-node temps from ctw scratch (own 200-local budget)
F.ctwStepThermalNodes = function(wheelID, dt, localEnvTemp, wd, w, data, mods)
    local fwdSoftDamp = ctw.fwdSoftDamp
    local awdSoftDamp = ctw.awdSoftDamp
    local adjustedChangeRate = ctw.adjustedChangeRate
    local airConductionRate = ctw.airConductionRate
    local airCoolingFactor = ctw.airCoolingFactor
    local airCoolingRate = ctw.airCoolingRate
    local airInertia = ctw.airInertia
    local angularVel = ctw.angularVel
    local avgCarcassTemp = ctw.avgCarcassTemp
    local avgWeightedTemp = ctw.avgWeightedTemp
    local bf = ctw.bf
    local brakeCoreTemp = ctw.brakeCoreTemp
    local brakeEffSoak = ctw.brakeEffSoak
    local brakeGainRate = ctw.brakeGainRate
    local brakeSurfaceTemp = ctw.brakeSurfaceTemp
    local brakeTorque = ctw.brakeTorque
    local carcassPropScale = ctw.carcassPropScale
    local carcassRate = ctw.carcassRate
    local climateScale = ctw.climateScale
    local conductanceTreadScale = ctw.conductanceTreadScale
    local contactDepth = ctw.contactDepth
    local coreCoolRate = ctw.coreCoolRate
    local coreVelCoolRate = ctw.coreVelCoolRate
    local cruiseNm = ctw.cruiseNm
    local current_working_temp = ctw.current_working_temp
    local driveHeatGateCarcass = ctw.driveHeatGateCarcass
    local ductPct = ctw.ductPct
    local ductSoakCondFactor = ctw.ductSoakCondFactor
    local dynamicPressurePSI = ctw.dynamicPressurePSI
    local effectiveAirspeed = ctw.effectiveAirspeed
    local estimatedContactArea = ctw.estimatedContactArea
    local excessPropGate = ctw.excessPropGate
    local excessPropGateCarcass = ctw.excessPropGateCarcass
    local excessPropGateEff = ctw.excessPropGateEff
    local flexModifier = ctw.flexModifier
    local g_mag = ctw.g_mag
    local groundModel = ctw.groundModel
    local heatMassScale = ctw.heatMassScale
    local isAirborne = ctw.isAirborne
    local isDirtGrassSurface = ctw.isDirtGrassSurface
    local isGravelSurface = ctw.isGravelSurface
    local isIceSurface = ctw.isIceSurface
    local isMudSurface = ctw.isMudSurface
    local isSandSurface = ctw.isSandSurface
    local isSnowSurface = ctw.isSnowSurface
    local isSportPlusProf = ctw.isSportPlusProf
    local isWetSurface = ctw.isWetSurface
    local jbeamMu = ctw.jbeamMu
    local jbeamSlideMu = ctw.jbeamSlideMu
    local load_kg = ctw.load_kg
    local load_kg_thermal = ctw.load_kg_thermal
    local longSlipEnergy = ctw.longSlipEnergy
    local netTorque = ctw.netTorque
    local patchFrac = ctw.patchFrac
    local patchHeatScale = ctw.patchHeatScale
    local peakWorkFactor = ctw.peakWorkFactor
    local pressureRatio = ctw.pressureRatio
    local propAbs = ctw.propAbs
    local rimRate = ctw.rimRate
    local rollingResistance = ctw.rollingResistance
    local safeAirspeed = ctw.safeAirspeed
    local sideSlipEnergy = ctw.sideSlipEnergy
    local skinCoreConductance = ctw.skinCoreConductance
    local slipEnergy = ctw.slipEnergy
    local slipHeatRate = ctw.slipHeatRate
    local staticCoolingRate = ctw.staticCoolingRate
    local streetCarcassScale = ctw.streetCarcassScale
    local streetSlipHeatScale = ctw.streetSlipHeatScale
    local surfaceAreaScale = ctw.surfaceAreaScale
    local tempDistWeighted = ctw.tempDistWeighted
    local trackConductivityMult = ctw.trackConductivityMult
    local trackTemp = ctw.trackTemp
    local tyreWidthCoeff = ctw.tyreWidthCoeff
    local vehNotParked = ctw.vehNotParked
    local verticalCarcassHeat = ctw.verticalCarcassHeat
    local wCenter = ctw.wCenter
    local wLeft = ctw.wLeft
    local wRight = ctw.wRight
    local workHeatRate = ctw.workHeatRate

    -- Snapshot nodes before coupled updates (reuse scratch — no per-step alloc)
    local skinSnap = scratchSkinSnap
    skinSnap[1], skinSnap[2], skinSnap[3] = data.temp[1], data.temp[2], data.temp[3]
    local carcassSnap = scratchCarcassSnap
    carcassSnap[1], carcassSnap[2], carcassSnap[3] = data.temp[4], data.temp[5], data.temp[6]
    local rimSnap = data.temp[7] or localEnvTemp
    local airSnap = data.temp[8] or localEnvTemp

    -- Spawn convection grace: ease freestream fight against garage soak for ~SPAWN_CONV_GRACE_S
    data.spawnAge = (data.spawnAge or 0) + dt
    local spawnConvScale = 1.0
    if SPAWN_CONV_GRACE_S > 0 and data.spawnAge < SPAWN_CONV_GRACE_S then
        local u = max(0, min(1, data.spawnAge / SPAWN_CONV_GRACE_S))
        u = u * u * (3.0 - 2.0 * u) -- smoothstep
        spawnConvScale = lerp(0.35, 1.0, u)
    end

    -- P4: mild direct solar → skin (trackTemp already carries bulk sun); speed-damped for park soak
    local todSkin = trackEnv.timeOfDay or 0.5
    if todSkin > 1.0 then todSkin = todSkin / 24.0 end
    local solarAngleSkin = max(0, cos((todSkin - 0.5) * 2 * pi))
    local cloudSkin = max(0, min(1, trackEnv.cloudCover or 0.2))
    local solarSkinPower = solarAngleSkin * (1.0 - cloudSkin * 0.85) * (topo.solarSkinGain or 0.026)
        / (1.0 + safeAirspeed * (topo.solarSkinSpeedDamp or 0.05))
    local rainAmt = 0
    if electrics and electrics.values and type(electrics.values.rainState) == "number" then
        rainAmt = max(0, min(1, electrics.values.rainState))
    end
    local filmEvap = max(waterFilmDepth, (rainAmt > 0.05) and max(0.25, rainAmt) or 0)
    local wetEvapExtra = (topo.wetEvapSkinCoef or 0.014) * filmEvap

    -- Lateral carcass bias from side-slip (outer shoulder works harder in a slide)
    local sideBias = 0
    if (longSlipEnergy + sideSlipEnergy) > 1e-4 then
        sideBias = max(-0.35, min(0.35, (sideSlipEnergy - longSlipEnergy * 0.35) * 0.15 * (wd.wheelDir or 1)))
    end
    local wLeftB = max(0.08, wLeft * (1.0 - sideBias))
    local wRightB = max(0.08, wRight * (1.0 + sideBias))
    local wCenterB = max(0.08, wCenter)
    local carcassWeights = scratchCarcassWeights
    carcassWeights[1], carcassWeights[2], carcassWeights[3] = wLeftB / (wLeftB + wCenterB + wRightB), wCenterB / (wLeftB + wCenterB + wRightB), wRightB / (wLeftB + wCenterB + wRightB)

    for i = 1, 3 do
        local weight = carcassWeights[i]
        local loadCoeff = weight * load_kg_thermal
        -- Cornering work only — straight-line bump noise must not inflate skin heat.
        -- Soft C4 workHeatG0 0.04: light/medium turn-in can warm; other compounds stay 0.22.
        local relative_work = max(0, g_mag - (ctw.workHeatG0 or 0.22)) * loadCoeff / 1000
        
        -- High-speed soft-saturation slide heat (street driven residual slip soft-cap applied here)
        local slipEnergyHeat = (slipEnergy / (1.0 + slipEnergy * 0.12)) * streetSlipHeatScale

        -- Rebalanced skin ring heating rates to prevent rapid thermal saturation
        local rawFrictionalGain = (slipEnergyHeat * 0.05 + netTorque * 0.002) * 3 * weight
        
        local surfaceMu = ((ctw.gmStatic or groundModel.staticFrictionCoefficient or 1) * 0.55
            + (ctw.gmSliding or groundModel.slidingFrictionCoefficient or groundModel.staticFrictionCoefficient or 1) * 0.45) * jbeamMu
        local slideMuScale = max(0.5, min(1.6, jbeamSlideMu / max(0.2, jbeamMu)))

        -- Skin slip/work: compound rates + optional skinSlipWorkScale (default 1; no track fudge)
        local slipWorkScale = topo.skinSlipWorkScale or 1.10
        local slipEnergyHeatWork = slipEnergy / (1.0 + slipEnergy * 0.12)
        rawFrictionalGain = rawFrictionalGain * (max(surfaceMu - 0.5, 0.1) * 2)
            + (((0.0078 * (slipEnergyHeat * slipEnergyHeat) * loadCoeff) * slipHeatRate * slideMuScale
                + 0.145 * relative_work * workHeatRate * peakWorkFactor / (1 + (slipEnergyHeatWork * slipEnergyHeatWork))) * surfaceMu / tyreWidthCoeff) * slipWorkScale
                
        rawFrictionalGain = rawFrictionalGain + ((verticalCarcassHeat * 0.005 * workHeatRate) / heatMassScale) * weight

        -- Surface sliding heat dampening (inline select)
        local frictionalGain = (rawFrictionalGain / heatMassScale) * ((tempDistWeighted > 1.1) and max(0.30, 1.0 - (tempDistWeighted - 1.1) * 0.6) or 1.0)
            * (isIceSurface and 0.20 or isSnowSurface and 0.25 or isMudSurface and 0.35 or isSandSurface and 0.45 or isDirtGrassSurface and 0.55 or isGravelSurface and 0.70 or isWetSurface and 0.85 or 1.0)

        -- Locked / locking wheel: sliding work is a circumferential flat, not whole-ring heating.
        -- Without this, 1–3s of ABS lock cooks skin → hot cliff → multi-second delay before roll resumes.
        if not isAirborne and angularVel < LOCKUP_OMEGA_THRESH and slipEnergy > 0.20 then
            frictionalGain = frictionalGain * lerp(LOCKUP_HEAT_FLOOR, 1.0, max(0, min(1, angularVel / LOCKUP_OMEGA_THRESH)))
        end
        -- P0-1: deposit slip/work/torque heat on patch-resident fraction (integrates with lockup floor)
        -- Street residual slip soft-cap also trims excess-prop slip/work boost (driven FWD cook).
        frictionalGain = frictionalGain * patchHeatScale * (1.0 + ((topo.drivePropSlipWorkMult or 1.0) - 1.0) * excessPropGateEff * streetSlipHeatScale)
        -- Phase D + Path A1: soft sink / rough / GM soft-wet damp frictional heat
        if not isAirborne then
            local sinkDamp = 1.0 / (1.0 + max(0, contactDepth or 0) * (topo.softSinkHeatCoef or 1.2)
                + (ctw.gmRough or tonumber(groundModel.rough) or 0) * (topo.softSinkRoughCoef or 0.35)
                + (ctw.softGmExtra or 0))
            frictionalGain = frictionalGain * max(topo.softSinkHeatFloor or 0.72, sinkDamp)
        end
        -- P4: mild solar→skin (shared across rings by weight)
        frictionalGain = frictionalGain + solarSkinPower * weight

        local tempDelta = ((skinSnap[i] or localEnvTemp) - localEnvTemp)
        
        -- TURBULENT CONVECTION (v^0.8). 0.155 skin scale: cruise still mild; track retains more heat.
        -- Free-belt cool uses geometric patchFrac (not heat floor): larger patch → less freeFrac cool.
        -- Intentionally separate from patchHeatScale so we don't also amplify RR via hystSkinShare.
        local velCool = (effectiveAirspeed ^ 0.8) * airCoolingRate * 0.155 * (ctw.skinVelCoolScale or 1.0) * airCoolingFactor * surfaceAreaScale / (1.0 + min(0.18, max(0, g_mag - 0.20) * 0.22))
        local totalConvection = tempDelta * (staticCoolingRate * 0.04 + velCool) * climateScale * (1.0 + (1.0 - patchFrac) * (topo.freeBeltCoolMult - 1.0)) * spawnConvScale
        
        if tempDelta > 0 then
            totalConvection = totalConvection + tempDelta * climateScale * (
                (isWetSurface and 0.020 or 0) + ((isIceSurface or isSnowSurface) and 0.030 or 0) + wetEvapExtra)
        end

        local tempK_skin = (skinSnap[i] or localEnvTemp) + 273.15
        -- STEFAN-BOLTZMANN GREY-BODY RADIATION MODEL (Calibrated surface-area-to-mass scaling)
        local radiationCooling = (RUBBER_EMISSIVITY * STEFAN_BOLTZMANN * (tempK_skin^4 - (localEnvTemp + 273.15)^4)) * 0.0001

        local surfaceConduction = 0
        if not isAirborne then
            local surfaceConductivity = ASPHALT_CONDUCTIVITY * trackConductivityMult
            local surfaceTemp = trackTemp
            if isIceSurface then
                surfaceConductivity, surfaceTemp = 2.0 * trackConductivityMult, min(localEnvTemp, 0)
            elseif isSnowSurface then
                surfaceConductivity, surfaceTemp = 0.20 * trackConductivityMult, min(localEnvTemp, 0)
            elseif isMudSurface then
                surfaceConductivity, surfaceTemp = 0.45 * trackConductivityMult, localEnvTemp
            elseif isSandSurface then
                surfaceConductivity, surfaceTemp = 0.25 * trackConductivityMult, localEnvTemp + (trackTemp - localEnvTemp) * 0.45
            elseif isGravelSurface or isDirtGrassSurface then
                surfaceConductivity, surfaceTemp = 0.55 * trackConductivityMult, localEnvTemp + (trackTemp - localEnvTemp) * 0.55
            elseif isWetSurface then
                surfaceConductivity, surfaceTemp = 0.75 * trackConductivityMult, localEnvTemp + (trackTemp - localEnvTemp) * 0.35
            end
            -- Soft sink (contactDepth) or rough / soft-wet GM reduces clean asphalt conduction
            surfaceConduction = max(-25, min(110,
                (surfaceConductivity * estimatedContactArea * ((skinSnap[i] or localEnvTemp) - surfaceTemp) / THERMAL_BOUNDARY_LAYER)
                / (1 + slipEnergy * 0.1)
                * 0.003 / (1.0 + max(0, contactDepth or 0) * 4.0
                    + (ctw.gmRough or tonumber(groundModel.rough) or 0) * 0.5
                    + (ctw.condGmExtra or 0))
            )) * weight
        end

        -- Skin ↔ matching carcass lane (L/C/R)
        local skinT = skinSnap[i] or localEnvTemp
        -- P1-1: real skin lateral conductance (mirrors carcass); soft avg equalizer mostly retired
        local skinLateral
        if i == 2 then
            skinLateral = (((skinSnap[1] or localEnvTemp) - skinT) + ((skinSnap[3] or localEnvTemp) - skinT)) * (topo.skinLateralConductance * 0.5)
        else
            skinLateral = ((skinSnap[2] or localEnvTemp) - skinT) * topo.skinLateralConductance
        end

        data.temp[i] = skinT + dt * (frictionalGain
            - (totalConvection + radiationCooling + surfaceConduction)
            + (avgWeightedTemp - skinT) * topo.skinEqualizerRetain
            + skinLateral
            + ((carcassSnap[i] or localEnvTemp) - skinT) * skinCoreConductance * conductanceTreadScale
        ) * adjustedChangeRate / tyreWidthCoeff
    end

    -- Soft-saturate ω so RR heat grows like real rolling power vs v^0.8 convection (ΔT rises slowly with speed)
    local angularVelHeat = abs(angularVel) / (1.0 + abs(angularVel) / 90.0)
    -- Cruise RR soft-cap (Phase 2: scales default 1.0 = off for Soft C4 A/B; was 0.48/0.72).
    local cruiseRRScale = 1.0
    local rrFull = topo.cruiseRrScaleFull or 1.0
    local rrPart = topo.cruiseRrScalePartial or 1.0
    if slipEnergy < 0.08 and g_mag < 0.35 and abs(brakeTorque) < 50 then
        cruiseRRScale = rrFull
    elseif slipEnergy < 0.15 and g_mag < 0.55 then
        cruiseRRScale = rrPart
    end
    -- Prop-linked RR damp: base load·ω RR opens under drive and was feeding carcass runaway
    -- (slick constant scale; street high-V scale). Blend toward carcassPropScale with excessPropGate.
    local propRrDamp = 1.0
    if carcassPropScale < 0.999 and excessPropGate > 1e-4 then
        propRrDamp = 1.0 + (carcassPropScale - 1.0) * excessPropGate
    end
    -- Scale hysteresis with carcass excess gate (base at cruise; full hystExcess when hard throttle).
    -- Skin uses excessPropGateEff; carcass hyst/flex use excessPropGateCarcass (slick / street high-V cut).
    -- Base load·ω RR (cruise soft-cap + prop damp). Coast-axle warm-up is flexWarmGain, not a separate RR mult.
    local totalHysteresisHeat = (
        (load_kg_thermal * angularVelHeat * 0.0000028 * (0.45 * exp(-0.5 * (avgWeightedTemp / current_working_temp - 1)^2) + 0.15) * rollingResistance * cruiseRRScale * propRrDamp)
        + (verticalCarcassHeat * 0.01 * workHeatRate)
        + (propAbs * driveHeatGateCarcass * angularVelHeat * (topo.drivePropHystBase + (topo.drivePropHystExcess - topo.drivePropHystBase) * excessPropGateCarcass) * rollingResistance)
    ) / heatMassScale

    -- P0-2: gated flex warm-up into carcass (load × speed × g/slip). Does NOT bypass cruiseRRScale —
    -- straights keep workGate≈0 so Belasco GT-IV highway soak stays soft-capped.
    local flexWarmHeat = 0
    if not isAirborne and vehNotParked > 0 then
        local flexGate = max(0, min(1, (load_kg - topo.flexWarmLoad0) / max(1, topo.flexWarmLoad1 - topo.flexWarmLoad0)))
            * max(0, min(1, (safeAirspeed - topo.flexWarmSpeed0) / max(1, topo.flexWarmSpeed1 - topo.flexWarmSpeed0)))
            * max(0, min(1, max(0, g_mag - topo.flexWarmG0) / 0.70 + slipEnergy * 1.8))
        if flexGate > 1e-4 then
            local coldCoreBoost = (avgCarcassTemp < current_working_temp)
                and (1.0 + 0.35 * max(0, min(1, (current_working_temp - avgCarcassTemp) / max(20.0, mods.coldWidth or DEFAULT_MODS.coldWidth))))
                or 1.0
            flexWarmHeat = flexGate * topo.flexWarmGain * load_kg_thermal * angularVelHeat * rollingResistance * flexModifier * coldCoreBoost / heatMassScale
            -- Excess prop: damp base flex that co-fires with hard throttle / prop-hold (slick or street high-V)
            flexWarmHeat = flexWarmHeat * propRrDamp
        end
        -- Extra carcass flex on excess prop; carcass gate (slick / street high-V cut vs skin)
        if excessPropGateCarcass > (topo.drivePropFlexGateStart or 0.12) then
            flexWarmHeat = flexWarmHeat
                + ((excessPropGateCarcass - (topo.drivePropFlexGateStart or 0.12)) / max(1e-3, 1.0 - (topo.drivePropFlexGateStart or 0.12)))
                * topo.drivePropFlexExcess * load_kg_thermal * angularVelHeat * rollingResistance * flexModifier / heatMassScale
        end
    end

    local carcassCoolCoef = ((topo.carcassCoolVelCoef or 0.28) * coreVelCoolRate * (effectiveAirspeed ^ 0.8 * 0.20) * airCoolingFactor
        + (topo.carcassCoolStaticCoef or 0.20) * coreCoolRate) * climateScale

    -- Share a slice of RR/flex work with skin so carcass doesn't runaway vs freestream-cooled tread.
    -- Phase C: bulk leak — intentionally NOT × patchHeatScale (slip/work already patch-scaled).
    local carcassWork = totalHysteresisHeat + flexWarmHeat
    local hystSkinShare = max(0, min(0.45, topo.hystSkinShare or 0.18))
    if hystSkinShare > 1e-6 and carcassWork > 0 then
        for i = 1, 3 do
            data.temp[i] = data.temp[i]
                + dt * carcassWork * hystSkinShare * carcassWeights[i] * adjustedChangeRate / tyreWidthCoeff
        end
    end
    local carcassWorkRemain = carcassWork * (1.0 - hystSkinShare)

    -- Carcass L/C/R: RR heat by load bias, skin coupling, rim soak, lateral diffusion, air
    for i = 1, 3 do
        local weight = carcassWeights[i]
        local carT = carcassSnap[i] or localEnvTemp
        local lateral
        if i == 2 then
            lateral = (((carcassSnap[1] or localEnvTemp) - carT) + ((carcassSnap[3] or localEnvTemp) - carT)) * (CARCASS_LATERAL_CONDUCTANCE * 0.5)
        else
            lateral = ((carcassSnap[2] or localEnvTemp) - carT) * CARCASS_LATERAL_CONDUCTANCE
        end
        data.temp[i + 3] = carT + (
            ((skinSnap[i] or localEnvTemp) - carT) * skinCoreConductance * conductanceTreadScale
            + (rimSnap - carT) * RIM_CARCASS_CONDUCTANCE * ductSoakCondFactor
            + (airSnap - carT) * airConductionRate * 0.05
            + lateral
            + carcassWorkRemain * weight
            - (carT - localEnvTemp) * carcassCoolCoef
        ) * carcassRate * dt
    end

    avgCarcassTemp = F.TempCarcassToAvgTemp(data.temp, w.combinedBias, pressureRatio, localEnvTemp)

    -- Rim / brake soak node: rotor heat enters here, then conducts into carcass + cavity air.
    -- brakeMass/diameter already scale rimInertia→rimRate; area + rotorMaterial scale soak gain.
    local brakeAreaScale = max(0.6, min(1.8, (bf.brakeCoolingArea or 0.1) / 0.12))
    local rotorMat = string.lower(bf.rotorMaterial or "steel")
    local rotorCoolMult = (rotorMat == "aluminum" or rotorMat == "aluminium") and 1.15
        or (string.find(rotorMat, "carbon") and 0.90 or 1.0)
    -- Soak coupling (separate from rim air-cool): Al conducts more into hub; carbon-ceramic less
    local rotorSoakMult = (rotorMat == "aluminum" or rotorMat == "aluminium") and 1.08
        or (string.find(rotorMat, "carbon") and 0.82 or 1.0)
    local radiantCoef = topo.brakeRadiantCoef or 2.2e-11
    local radiantToRim = radiantCoef * ((brakeSurfaceTemp + 273.15)^4 - (rimSnap + 273.15)^4)
        * brakeGainRate * ductSoakCondFactor * brakeAreaScale * rotorSoakMult
    local rimCarcassNet = (carcassWeights[1] * ((carcassSnap[1] or localEnvTemp) - rimSnap)
        + carcassWeights[2] * ((carcassSnap[2] or localEnvTemp) - rimSnap)
        + carcassWeights[3] * ((carcassSnap[3] or localEnvTemp) - rimSnap))
        * RIM_CARCASS_CONDUCTANCE * ductSoakCondFactor
    local rimCool = (rimSnap - localEnvTemp)
        * (0.22 * (effectiveAirspeed ^ 0.8 * 0.28) * airCoolingFactor * rotorCoolMult + 0.08)
        * climateScale * brakeAreaScale

    -- Fire / hot-node soak (same helper BeamNG brake thermals use)
    local fireToRim = 0
    local fireFn = fire and fire.getClosestHotNodeTempDistance
    if type(fireFn) == "function" and wd.node1 then
        local okF, fireTemperature, fireDistance = pcall(fireFn, wd.node1)
        if okF and type(fireTemperature) == "number" and type(fireDistance) == "number" then
            fireToRim = max((fireTemperature - rimSnap) * 0.04 * max(10 - fireDistance, 0), 0)
        end
    end

    local soakCommon = brakeGainRate * ductSoakCondFactor * brakeAreaScale * brakeEffSoak * rotorSoakMult
    local brakeSurfTerm = ((topo.brakeSurfSoak or 0.016) * (brakeSurfaceTemp - rimSnap)) * soakCommon
    local brakeCoreTerm = ((topo.brakeCoreSoak or 0.0025) * (brakeCoreTemp - rimSnap)) * soakCommon
    local brakeSoakPower = brakeSurfTerm + brakeCoreTerm + radiantToRim
    data.brakeSoakRateCs = brakeSoakPower * rimRate

    -- Duty mods: topology/runtime gates actively applying this frame (Heavy UI; not profile knobs)
    local dutyMods = ""
    if streetSlipHeatScale < 0.999 then
        dutyMods = isSportPlusProf and "sport_plus_slip_softcap" or "fwd_slip_softcap"
    end
    if streetCarcassScale < 0.999 then
        dutyMods = (dutyMods == "") and "street_high_v_damp" or (dutyMods .. ",street_high_v_damp")
    end
    if drivenWheelCount >= 3 and excessPropGate > 1e-4 and propAbs > (cruiseNm * 0.5) then
        dutyMods = (dutyMods == "") and "awd_prop_gate" or (dutyMods .. ",awd_prop_gate")
    end
    if fwdSoftDamp then
        dutyMods = (dutyMods == "") and "fwd_soft_drive_damp" or (dutyMods .. ",fwd_soft_drive_damp")
    end
    if awdSoftDamp then
        dutyMods = (dutyMods == "") and "awd_soft_front_damp" or (dutyMods .. ",awd_soft_front_damp")
    end
    if flexWarmHeat > 1e-8 and propAbs < (topo.drivePropDrivenThreshNm or 40) then
        dutyMods = (dutyMods == "") and "undriven_warmup" or (dutyMods .. ",undriven_warmup")
    end
    if brakeSoakPower > 0.015 and (brakeSurfaceTemp - rimSnap) > 10 then
        dutyMods = (dutyMods == "") and "brake_tire_soak" or (dutyMods .. ",brake_tire_soak")
    end
    if ductPct > (DUCT_DEFAULT_PCT + 4) then
        dutyMods = (dutyMods == "") and "duct_tire_side" or (dutyMods .. ",duct_tire_side")
    end
    if not isAirborne and ((contactDepth or 0) > 0.015 or (ctw.gmRough or tonumber(groundModel.rough) or 0) > 0.15
        or (ctw.gmDefDepth or 0) > 0.008 or (ctw.gmFluid or 0) > 40 or (ctw.gmStrength or 1) < 0.88) then
        dutyMods = (dutyMods == "") and "soft_sink_damp" or (dutyMods .. ",soft_sink_damp")
    end
    if (data.aeroHeatThermalFrac or 1) < 0.999 then
        dutyMods = (dutyMods == "") and "aero_heat_disc" or (dutyMods .. ",aero_heat_disc")
    end
    data.lastDutyMods = dutyMods

    data.temp[7] = rimSnap + (
        brakeSoakPower + rimCarcassNet
        + (airSnap - rimSnap) * RIM_AIR_CONDUCTANCE
        + fireToRim - rimCool
    ) * rimRate * dt

    -- Cavity air: lags carcass + rim (pressure thermometer); dedicated airThermalInertia (P1-2)
    data.temp[8] = airSnap + (
        (avgCarcassTemp - airSnap) * airConductionRate * 4.0
        + ((data.temp[7] or localEnvTemp) - airSnap) * RIM_AIR_CONDUCTANCE * 2.0
        - (airSnap - localEnvTemp) * (airConductionRate * 0.08 * ((dynamicPressurePSI + 14.696) / 14.696) * (1.0 + abs(angularVel) * 0.006)) * climateScale
    ) * (1.0 / max(0.05, airInertia)) * dt


    -- Bridge locals into ctw scratch for wear helper (Lua local-cap)
    ctw.avgWeightedTemp = avgWeightedTemp
    ctw.avgCarcassTemp = avgCarcassTemp -- post-step carcass (heat-leak gate; skin flash must not count)
    ctw.current_working_temp = current_working_temp
    ctw.tempDistWeighted = tempDistWeighted
    ctw.isAirborne = isAirborne
    ctw.slipEnergy = slipEnergy
    ctw.sideSlipEnergy = sideSlipEnergy
    ctw.tyreWidthCoeff = tyreWidthCoeff
    ctw.brakeTorque = brakeTorque
    ctw.angularVel = angularVel
    ctw.wLeft = wLeft
    ctw.wCenter = wCenter
    ctw.wRight = wRight
    ctw.contactDepth = contactDepth
    ctw.isWetSurface = isWetSurface
    ctw.isMudSurface = isMudSurface
    ctw.isSnowSurface = isSnowSurface
    ctw.isSandSurface = isSandSurface
    ctw.isGravelSurface = isGravelSurface
    ctw.isDirtGrassSurface = isDirtGrassSurface
    ctw.isIceSurface = isIceSurface
    ctw.vehNotParked = vehNotParked
end

-- CalcTyreWear thermal integration: two functions so each stays under Lua 200 locals.
F.ctwIntegrateThermals = function(wheelID, dt, localEnvTemp, wd, w, data, mods)
    F.ctwPrepareThermals(wheelID, dt, localEnvTemp, wd, w, data, mods)
    assertCtwWearContractOnce()
    F.ctwStepThermalNodes(wheelID, dt, localEnvTemp, wd, w, data, mods)
end

-- CalcTyreWear wear / damage / pressure (own local scope)

F.CalcTyreWear = function(wheelID, dt, localEnvTemp)
    local wd = wheels.wheelRotators[wheelID]
    local w = wheelCache[wheelID]
    local data = tyreData[wheelID]
    if not wd or not w or not data then return end

    localEnvTemp = localEnvTemp or ENV_TEMP
    dt = dt or 0.01
    data.temp = F.ensureTempNodes(data.temp, localEnvTemp)

    local mods = data.interpolatedMods or DEFAULT_MODS
    F.ctwIntegrateThermals(wheelID, dt, localEnvTemp, wd, w, data, mods)
    F.ctwIntegrateWear(wheelID, dt, localEnvTemp, wd, w, data, mods)
end

-- =============================================================================
-- GRIP (hot path — do not split without regression sign-off)
-- =============================================================================

-- COMPRESSED LOOKUP GRIP MATH: Scans pre-calculated static coefficient rows to avoid execution branches
-- profileLower: already string.lower'd (cached on tyreData); do not re-lower on the hot path.
F.getProfileBaselineGrip = function(profileLower, x)
    local p_lower = profileLower or ""
    local c = nil
    for i = 1, #GRIP_COEFFS do
        if string.find(p_lower, GRIP_COEFFS[i][1], 1, true) then
            c = GRIP_COEFFS[i][2]
            break
        end
    end
    c = c or { 0.85, 0.10, -0.05 } -- Default standard passenger fallback
    return c[1] + x * ((c[2] or 0) + x * ((c[3] or 0) + x * (c[4] or 0)))
end

-- A2 mild scalar-only Cond→grip fade (default on). A/B off with flag.
-- Never feeds HUD min(sc,nd) or node peak into wearPenalty while spike on.
local ENABLE_SCALAR_GRIP_FADE = true
local SCALAR_GRIP_FADE_START = 0.30 -- lifeUsed before fade (sc < 70%); was 0.40 / sc < 60%
local SCALAR_GRIP_FADE_FLOOR = 0.90 -- wearPenalty at lifeUsed ≈ 1 (mild; not old 0.75)

F.CalculateTyreGrip = function(wheelID, localEnvTemp)
    local data = tyreData[wheelID]
    local w = wheelCache[wheelID]
    local wd = wheels.wheelRotators[wheelID]
    if not data or not w or not wd then return 1, 1, 1 end

    localEnvTemp = localEnvTemp or ENV_TEMP
    local mods = data.interpolatedMods or DEFAULT_MODS
    local rawJBeamTread = wd.treadCoef or 0.5
    local treadCoef = rawJBeamTread 
    local softnessCoef = wd.softnessCoef or 0.5
    local initialPressurePSI = max(1.0, data.coldPressurePSI or wd.pressure or 25.0)
    local currentPSI = data.currentPressurePSI or initialPressurePSI
    
    local optP = max(1.0, data.targetHotPressurePSI or mods.optimalPressure or 25.0)
    local pOffset = (currentPSI / optP) - 1.0
    local sensitivity = mods.pressureSensitivity or 0.5

    local avgTemp = F.EffectiveTyreTemp(data.temp, w.combinedBias, currentPSI / optP, localEnvTemp, mods)
    -- A1 held for HUD hybrid: Cond may mirror node peak for display. Baseline profile
    -- grip still treats condition as 100 while spike on (node μ owns contact scallop).
    -- A2: wearPenalty may apply mild fade from scalarTreadCondition only (flagged).
    local nodeSpikeOwnsWear = F.isNodeWearSpikeEnabled and F.isNodeWearSpikeEnabled()
    local cond = data.condition or 100
    if nodeSpikeOwnsWear then cond = 100 end
    local x = cond * 0.01
    
    local compliance = mods.casingCompliance or 0.5
    local camberSens = mods.camberSensitivity or 1.0
    local bottomOutSens = mods.bottomOutSensitivity or 1.0

    local profile1 = data.profile1
    local profile2 = data.profile2
    local profile1Lower = data.profile1Lower or ""
    local profile2Lower = data.profile2Lower or ""
    local interpFactor = data.interpFactor or 0

    local baselineGrip1 = F.getProfileBaselineGrip(profile1Lower, x)
    local baselineGrip2 = F.getProfileBaselineGrip(profile2Lower, x)
    local tyreGrip = lerp(baselineGrip1, baselineGrip2, interpFactor)

    -- DYNAMIC SURFACE CLASSIFICATION (cached until contact material / rain changes)
    local groundModel = w.groundModel or DOESNT_EXIST_DATA
    local isRaining = electrics and electrics.values and type(electrics.values.rainState) == "number" and electrics.values.rainState > 0
    local surfaceType, flags = F.resolveWheelSurface(w, groundModel, isRaining)
    local isWetSurface = flags.wet
    local isLooseSurface = flags.loose
    local gmName = flags.gmName or (groundModel.nameLower or "")

    -- WEAR GRIP PENALTY
    -- Spike on + ENABLE_SCALAR_GRIP_FADE: mild fade from scalarTreadCondition only
    -- (life clock; never min(sc,nd) / node peak). Spike off: legacy condition path.
    local wearPenalty = 1.0
    if nodeSpikeOwnsWear then
        if ENABLE_SCALAR_GRIP_FADE then
            local sc = data.scalarTreadCondition
            if sc == nil then sc = 100 end
            local lifeUsed = max(0, min(1, (100 - sc) * 0.01))
            if lifeUsed > SCALAR_GRIP_FADE_START then
                local t = (lifeUsed - SCALAR_GRIP_FADE_START) / (1.0 - SCALAR_GRIP_FADE_START)
                wearPenalty = lerp(1.0, SCALAR_GRIP_FADE_FLOOR, max(0, min(1, t)))
            end
        end
    else
        if isLooseSurface then
            local minGripFactor = lerp(0.30, 0.55, 1.0 - treadCoef) 
            wearPenalty = lerp(minGripFactor, 1.0, x)
        else
            wearPenalty = lerp(0.75, 1.0, x)
        end
    end
    tyreGrip = tyreGrip * wearPenalty

    -- Profile-owned thermal grip curve (ambient does not shift the compound peak)
    local thermalMultiplier = F.getProfileThermalGrip(mods, avgTemp, compliance, softnessCoef)

    -- Street: mild cold forgiveness. Race/slick/sport+: sharpen cold cliff (anti high-G trip on cold μ)
    local p1Cold = profile1Lower
    local p2Cold = profile2Lower
    local isRaceCold = string.find(p1Cold, "slick", 1, true) or string.find(p2Cold, "slick", 1, true)
        or string.find(p1Cold, "sport_plus", 1, true) or string.find(p2Cold, "sport_plus", 1, true)
    if thermalMultiplier < 1.0 then
        if isRaceCold then
            thermalMultiplier = max(0.42, thermalMultiplier ^ 1.12)
        else
            local thermalTolerance = lerp(1.18, 1.08, treadCoef)
            thermalMultiplier = max(0.50, thermalMultiplier ^ (1.0 / thermalTolerance))
        end
    end

    -- Mild adhesion shaping (old full square + high sport+ adhesion capped warm-up grip ~80–86%)
    local adhesionWeight = max(0.15, min(0.75, mods.adhesion or 0.45))
    local tTherm = max(0, thermalMultiplier)
    local shaped = tTherm * (0.62 + 0.38 * tTherm) -- between linear and quadratic
    local compoundThermalGrip = lerp(tTherm, shaped, adhesionWeight * 0.55)
    tyreGrip = tyreGrip * compoundThermalGrip * (mods.gripMultiplier or 1.0)

    -- Compound × surface character (AT/MT/winter/slick/etc.)
    tyreGrip = F.applyProfileSurfaceBias(tyreGrip, surfaceType, profile1Lower, profile2Lower)
    local longPressureScale, latPressureScale = F.CalcPressureGripScales(pOffset, sensitivity, isLooseSurface)

    -- Dynamically scales vertical tire load sensitivity by active wheelCount to handle trucks/duallys
    local staticLoad = (vehicleMass * 9.81) / wheelCount
    local loadSensitivityModifier = 1.0 / (1.0 + (mods.loadSensitivity or DEFAULT_MODS.loadSensitivity) * max(0, ((w.loadRaw or 0) / max(1, staticLoad)) - 1.0))
    -- Blend with stock JBeam noLoadCoef / fullLoadCoef curve
    local bf = data.baseFactors
    if bf and bf.noLoadCoef and bf.fullLoadCoef then
        local loadN = max(0, w.loadRaw or 0)
        local tLoad = min(1.0, loadN * (bf.loadSensitivitySlope or 0.00015) * 8.0)
        local jbeamLoadCoef = lerp(bf.noLoadCoef, bf.fullLoadCoef, tLoad)
        loadSensitivityModifier = loadSensitivityModifier * max(0.80, min(1.25, jbeamLoadCoef))
        -- Soft coupling to stock frictionCoef (do not double-count vs setFrictionThermalSensitivity)
        tyreGrip = tyreGrip * max(0.88, min(1.12, 0.55 + 0.45 * (bf.frictionCoef or 1.0)))
    end
    tyreGrip = tyreGrip * max(0.70, loadSensitivityModifier)

    -- Dynamic Wet & Hydroplaning Model (film depth from rain accumulation)
    if isWetSurface or waterFilmDepth > 0.05 then
        local drainage = mods.waterDrainage or 0.5
        local speedMPS = w.airspeed or 0
        local film = isWetSurface and max(waterFilmDepth, 0.35) or waterFilmDepth
        local widthHelp = max(0, min(8, ((wd.tireWidth or wd.tyreWidth or wd.width or 0.2) - 0.18) * 40))
        local thresholdSpeed = 10.0 + (drainage * 28.0) + max(-5.0, min(10.0, (currentPSI - 25.0) * 0.3)) + widthHelp - film * 8.0
        local exponent = max(-20.0, min(20.0, -0.16 * (speedMPS - thresholdSpeed)))
        local hydroplaneFactor = (speedMPS > 3.0) and (1.0 / (1.0 + exp(exponent))) or 0.0
        
        local baseWetPenalty = 0.14 * (1.0 - drainage) * (0.5 + film * 0.5)
        local dynamicPenalty = 0.55 * hydroplaneFactor * (1.0 - drainage * 0.40) * (0.4 + film * 0.6)
        -- Wet gravel: less classic hydroplane, more slurry — soften hydro term
        if surfaceType == "gravel_wet" then
            dynamicPenalty = dynamicPenalty * 0.55
            baseWetPenalty = baseWetPenalty * 0.70
        end
        tyreGrip = tyreGrip * (1.0 - min(0.78, baseWetPenalty + dynamicPenalty))
        tyreGrip = tyreGrip * (mods.wetGripScale or 1.0)
        -- Wet asphalt must not beat the same compound on dry asphalt (MT/logger wetGripScale overshoot)
        if surfaceType == "wet_paved" then
            local dryScale = select(1, F.getSurfaceSanityScale("dry_paved", treadCoef, drainage))
            local wetScale = select(1, F.getSurfaceSanityScale("wet_paved", treadCoef, drainage))
            local dryMod = mods.dryGripScale or 1.0
            local wetMod = mods.wetGripScale or 1.0
            local dryBias = 1.0
            local p1 = profile1Lower
            local p2 = profile2Lower
            if string.find(p1, "mudterrain", 1, true) or string.find(p2, "mudterrain", 1, true)
                or string.find(p1, "crawler", 1, true) or string.find(p2, "crawler", 1, true)
                or string.find(p1, "offroad", 1, true) or string.find(p2, "offroad", 1, true)
                or string.find(p1, "logger", 1, true) or string.find(p2, "logger", 1, true) then
                dryBias = 0.96
            elseif string.find(p1, "highway", 1, true) or string.find(p2, "highway", 1, true)
                or string.find(p1, "trailer", 1, true) or string.find(p2, "trailer", 1, true) then
                dryBias = 1.02
            else
                -- Mirror street asphalt bias (standard/vintage only; sport uses dryGripScale)
                if string.find(p1, "standard", 1, true) or string.find(p2, "standard", 1, true)
                    or string.find(p1, "vintage", 1, true) or string.find(p2, "vintage", 1, true) then
                    dryBias = 1.02
                end
            end
            local ratioCap = (dryScale * dryMod * dryBias) / max(1e-3, wetScale * wetMod) * 0.98
            if ratioCap < 1.0 then
                tyreGrip = tyreGrip * ratioCap
            end
        end
    elseif surfaceType == "dry_paved" or surfaceType == "hard_smooth" then
        -- Pavement / smooth props only — do not apply dryGripScale on rock (offroad MT penalty was wrong there)
        tyreGrip = tyreGrip * (mods.dryGripScale or 1.0)
    end

    -- Distinct damage grip penalties
    -- Clog: rally/offroad on loose only (street compounds never pack); ~16–28% peak loss
    if (data.currentClog or data.clog or 0) > 0.01 then
        local clogAmt = data.currentClog or data.clog
        local clogCoef = 0.28
        local p1c = profile1Lower
        local p2c = profile2Lower
        if string.find(p1c, "rally", 1, true) or string.find(p2c, "rally", 1, true) then
            clogCoef = 0.16
        end
        tyreGrip = tyreGrip * (1.0 - clogAmt * clogCoef * lerp(1.2, 0.6, treadCoef))
    end
    if (data.currentGraining or data.graining or 0) > 0.01 then
        tyreGrip = tyreGrip * (1.0 - (data.currentGraining or data.graining) * 0.22)
    end
    -- Ignore first ~8% blister (UI noise); then ramp to ~29% grip loss at full blister
    local blisterGrip = data.currentBlistering or data.blistering or 0
    if blisterGrip > 0.08 then
        tyreGrip = tyreGrip * (1.0 - (blisterGrip - 0.08) * 0.32)
    end
    if (data.heatCycles or 0) > 0 then
        local stintFadeRateGrip = mods.stintFadeRate or DEFAULT_MODS.stintFadeRate or 1.0
        tyreGrip = tyreGrip * (1.0 - min(0.15, data.heatCycles * 0.02 * stintFadeRateGrip)) -- hardened compound loses grip
    end
    if (data.stintFade or 0) > 0 then
        tyreGrip = tyreGrip * (1.0 - data.stintFade)
    end

    -- Camber penalty + mild camber thrust (grip bias, not spindle forces)
    local slideFactor = max(0, min(1, (w.slipEnergy or 0) / 0.50))
    local camberAbs = abs(w.camber or 0)
    local excessiveCamber = max(0, camberAbs - (2.5 + compliance * 3.5))
    local camberPenaltyFactor = 1.0 / (1.0 + excessiveCamber * excessiveCamber * (0.016 - compliance * 0.009) * camberSens)
    tyreGrip = tyreGrip * lerp(camberPenaltyFactor, 1.0, slideFactor)
    -- Camber thrust: small lateral preference when camber is working in the contact patch
    local camberThrust = max(0, min(0.06, camberAbs * 0.004 * (1.0 - slideFactor) * compliance))

    -- Unified suspension grip (single path — no stacked stress/vel/deflection penalties)
    -- Compression bump/bottom-out and droop unloading both reduce available patch load quality.
    local suspGripModifier = 1.0
    local bump = w.suspBump or 0
    local droop = w.suspDroop or 0
    local suspVel = w.suspensionVelocity or 0
    if bump > 0 then
        -- Soft bump: mild; hard bump (beyond SUSP_HARD band encoded in stress): stronger
        local hardFrac = min(1.0, bump / max(1e-3, SUSP_HARD_BUMP_M - SUSP_SOFT_BUMP_M))
        suspGripModifier = suspGripModifier * max(0.82, 1.0 - bump * 1.8 * bottomOutSens - hardFrac * 0.08 * bottomOutSens)
    end
    if droop > 0 then
        suspGripModifier = suspGripModifier * max(0.78, 1.0 - droop * 2.2)
    end
    -- Fast damper stroke: brief unload / scrub (extension = negative vel when hub dropping)
    if abs(suspVel) > 0.35 then
        suspGripModifier = suspGripModifier * max(0.88, 1.0 - (abs(suspVel) - 0.35) * 0.06)
    end
    tyreGrip = tyreGrip * suspGripModifier

    local surfaceScale, surfaceCap = F.getSurfaceSanityScale(surfaceType, treadCoef, mods.waterDrainage or 0.5)
    local gmStatic = max(0.0, groundModel.staticFrictionCoefficient or 1.0)
    local gmSliding = max(0.0, groundModel.slidingFrictionCoefficient or gmStatic)
    -- FRICTIONLESS / zero-μ pads: collapse grip instead of dividing by tiny μ (cap explosion)
    if gmStatic <= 0.01 and gmSliding <= 0.01 then
        tyreGrip = tyreGrip * 0.02
    else
        local gmMu = max(0.05, (gmStatic * 0.65) + (gmSliding * 0.35))
        local beamSurfaceReference = max(0.18, min(1.20, gmMu))
        tyreGrip = min(tyreGrip * surfaceScale, surfaceCap / beamSurfaceReference)
    end

    -- Zone wear: outer/inner wear hurts lateral more; center hurts longitudinal more
    -- A1: zoneCondition is HUD-only while node spike owns wear feel (no second grip tax).
    local zoneLatPen, zoneLongPen = 1.0, 1.0
    if not nodeSpikeOwnsWear then
        local zc = data.zoneCondition or { 100, 100, 100 }
        zoneLatPen = 1.0 - ((100 - (zc[1] or 100)) + (100 - (zc[3] or 100))) * 0.0015
        zoneLongPen = 1.0 - (100 - (zc[2] or 100)) * 0.0020
    end
    local longGrip = tyreGrip * longPressureScale * (mods.longGripMult or 1.0) * max(0.55, zoneLongPen)
    local latGrip = tyreGrip * latPressureScale * (mods.latGripMult or 1.0) * max(0.55, zoneLatPen) * (1.0 + camberThrust)

    -- Tip-over protection: only after real load transfer (preserve turn-in bite)
    do
        local loadRatio = (w.loadRaw or 0) / max(1.0, staticLoad)
        if loadRatio > 1.32 then
            local overload = min(1.6, loadRatio - 1.32)
            latGrip = latGrip * max(0.72, 1.0 - overload * 0.22)
        end
    end

    -- Anti-trip ceiling: race compounds — softer than v3 so turn-in isn't dead
    do
        local p1r = profile1Lower
        local p2r = profile2Lower
        local isRaceLat = string.find(p1r, "slick", 1, true) or string.find(p2r, "slick", 1, true)
            or string.find(p1r, "sport_plus", 1, true) or string.find(p2r, "sport_plus", 1, true)
        if isRaceLat then
            local latCap = 1.12 -- sport_plus
            -- supersoft_slick contains "soft_slick" — check C5 first.
            if string.find(p1r, "supersoft_slick", 1, true) or string.find(p2r, "supersoft_slick", 1, true) then
                latCap = 1.20
            elseif string.find(p1r, "soft_slick", 1, true) or string.find(p2r, "soft_slick", 1, true) then
                latCap = 1.18
            elseif string.find(p1r, "medium_slick", 1, true) or string.find(p2r, "medium_slick", 1, true) then
                latCap = 1.16
            elseif string.find(p1r, "hard_slick", 1, true) or string.find(p2r, "hard_slick", 1, true) then
                latCap = 1.14
            end
            local tOptLat = mods.optimalTemp or DEFAULT_MODS.optimalTemp
            local coldFrac = max(0, min(1, (tOptLat - avgTemp) / max(20.0, tOptLat * 0.45)))
            local hotFrac = max(0, min(1, (avgTemp - tOptLat) / max(20.0, tOptLat * 0.40)))
            latCap = latCap * (1.0 - 0.18 * coldFrac - 0.12 * hotFrac)
            if latGrip > latCap then latGrip = latCap end
        end
    end

    -- Friction write uses raw grip (PhysicsLoop). Brake lock fade is off — native lock.
    tyreGripTable[wheelID] = tyreGrip
    return longGrip, latGrip, tyreGrip
end

-- Brake lock fade: DISABLED (V2 experimental). Lock is native BeamNG
-- (brake torque vs patch μ). ReSpin only writes thermal/wear scales via
-- setFrictionThermalSensitivity — not a lock controller.
-- Set ENABLE_BRAKE_LOCK_FADE true only for A/B debug; keep false for normal use.
local ENABLE_BRAKE_LOCK_FADE = false

F.refreshBrakeLockInputs = function()
    -- no-op while lock fade is off (kept so call sites stay stable)
end

-- Returns: longGrip, latGrip, fade01 (Pitwall Lock fade; always 0 when disabled)
F.applyBrakeLockFade = function(longGrip, latGrip, _wd, _w)
    if not ENABLE_BRAKE_LOCK_FADE then
        return longGrip, latGrip, 0
    end
    -- Legacy path removed from hot use. Re-enable only with an explicit experiment
    -- branch; do not reintroduce pedal/gx μ collapses for production.
    return longGrip, latGrip, 0
end

-- Front/rear from common BeamNG wheel names (FL/FR/RL/RR, wheel_FL, …).

-- =============================================================================
-- GFX LOOP & VEHICLE LIFECYCLE
-- =============================================================================

F.updateGFX = function(dt)
    -- BeamMP remotes: do not integrate thermals or write native friction/pressure.
    if F.isRemoteMpVehicle() then return end
    if not wheels or not wheels.wheelRotators then return end
    if not next(wheelIndexMap) then F.initGuiStream() end
    if not next(tyreData) then F.initTyreData() end

    -- Prefer GE mailbox when present (even if unchanged this frame). Previously we only
    -- marked envReceived on mailbox *change*, so native getEnvTemperature ran every frame
    -- between 2 Hz GE ticks and fought altitude/mailbox steps → noisy ΔT + wasted work.
    local envFromMailbox = false
    if obj and obj.getLastMailbox then
        local env = obj:getLastMailbox("tireWearMailboxEnvTemp")
        if env then
            envFromMailbox = true
            if env ~= lastEnvMailbox then
                lastEnvMailbox = env
                local rawEnv = F.sanitizeEnvTemp(env)
                local blended = ENV_TEMP + (rawEnv - ENV_TEMP) * min(1.0, dt * ENV_SMOOTH_RATE)
                local maxStep = ENV_MAX_DELTA_PER_SEC * dt
                local delta = blended - ENV_TEMP
                if delta > maxStep then delta = maxStep elseif delta < -maxStep then delta = -maxStep end
                ENV_TEMP = ENV_TEMP + delta
                if rawEnv < rawEnvMin then rawEnvMin = rawEnv end
                if rawEnv > rawEnvMax then rawEnvMax = rawEnv end
            end
        end

        local trackEnvMailbox = obj:getLastMailbox("tireWearMailboxTrackEnv")
        if trackEnvMailbox and trackEnvMailbox ~= lastTrackEnvMailbox then
            lastTrackEnvMailbox = trackEnvMailbox
            local decoded = decodeMailbox(trackEnvMailbox)
            if decoded then
                trackEnv.timeOfDay = decoded.timeOfDay or trackEnv.timeOfDay
                trackEnv.cloudCover = decoded.cloudCover or trackEnv.cloudCover
            end
        end

        -- Front/Rear duct % from Tuning menu (GE createbrakeductsliders)
        local ductMailbox = obj:getLastMailbox("tireWearMailboxDuct")
        if ductMailbox and ductMailbox ~= lastDuctMailbox then
            lastDuctMailbox = ductMailbox
            local decoded = decodeMailbox(ductMailbox)
            if decoded then
                brakeDuctSettings[1] = tonumber(decoded[1]) or brakeDuctSettings[1]
                brakeDuctSettings[2] = tonumber(decoded[2]) or brakeDuctSettings[2]
            end
        end

        -- Per-vehicle draft wake from LuuksDraftingMod (soft companion; no-op if absent)
        local draftMailbox = obj:getLastMailbox("tireWearMailboxDraft")
        if draftMailbox and draftMailbox ~= draft.lastMailbox then
            draft.lastMailbox = draftMailbox
            local decoded = decodeMailbox(draftMailbox)
            if decoded then
                local myId = objCall("getID") or objectId
                local mine = decoded[myId] or decoded[tostring(myId)]
                if type(mine) == "table" then
                    F.setDraftWake(mine.wake, mine.side, mine.push, mine.airTempDelta)
                end
            end
        end
    end

    F.decayDraftWake(dt)

    if not envFromMailbox then
        local nativeKelvin = objCall("getEnvTemperature")
        if nativeKelvin and nativeKelvin > 0 then
            local nativeCelsius = nativeKelvin - 273.15
            local rawEnv = F.sanitizeEnvTemp(nativeCelsius)
            local blended = ENV_TEMP + (rawEnv - ENV_TEMP) * min(1.0, dt * ENV_SMOOTH_RATE)
            local maxStep = ENV_MAX_DELTA_PER_SEC * dt
            local delta = blended - ENV_TEMP
            if delta > maxStep then delta = maxStep elseif delta < -maxStep then delta = -maxStep end
            ENV_TEMP = ENV_TEMP + delta
            if rawEnv < rawEnvMin then rawEnvMin = rawEnv end
            if rawEnv > rawEnvMax then rawEnvMax = rawEnv end
        end
    end

    local localizedEnvTemp = ENV_TEMP
    -- Mild diurnal only as last-resort when env feed is completely flat (not a fake weather system)
    local envTempRange = rawEnvMax - rawEnvMin
    if envTempRange < 0.5 and (not envFromMailbox) then
        local rad = (trackEnv.timeOfDay - 0.16) * 2 * pi
        localizedEnvTemp = ENV_TEMP + 2.0 * -cos(rad)
    end

    -- Pack air: hotter ambient in a wake (inferred on 0.39+; companion on older builds)
    if draft.airTempEffective > 0 then
        localizedEnvTemp = localizedEnvTemp + draft.airTempEffective
    end

    -- Water film accumulation from rainState (0..1); decays when dry
    local rainState = 0
    if electrics and electrics.values and type(electrics.values.rainState) == "number" then
        rainState = max(0, min(1, electrics.values.rainState))
    end
    if rainState > 0 then
        waterFilmDepth = min(1.0, waterFilmDepth + rainState * dt * 0.15)
    else
        waterFilmDepth = max(0, waterFilmDepth - dt * 0.04)
    end
    -- Immersed wheels dump water onto the contact patch
    for _, wc in pairs(wheelCache) do
        if wc and wc.underWater then
            waterFilmDepth = min(1.0, waterFilmDepth + dt * 0.35)
            break
        end
    end

    -- Sample track surface once per GFX frame (physics + UI share this)
    frameTrackTemp = F.getTrackTemp(localizedEnvTemp, trackEnv.timeOfDay, trackEnv.cloudCover)
    frameChassisSpeed = objChassisSpeed()
    
    local upVector = objCall("getDirectionVectorUp")
    local frontVector = objCall("getDirectionVector")
    local invQuat = nil
    if upVector and frontVector and quatFromDir then
        local ok, q = pcall(quatFromDir, vec3(frontVector), vec3(upVector))
        if ok and q then invQuat = q:inversed() end
    end

    local airspeed = F.getFreestreamAirspeed()
    -- Stint trip (m): freestream integrate; ignore crawl/park jitter
    if airspeed and airspeed > 0.5 and dt and dt > 0 and dt < 0.25 then
        stintDistanceM = stintDistanceM + airspeed * dt
    end

    local gx_gfx = (sensors and (sensors.gx2 or sensors.gx) or 0) / 9.80665
    local gy_gfx = (sensors and (sensors.gy2 or sensors.gy) or 0) / 9.80665
    local g_mag = sqrt(gx_gfx * gx_gfx + gy_gfx * gy_gfx)

    F.prepareWheelFrame(dt, localizedEnvTemp, invQuat, upVector, airspeed, g_mag, gy_gfx)

    F.sampleNativeAero()
    F.runFixedPhysicsSteps(dt, localizedEnvTemp)
    if F.stepNodeWearSpike then F.stepNodeWearSpike(dt) end
    if F.stepNodeCollisionProbe then F.stepNodeCollisionProbe() end
    
    if DEBUG_THERMALS then
        local logParts = {}
        for wheelID, data in pairs(tyreData) do
            local avg = F.TempRingsToAvgTemp(data.temp, 0, 1.0, localizedEnvTemp)
            local carc = F.TempCarcassToAvgTemp(data.temp, 0, 1.0, localizedEnvTemp)
            local wName = wheelCache[wheelID] and wheelCache[wheelID].name or tostring(wheelID)
            table.insert(logParts, string.format("%s: Skin=%.1f Carc=%.1f Rim=%.1f Air=%.1f (Opt=%.1f)", wName, avg, carc, data.temp[7] or 0, data.temp[8] or 0, data.working_temp or 0))
        end
        print("TIRE_DEBUG: " .. table.concat(logParts, " | "))
    end

    sendTimer = sendTimer + dt
    if sendTimer >= SEND_INTERVAL then
        sendTimer = 0
        -- Global env snapshot only when flushing HUD (was every GFX frame)
        guiStream.envTemp = math.floor(localizedEnvTemp * 10) / 10
        guiStream.trackTemp = math.floor(frameTrackTemp * 10) / 10
        guiStream.rainState = math.floor((rainState or 0) * 100)
        guiStream.waterFilm = math.floor(waterFilmDepth * 100)
        guiStream.packWake = math.floor(max(draft.inferredWake, draft.coolingWake) * 100)
        guiStream.packAirDelta = math.floor(draft.airTempEffective * 10) / 10
        guiStream.streamHz = math.floor(1.0 / SEND_INTERVAL + 0.5)
        guiStream.timeOfDay = math.floor((trackEnv.timeOfDay or 0) * 1000) / 1000
        guiStream.cloudCover = math.floor((trackEnv.cloudCover or 0) * 100)
        guiStream.envTempRange = math.floor((rawEnvMax - rawEnvMin) * 10) / 10
        guiStream.stintKm = math.floor(stintDistanceM / 10) / 100 -- m → km, 2 decimals
        do
            local odoM = 0
            local ev = electrics and electrics.values
            if ev then
                odoM = tonumber(ev.odometer) or tonumber(ev.odometerTotal) or tonumber(ev.trip) or 0
                -- Some builds already expose km; treat values > 1e6 as meters, else if < 50000 and > stint assume km→m
                if odoM > 0 and odoM < 50000 and stintDistanceM > 1000 and odoM < stintDistanceM then
                    odoM = odoM * 1000
                end
            end
            guiStream.odoKm = math.floor(odoM / 10) / 100
        end
        local pos = objCall("getPosition")
        if pos and pos.z then
            guiStream.elevationM = math.floor(pos.z * 10) / 10
        end
        F.flushGuiStream(localizedEnvTemp)
        F.stampStreamIdentity()

        -- 0.39+: queueStream feeds StreamsManager / streamsUpdate. Prefer it alone so apps
        -- do not process the same payload twice (queueStream + trigger). Older builds keep trigger.
        -- Presence cached in onInit (hasQueueStream / hasGuiTrigger).
        -- Seated vehicle only — extra spawned cars / BeamMP remotes must not overwrite HUD.
        if F.isHudPublisher() then
            if hasQueueStream then
                guihooks.queueStream("TireWearThermals", guiStream)
            elseif hasGuiTrigger then
                guihooks.trigger("TireWearThermals", guiStream)
            end
        end
    end

    F.writeTelemetryIfEnabled(dt)
end

-- Single owner for spawn/reset clears of tables modules capture at install.
-- Always clear IN PLACE — never `wheelCache = {}` (orphans install closures → ice grip).
F.clearSharedCaches = function()
    for k in pairs(wheelCache) do wheelCache[k] = nil end
    for k in pairs(baseBrakeCoolings) do baseBrakeCoolings[k] = nil end
    for k in pairs(tyreGripTable) do tyreGripTable[k] = nil end
    if groundCache.lut then
        for k in pairs(groundCache.lut) do groundCache.lut[k] = nil end
    end
    classifyCache.vehicleType = nil
    classifyCache.rallyDamper = nil
    classifyCache.typeRetryCount = 0
    brakeDuctSettings[1] = DUCT_DEFAULT_PCT
    brakeDuctSettings[2] = DUCT_DEFAULT_PCT
    ctwWearContractChecked = false
end

F.onInit = function()
    local t0 = (os and os.clock and os.clock()) or 0
    local ok, err = pcall(function()
        -- onReset calls onInit; bump once per spawn/reset so HUD snaps instead of lerping stale heat.
        F.bumpResetGen()
        print("tireWearThermals vehicle extension onInit")
        -- BeamNG 0.39+: native inter-vehicle aero authority (do NOT call setWindAero)
        draft.hasNativeInterAero = obj and type(obj.setWindAero) == "function"
        -- Cache GUI publish path once (hot flush must not re-type-check every tick)
        hasQueueStream = guihooks and type(guihooks.queueStream) == "function"
        hasGuiTrigger = guihooks and type(guihooks.trigger) == "function"
        local weight = 1500
        if v and v.data and v.data.nodes then
            local sum = 0
            for _, n in pairs(v.data.nodes) do
                if type(n) == "table" and type(n.nodeWeight) == "number" then sum = sum + n.nodeWeight end
            end
            if sum > 0 then weight = sum end
        end
        
        if weight < 100 then
            weight = weight * 1000
        end
        vehicleMass = weight

        if not next(groundCache.models) then
            local targetID = objectId or objCall("getID") or 0
            objCall("queueGameEngineLua", "if tireWearThermals then tireWearThermals.getGroundModels(" .. tostring(targetID) .. ") end")
        end

        lastTrackEnvMailbox = nil
        lastEnvMailbox = nil
        rawEnvMin = 100
        rawEnvMax = -100
        F.clearSharedCaches()
        gfxAccumulator = 0
        waterFilmDepth = 0
        -- Keep / restore CSV arm across reset so stint data is never truncated
        telem.timer = 0
        lastDuctMailbox = nil
        draft.lastMailbox = nil
        draft.wake, draft.side, draft.push = 0, 0, 0
        draft.airTempDelta, draft.coolingWake = 0, 0
        draft.lastRxClock = 0
        draft.inferredWake = 0
        draft.convectionMult, draft.airTempEffective = 1.0, 0
        F.resetNativeAero()

        F.initTyreData()
        F.initGuiStream()
        if F.ensureNodeCollisionProbe then F.ensureNodeCollisionProbe() end
        -- Seed native friction before first grip step (avoids limbo μ on spawn)
        if wheels and wheels.wheelRotators then
            for i, wd in pairs(wheels.wheelRotators) do
                local wheel = F.resolveWheelFrictionTarget(i, wd)
                if wheel then
                    F.applyWheelFriction(wheel, 1.0, 1.0)
                end
            end
        end
        -- Soft reset keeps locals; full vehicle reload re-runs module — restore from arm marker
        if not telem.csvEnabled then
            F.restoreTelemetryAfterReload("onInit")
        elseif telem.csvEnabled and telem.path then
            -- Flush any pending samples before #RESET so stint data is never lost
            F.appendTelemetryResetMarker(nil, telem.path, "onReset")
        end
    end)
    if not ok then
        print("tireWearThermals onInit handled exception: " .. tostring(err))
    end
    local t1 = (os and os.clock and os.clock()) or t0
    local ms = (t1 - t0) * 1000
    if ms > 50 then
        local msg = string.format(
            "onInit took %.1f ms (nativeInterAero=%s). 0.39 may warn on slow extension loads.",
            ms, tostring(draft.hasNativeInterAero))
        if type(log) == "function" then
            log("W", "tireWearThermals", msg)
        else
            print("W|tireWearThermals|" .. msg)
        end
    elseif DEBUG_THERMALS then
        print(string.format("tireWearThermals onInit %.1f ms nativeInterAero=%s", ms, tostring(draft.hasNativeInterAero)))
    end
end

F.onReset = function()
    if F.resetNodeWearSpike then F.resetNodeWearSpike() end
    if F.resetNodeCollisionProbe then F.resetNodeCollisionProbe() end
    F.onInit()
end

-- Vehicle deserialize / hard reload: flush if somehow still buffered, then restore arm.
F.onDeserialized = function(_data)
    -- Same object id after a hard reload — new thermal life for HUD bind.
    F.bumpResetGen()
    F.flushTelemetryBuffer()
    if not telem.csvEnabled then
        F.restoreTelemetryAfterReload("onDeserialized")
    elseif telem.csvEnabled and telem.path then
        F.appendTelemetryResetMarker(nil, telem.path, "onDeserialized")
    end
end

-- 0.39 prefers onExtensionUnloaded over deprecated onUnload
F.onExtensionUnloaded = function()
    F.flushTelemetryBuffer()
    if F.resetNodeWearSpike then F.resetNodeWearSpike() end
    if F.unloadNodeCollisionProbe then F.unloadNodeCollisionProbe() end
    draft.wake, draft.side, draft.push = 0, 0, 0
    draft.airTempDelta, draft.coolingWake = 0, 0
    draft.inferredWake = 0
    draft.convectionMult, draft.airTempEffective = 1.0, 0
    draft.lastMailbox = nil
    F.resetNativeAero()
end

F.onSettingsChanged = function()
end

-- =============================================================================
-- MODULE INSTALL — must run before M.* exports (setGroundModels, initTyreData, …)
-- Order: Ground → Pressure → Temp → Draft → Classify → Wheel → Wear → NodeWear → NodeProbe → PhysicsLoop → Hud → Telemetry
-- =============================================================================

Ground.install(F, {
    cache = groundCache,
    topo = topo,
    missing = DOESNT_EXIST_DATA,
})

Pressure.install(F, {
    objPcall = objPcall,
    isRemoteMpVehicle = function() return F.isRemoteMpVehicle() end,
    getV = function() return v end,
})

Temp.install(F, {
    getEnvTemp = function() return ENV_TEMP end,
    TEMP_NODE_COUNT = TEMP_NODE_COUNT,
    WORKING_TEMP = WORKING_TEMP,
    DEFAULT_MODS = DEFAULT_MODS,
    THERMAL_TOPOLOGY = THERMAL_TOPOLOGY,
    lerp = lerp,
})

Draft.install(F, {
    draft = draft,
    getVehicleAirspeedRef = function() return F.getVehicleAirspeedRef() end,
    getFreestreamAirspeed = function() return F.getFreestreamAirspeed() end,
})

Classify.install(F, {
    DEFAULT_MODS = DEFAULT_MODS,
    STANDALONE_MODIFIERS = STANDALONE_MODIFIERS,
    PROFILE_POINTS = PROFILE_POINTS,
    SLICK_SPECTRUM_POINTS = SLICK_SPECTRUM_POINTS,
    UTILITY_SPECTRUM_POINTS = UTILITY_SPECTRUM_POINTS,
    COMMERCIAL_SPECTRUM_POINTS = COMMERCIAL_SPECTRUM_POINTS,
    ATV_UTV_SPECTRUM_POINTS = ATV_UTV_SPECTRUM_POINTS,
    VINTAGE_SPECTRUM_POINTS = VINTAGE_SPECTRUM_POINTS,
    cache = classifyCache,
    lerp = lerp,
})

Wheel.install(F, {
    getWheels = function() return wheels end,
    getV = function() return v end,
    objPcall = objPcall,
    objCall = objCall,
    vec3 = vec3,
    quat = quat,
    vecLen = vecLen,
    lerp = lerp,
    tyreData = tyreData,
    classifyCache = classifyCache,
    brakeDuctSettings = brakeDuctSettings,
    getEnvTemp = function() return ENV_TEMP end,
    WORKING_TEMP = WORKING_TEMP,
    DUCT_DEFAULT_PCT = DUCT_DEFAULT_PCT,
    MAX_DUCT_AIR_FACTOR = MAX_DUCT_AIR_FACTOR,
    SLICK_PREHEAT_BLEND = SLICK_PREHEAT_BLEND,
    STREET_PREHEAT_BLEND = STREET_PREHEAT_BLEND,
    SKIN_PREHEAT_FRAC = SKIN_PREHEAT_FRAC,
    setWheelCount = function(n) wheelCount = n end,
    resetStintDistance = function() stintDistanceM = 0 end,
    getTirePartName = function(name) return F.getTirePartName(name) end,
    getInterpolatedProfile = function(a, b, c, d, e, f, g) return F.getInterpolatedProfile(a, b, c, d, e, f, g) end,
    getNativeGroupPressurePSI = function(wd) return F.getNativeGroupPressurePSI(wd) end,
    getTuneColdFillPSI = function(front) return F.getTuneColdFillPSI(front) end,
    setNativeGroupPressurePSI = function(wd, psi) return F.setNativeGroupPressurePSI(wd, psi) end,
    seedHotTargetPSI = function(cold, opt) return F.seedHotTargetPSI(cold, opt) end,
    remapSlickSoftness = function(s) return F.remapSlickSoftness(s) end,
    isRemoteMpVehicle = function() return F.isRemoteMpVehicle() end,
})

Wear.install(F, {
    ctw = ctw,
    topo = topo,
    DEFAULT_MODS = DEFAULT_MODS,
    getEnvTemp = function() return ENV_TEMP end,
    WORKING_TEMP = WORKING_TEMP,
    TORQUE_ENERGY_MULTIPLIER = TORQUE_ENERGY_MULTIPLIER,
    missing = DOESNT_EXIST_DATA,
    getVehicleMass = function() return vehicleMass end,
    getWheelCount = function() return wheelCount end,
    lerp = lerp,
    tempDistToWearMult = function(td) return F.tempDistToWearMult(td) end,
    applyPressureLeakPa = function(wd, leak, dt) return F.applyPressureLeakPa(wd, leak, dt) end,
    deflateTireCompat = function(id) return F.deflateTireCompat(id) end,
    getNativeGroupPressurePSI = function(wd) return F.getNativeGroupPressurePSI(wd) end,
    isTirePressureInflateActive = function() return F.isTirePressureInflateActive() end,
    applyHotPressureWriteback = function(wd, pa, dt, mx, db) return F.applyHotPressureWriteback(wd, pa, dt, mx, db) end,
    seedHotTargetPSI = function(cold, opt) return F.seedHotTargetPSI(cold, opt) end,
})

NodeWear.install(F, {
    getWheels = function() return wheels end,
    wheelCache = wheelCache,
    tyreData = tyreData,
    objCall = objCall,
    isRemoteMpVehicle = function() return F.isRemoteMpVehicle() end,
})

NodeProbe.install(F, {
    getWheels = function() return wheels end,
    tyreData = tyreData,
    isRemoteMpVehicle = function() return F.isRemoteMpVehicle() end,
})

PhysicsLoop.install(F, {
    getWheels = function() return wheels end,
    wheelCache = wheelCache,
    tyreData = tyreData,
    tyreGripTable = tyreGripTable,
    topo = topo,
    objCall = objCall,
    SPIKE_STRIP_MATERIAL_ID = SPIKE_STRIP_MATERIAL_ID,
    NATIVE_SLIP_ENERGY_SCALE = NATIVE_SLIP_ENERGY_SCALE,
    NATIVE_SLIP_VEL_SCALE = NATIVE_SLIP_VEL_SCALE,
    FIXED_DT = FIXED_DT,
    GRIP_STEP_INTERVAL = GRIP_STEP_INTERVAL,
    getGfxAccumulator = function() return gfxAccumulator end,
    setGfxAccumulator = function(v) gfxAccumulator = v end,
    getGripStepCounter = function() return gripStepCounter end,
    setGripStepCounter = function(v) gripStepCounter = v end,
    setDrivenWheelCount = function(n) drivenWheelCount = n end,
    setDriveLayoutMode = function(m) driveLayoutMode = m end,
    TempCarcassToAvgTemp = function(t, b, p, e) return F.TempCarcassToAvgTemp(t, b, p, e) end,
})

Hud.install(F, {
    guiStream = guiStream,
    wheelIndexMap = wheelIndexMap,
    getWheels = function() return wheels end,
    wheelCache = wheelCache,
    tyreData = tyreData,
    tyreGripTable = tyreGripTable,
    nativeAero = nativeAero,
    getEnvTemp = function() return ENV_TEMP end,
    WORKING_TEMP = WORKING_TEMP,
    TEMP_NODE_COUNT = TEMP_NODE_COUNT,
    SEND_INTERVAL = SEND_INTERVAL,
    getWaterFilmDepth = function() return waterFilmDepth end,
    DOESNT_EXIST_DATA = DOESNT_EXIST_DATA,
    stampStreamIdentity = function() F.stampStreamIdentity() end,
    nativeAeroWheelShare = function(name, load) return F.nativeAeroWheelShare(name, load) end,
    classifySurfaceGrip = function(gm) return F.classifySurfaceGrip(gm) end,
    ensureTempNodes = function(t, e) return F.ensureTempNodes(t, e) end,
    TempCarcassToAvgTemp = function(t, b, p, e) return F.TempCarcassToAvgTemp(t, b, p, e) end,
    EffectiveTyreTemp = function(t, b, p, e, m) return F.EffectiveTyreTemp(t, b, p, e, m) end,
    getNativeBrakeTemps = function(wd, e) return F.getNativeBrakeTemps(wd, e) end,
    getBrakeDuctPercent = function(isFront) return F.getBrakeDuctPercent(isFront) end,
    getFreestreamAirspeed = function() return F.getFreestreamAirspeed() end,
    getChassisDynamicsSnapshot = function() return F.getChassisDynamicsSnapshot() end,
})

Telemetry.install(F, {
    telem = telem,
    tyreData = tyreData,
    tyreGripTable = tyreGripTable,
    getWheels = function() return wheels end,
    wheelCache = wheelCache,
    getNativeAero = function() return nativeAero end,
    getEnvTemp = function() return ENV_TEMP end,
    getWaterFilmDepth = function() return waterFilmDepth end,
    ensureTempNodes = F.ensureTempNodes,
    nativeAeroWheelShare = function(name, loadN) return F.nativeAeroWheelShare(name, loadN) end,
})

M.onSettingsChanged = F.onSettingsChanged
M.onInit = F.onInit
M.onReset = F.onReset
M.onDeserialized = F.onDeserialized
M.onExtensionUnloaded = F.onExtensionUnloaded
M.update = F.update
M.updateGFX = F.updateGFX
M.setGroundModels = F.setGroundModels
M.setDraftWake = F.setDraftWake
M.isRemoteMpVehicle = F.isRemoteMpVehicle
M.isHudPublisher = F.isHudPublisher
M.streamTag = F.streamTag
M.resetGen = function() return resetGen end
M.hasNativeInterAero = function() return draft.hasNativeInterAero end
M.getInferredWake = function() return draft.inferredWake end
M.flushTelemetryCsv = function()
    F.flushTelemetryBuffer()
end
M.setTelemetryCsv = function(enabled, path, intervalSec)
        local wasEnabled = telem.csvEnabled
        local prevPath = telem.path
        telem.csvEnabled = not not enabled
        if path and type(path) == "string" and #path > 0 then
            if telem.path and telem.path ~= path and telem.csvBufCount > 0 then
                -- Path change: flush old file before switching
                F.flushTelemetryBuffer()
            end
            if telem.path ~= path then
                telem.headerReady = false
            end
            telem.path = path
        end
        if type(intervalSec) == "number" and intervalSec > 0 then
            telem.interval = max(0.25, min(10.0, intervalSec))
        end
        if not telem.csvEnabled then
            -- Disarm: flush so no samples are stranded in RAM
            F.flushTelemetryBuffer()
            telem.timer = 0
            F.clearTelemetryArmMarker()
            return
        end
        if telem.path then
            F.writeTelemetryArmMarker(telem.path)
        end
        -- Header once on arm (or path change); not every sample / heartbeat re-arm
        if (not wasEnabled) or (prevPath ~= telem.path) or (not telem.headerReady) then
            local ioLib = F.getTelemetryIo()
            if ioLib and telem.path then
                F.ensureTelemetryHeader(ioLib, telem.path)
            end
        end
        if telem.lastFlushClock <= 0 then
            telem.lastFlushClock = os.clock()
        end
end

return M
