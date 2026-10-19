-- Upstream authorship: see CREDITS.md / NOTICE.

local M = {}

local DEFAULT_MODS = {
    adhesion = 0.45, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
    casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
    gripMultiplier = 1.00, longGripMult = 1.0, latGripMult = 1.0,
    optimalPressure = 32, optimalTemp = 65, pressureSensitivity = 0.5, rollingRes = 0.8, rollingHystScale = 1,
    staticCoolingRate = 0.08, slipHeatRate = 8.925, workHeatRate = 5.1, wearRate = 0.0005,
    treadInertia = 0.46, carcassInertia = 0.75, airThermalInertia = 0.22, thermalReactionRate = 1.35,
    tempPlateau = 15, coldWidth = 55, hotWidth = 55, gripFloor = 0.24,
    coldGripPower = 1.35, hotGripPower = 2.0,
    coldWearMult = 1.8, hotWearMult = 3.5, grainTempRatio = 0.75, blisterTempRatio = 1.55,
    grainRate = 0.00042, blisterRate = 0.00028,
    stintFadeRate = 1.0, camberWearMult = 1.0, rollingWearCoef = 1.0,
    waterDrainage = 0.8, wetGripScale = 1.0, dryGripScale = 1.0, trackConductivityMult = 1.0,
    skinVelCoolScale = 1.0,
    camberSensitivity = 1.0, bottomOutSensitivity = 1.0, scrubSensitivity = 1.0,

    driveSlipHeatMin = 1.0, driveSlipPropMin = 1.0, driveHighVCarcassScale = 1.0
}

local DRIVE_SOFTCAP_STREET = { driveSlipHeatMin = 0.90, driveSlipPropMin = 0.93, driveHighVCarcassScale = 0.80 }
local DRIVE_SOFTCAP_SPORT = { driveSlipHeatMin = 0.92, driveSlipPropMin = 0.95, driveHighVCarcassScale = 0.87 }
local DRIVE_SOFTCAP_SPORT_PLUS = { driveSlipHeatMin = 0.94, driveSlipPropMin = 0.97, driveHighVCarcassScale = 0.82 }
local DRIVE_SOFTCAP_TRACK_DAY = { driveSlipHeatMin = 0.97, driveSlipPropMin = 0.985, driveHighVCarcassScale = 0.91 }

local DRIVE_SOFTCAP_VINTAGE = { driveSlipHeatMin = 0.95, driveSlipPropMin = 0.97, driveHighVCarcassScale = 0.88 }
local DRIVE_SOFTCAP_OFF = { driveSlipHeatMin = 1.0, driveSlipPropMin = 1.0, driveHighVCarcassScale = 1.0 }
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

local DEFAULT_GRIP_COEFFS = {
    { "sport_plus", { 1.12, 0.22, -0.08 } },
    { "track_day", { 1.15, 0.22, -0.08 } },
    { "supersoft_slick", { 1.46, 0.36, -0.12 } },
    { "soft_slick", { 1.42, 0.34, -0.12 } },
    { "medium_slick", { 1.38, 0.32, -0.12 } },
    { "hard_slick", { 1.34, 0.30, -0.11 } },
    { "slick", { 1.38, 0.32, -0.12 } },
    { "sport", { 1.02, 0.16, -0.06 } },
    { "drag", { 1.28, 0.28, -0.10 } },
    { "drift", { 0.88, 0.12, -0.05 } },
    { "mudterrain", { 0.76, 0.08, -0.02 } },
    { "allterrain", { 0.82, 0.10, -0.03 } },
    { "rain", { 0.96, 0.14, -0.05 } },
    { "rally", { 0.98, 0.14, -0.05 } },
    { "winter", { 0.90, 0.12, -0.04 } },
    { "paddle", { 0.70, 0.08, -0.02 } },
    { "donut", { 0.68, 0.08, -0.03 } },
    { "crawler", { 0.72, 0.06, -0.02 } },
    { "vintage", { 0.88, 0.11, -0.04 } },
    { "utility", { 0.84, 0.08, -0.02 } },
    { "truck", { 0.86, 0.08, -0.02 } },
    { "heavy", { 0.84, 0.08, -0.02 } },
    { "standard", { 0.92, 0.12, -0.04 } },
    { "utv", { 0.78, 0.08, -0.02 } },
}

local GRIP_COEFFS = _G.GRIP_COEFFS
if not GRIP_COEFFS or #GRIP_COEFFS == 0 then
    GRIP_COEFFS = DEFAULT_GRIP_COEFFS
end

local STANDALONE_MODIFIERS = {
    drag = {
        adhesion = 0.58, airConductionRate = 0.018, airCoolingRate = 0.0175, brakeGainRate = 1.5,
        casingCompliance = 0.85, coreCoolRate = 0.021, coreVelCoolRate = 0.004, skinCoreConductance = 0.12,

        gripMultiplier = 1.32, longGripMult = 1.18, latGripMult = 0.92,
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

        gripMultiplier = 1.44, longGripMult = 0.95, latGripMult = 0.92,
        optimalPressure = 26, optimalTemp = 75, pressureSensitivity = 0.35, rollingRes = 1.02,
        staticCoolingRate = 0.08, slipHeatRate = 10.0, workHeatRate = 3.6, wearRate = 0.002,
        treadInertia = 0.40, carcassInertia = 0.648, thermalReactionRate = 1.3, tempPlateau = 14,
        coldWidth = 65, hotWidth = 65, gripFloor = 0.28, coldWearMult = 1.86,
        hotWearMult = 4.5, grainTempRatio = 0.78, blisterTempRatio = 1.80, waterDrainage = 0.4,
        wetGripScale = 0.95, dryGripScale = 1, trackConductivityMult = 1.15, camberSensitivity = 0.9,
        bottomOutSensitivity = 1, scrubSensitivity = 1.3
    },
    vintage = {
        adhesion = 0.28, airConductionRate = 0.0135, airCoolingRate = 0.02375, brakeGainRate = 0.6,
        casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,

        gripMultiplier = 1.15, longGripMult = 1, latGripMult = 1,
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

        gripMultiplier = 1.03, longGripMult = 1, latGripMult = 1,
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
        gripMultiplier = 0.74, longGripMult = 1, latGripMult = 1,
        optimalPressure = 10, optimalTemp = 48, pressureSensitivity = 0.22, rollingRes = 1.95,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.6, wearRate = 0.0008,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.5, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.62,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    },
    winter = {
        adhesion = 0.4, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.6,
        casingCompliance = 0.65, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,

        gripMultiplier = 1.22, longGripMult = 1, latGripMult = 1,
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

        gripMultiplier = 1.32, longGripMult = 0.95, latGripMult = 0.88,
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
        gripMultiplier = 0.96, longGripMult = 1.02, latGripMult = 1.07,
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

        gripMultiplier = 1.19, longGripMult = 1.02, latGripMult = 1.05,
        optimalPressure = 28, optimalTemp = 58, pressureSensitivity = 0.7, rollingRes = 1.18,
        staticCoolingRate = 0.08, slipHeatRate = 9.9, workHeatRate = 5.4, wearRate = 0.0008,
        treadInertia = 0.315, carcassInertia = 0.51, thermalReactionRate = 1.65, tempPlateau = 15,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 1.92,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.22, dryGripScale = 0.92, trackConductivityMult = 1, camberSensitivity = 1.1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.4
    }
}

local PROFILE_POINTS = {
    { tread = 0.30, profile = "sport_plus", mods = {
        adhesion = 0.52, airConductionRate = 0.015, airCoolingRate = 0.011, brakeGainRate = 1.35,
        casingCompliance = 0.45, coreCoolRate = 0.038, coreVelCoolRate = 0.0095, skinCoreConductance = 0.088,

        gripMultiplier = 1.11, longGripMult = 1.05, latGripMult = 1.02,
        optimalPressure = 31, optimalTemp = 76, pressureSensitivity = 0.75, rollingRes = 0.70,
        staticCoolingRate = 0.044, slipHeatRate = 13.63, workHeatRate = 7.96, wearRate = 0.0028,
        scalarTreadWearScale = 0.19,
        nodeWearScale = 1.10,
        treadInertia = 0.441, carcassInertia = 0.714, thermalReactionRate = 1.3, tempPlateau = 14,
        coldWidth = 52, hotWidth = 32, gripFloor = 0.24, coldWearMult = 1.908,
        hotWearMult = 5.60, grainTempRatio = 0.88, blisterTempRatio = 1.22, waterDrainage = 0.58,
        wetGripScale = 0.995, dryGripScale = 1.04, trackConductivityMult = 0.75, camberSensitivity = 1.1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.15, skinVelCoolScale = 0.50
    } },
    { tread = 0.40, profile = "track_day", mods = {
        adhesion = 0.444, airConductionRate = 0.015, airCoolingRate = 0.020, brakeGainRate = 1.32,
        casingCompliance = 0.42, coreCoolRate = 0.036, coreVelCoolRate = 0.0083, skinCoreConductance = 0.090,
        gripMultiplier = 1.04, longGripMult = 1.08, latGripMult = 1.0,
        optimalPressure = 31, optimalTemp = 76, pressureSensitivity = 0.71, rollingRes = 0.88,
        staticCoolingRate = 0.068, slipHeatRate = 8.96, workHeatRate = 4.82, wearRate = 0.0033,
        scalarTreadWearScale = 0.20,
        nodeWearScale = 1.0,
        treadInertia = 0.471, carcassInertia = 0.763, thermalReactionRate = 1.22, tempPlateau = 16,
        coldWidth = 64, hotWidth = 52, gripFloor = 0.28, coldWearMult = 1.84,
        hotWearMult = 3.05, grainTempRatio = 0.76, blisterTempRatio = 1.59, waterDrainage = 0.43,
        wetGripScale = 0.90, dryGripScale = 1.04, trackConductivityMult = 0.90, camberSensitivity = 1.18,
        bottomOutSensitivity = 1.04, scrubSensitivity = 1.28, skinVelCoolScale = 0.80
    } },
    { tread = 0.50, profile = "sport", mods = {
        adhesion = 0.42, airConductionRate = 0.015, airCoolingRate = 0.020, brakeGainRate = 1.2,
        casingCompliance = 0.5, coreCoolRate = 0.035, coreVelCoolRate = 0.008, skinCoreConductance = 0.076,

        gripMultiplier = 1.19, longGripMult = 1, latGripMult = 1,

        optimalPressure = 32, optimalTemp = 65, pressureSensitivity = 0.5, rollingRes = 0.8,
        staticCoolingRate = 0.065, slipHeatRate = 7.96, workHeatRate = 4.37, wearRate = 0.0026,
        scalarTreadWearScale = 0.15,
        nodeWearScale = 1.0,
        treadInertia = 0.483, carcassInertia = 0.782, thermalReactionRate = 1.2, tempPlateau = 18,
        coldWidth = 74, hotWidth = 55, gripFloor = 0.34, coldWearMult = 1.83,
        hotWearMult = 2.98, grainTempRatio = 0.88, blisterTempRatio = 1.55, waterDrainage = 0.72,
        wetGripScale = 1.03, dryGripScale = 1.02, trackConductivityMult = 1, camberSensitivity = 1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.1, skinVelCoolScale = 0.72
    } },
    { tread = 0.60, profile = "standard", mods = {

        adhesion = 0.41, airConductionRate = 0.01425, airCoolingRate = 0.02575, brakeGainRate = 1.05,
        casingCompliance = 0.55, coreCoolRate = 0.03675, coreVelCoolRate = 0.0084, skinCoreConductance = 0.072,

        gripMultiplier = 1.24, longGripMult = 1, latGripMult = 1,
        optimalPressure = 33, optimalTemp = 63, pressureSensitivity = 0.50, rollingRes = 0.82,
        staticCoolingRate = 0.0765, slipHeatRate = 8.25, workHeatRate = 4.27, wearRate = 0.000475,
        scalarTreadWearScale = 0.45,
        nodeWearScale = 0.82,
        treadInertia = 0.4935, carcassInertia = 0.799, thermalReactionRate = 1.225, tempPlateau = 17,
        coldWidth = 66, hotWidth = 55, gripFloor = 0.30, coldWearMult = 1.80,
        hotWearMult = 2.99, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.76,
        wetGripScale = 1.04, dryGripScale = 1.01, trackConductivityMult = 1, camberSensitivity = 0.95,

        bottomOutSensitivity = 1, scrubSensitivity = 1.05, skinVelCoolScale = 0.72
    } },
    { tread = 0.70, profile = "standard", mods = {

        adhesion = 0.4, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
        casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,

        gripMultiplier = 1.23, longGripMult = 1, latGripMult = 1,
        optimalPressure = 33, optimalTemp = 60, pressureSensitivity = 0.45, rollingRes = 0.82,
        staticCoolingRate = 0.08, slipHeatRate = 7.9, workHeatRate = 4.22, wearRate = 0.0005,
        scalarTreadWearScale = 0.33,
        nodeWearScale = 0.75,
        treadInertia = 0.504, carcassInertia = 0.816, thermalReactionRate = 1.25, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 3, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.9,

        bottomOutSensitivity = 1, scrubSensitivity = 1, skinVelCoolScale = 1
    } },
    { tread = 0.80, profile = "allterrain", mods = {
        adhesion = 0.36, airConductionRate = 0.012, airCoolingRate = 0.0325, brakeGainRate = 0.45,
        casingCompliance = 0.75, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.056,

        gripMultiplier = 1.24, longGripMult = 1, latGripMult = 1,
        optimalPressure = 30, optimalTemp = 56, pressureSensitivity = 0.35, rollingRes = 1.18,
        staticCoolingRate = 0.08, slipHeatRate = 7.2, workHeatRate = 3.96, wearRate = 0.00025,

        scalarTreadWearScale = 0.54,

        nodeWearScale = 0.75,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.05, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.9, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 0.7, scrubSensitivity = 0.9
    } },
    { tread = 0.85, profile = "allterrain", mods = {

        adhesion = 0.34, airConductionRate = 0.01125, airCoolingRate = 0.035, brakeGainRate = 0.375,
        casingCompliance = 0.775, coreCoolRate = 0.04725, coreVelCoolRate = 0.0108, skinCoreConductance = 0.048,

        gripMultiplier = 1.23, longGripMult = 1, latGripMult = 1,
        optimalPressure = 28, optimalTemp = 54, pressureSensitivity = 0.315, rollingRes = 1.30,
        staticCoolingRate = 0.08, slipHeatRate = 6.75, workHeatRate = 3.70, wearRate = 0.000225,

        scalarTreadWearScale = 0.55,
        nodeWearScale = 1,
        treadInertia = 0.630, carcassInertia = 1.020, thermalReactionRate = 1.0, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.725,
        hotWearMult = 2.89, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.925,
        wetGripScale = 1.12, dryGripScale = 0.97, trackConductivityMult = 0.75, camberSensitivity = 0.55,
        bottomOutSensitivity = 0.65, scrubSensitivity = 0.85
    } },
    { tread = 0.90, profile = "mudterrain", mods = {
        adhesion = 0.32, airConductionRate = 0.0105, airCoolingRate = 0.0375, brakeGainRate = 0.3,
        casingCompliance = 0.8, coreCoolRate = 0.049, coreVelCoolRate = 0.0112, skinCoreConductance = 0.04,

        gripMultiplier = 1.25, longGripMult = 1, latGripMult = 1,
        optimalPressure = 26, optimalTemp = 52, pressureSensitivity = 0.28, rollingRes = 1.42,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.43, wearRate = 0.0002,

        scalarTreadWearScale = 0.56,
        nodeWearScale = 1,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.95, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.88, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    } },
    { tread = 1.00, profile = "crawler", mods = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.85, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,

        gripMultiplier = 1.03, longGripMult = 1, latGripMult = 1,
        optimalPressure = 9, optimalTemp = 48, pressureSensitivity = 0.18, rollingRes = 1.7,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 2.90, wearRate = 0.00015,

        scalarTreadWearScale = 0.56,
        nodeWearScale = 1,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.9, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 1,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    } }
}

local SLICK_SPECTRUM_POINTS = {
    { softness = 0.50, profile = "hard_slick", mods = {
        adhesion = 0.48, airConductionRate = 0.015, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.3, coreCoolRate = 0.038, coreVelCoolRate = 0.0088, skinCoreConductance = 0.110,

        gripMultiplier = 1.03, longGripMult = 1, latGripMult = 1.00,

        optimalPressure = 28, optimalTemp = 90, pressureSensitivity = 0.95, rollingRes = 0.98, rollingHystScale = 1,
        staticCoolingRate = 0.060, slipHeatRate = 11.10, workHeatRate = 6.07, wearRate = 0.00115,
        rollingWearCoef = 50, scalarTreadWearScale = 6.4,
        treadInertia = 0.4536, carcassInertia = 0.7344, thermalReactionRate = 1.25, tempPlateau = 16.6,
        coldWidth = 61.6, hotWidth = 37.9, gripFloor = 0.24, coldWearMult = 1.86,
        hotWearMult = 3.15, grainTempRatio = 0.78, blisterTempRatio = 1.65, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.55, skinVelCoolScale = 0.50
    } },
    { softness = 0.575, profile = "hard_slick", mods = {
        adhesion = 0.50, airConductionRate = 0.01575, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.275, coreCoolRate = 0.0345, coreVelCoolRate = 0.008, skinCoreConductance = 0.115,

        gripMultiplier = 1.04, longGripMult = 1, latGripMult = 1.00,

        optimalPressure = 27.5, optimalTemp = 87, pressureSensitivity = 1.0, rollingRes = 1.00, rollingHystScale = 1,
        staticCoolingRate = 0.060, slipHeatRate = 11.50, workHeatRate = 6.31, wearRate = 0.00130,
        rollingWearCoef = 55, scalarTreadWearScale = 5.2,
        treadInertia = 0.4263, carcassInertia = 0.6902, thermalReactionRate = 1.335, tempPlateau = 16.0,
        coldWidth = 59.5, hotWidth = 36.6, gripFloor = 0.24, coldWearMult = 1.905,
        hotWearMult = 3.225, grainTempRatio = 0.78, blisterTempRatio = 1.65, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.60, skinVelCoolScale = 0.50
    } },
    { softness = 0.65, profile = "medium_slick", mods = {

        adhesion = 0.52, airConductionRate = 0.0165, airCoolingRate = 0.014, brakeGainRate = 1.0,
        casingCompliance = 0.25, coreCoolRate = 0.031, coreVelCoolRate = 0.0072, skinCoreConductance = 0.120,

        gripMultiplier = 1.02, longGripMult = 1, latGripMult = 1.00,

        optimalPressure = 27, optimalTemp = 84, pressureSensitivity = 1.05, rollingRes = 1.02, rollingHystScale = 3.80,

        staticCoolingRate = 0.060, slipHeatRate = 7.64, workHeatRate = 4.15, wearRate = 0.00135,
        rollingWearCoef = 42, scalarTreadWearScale = 9.3,
        treadInertia = 0.399, carcassInertia = 0.646, thermalReactionRate = 1.42, tempPlateau = 15.5,

        coldWidth = 36.0, hotWidth = 22.0, gripFloor = 0.24, coldWearMult = 1.95,
        hotWearMult = 3.30, grainTempRatio = 0.78, blisterTempRatio = 1.65, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.45,

        bottomOutSensitivity = 1.1, scrubSensitivity = 1.65, skinVelCoolScale = 0.90
    } },
    { softness = 0.725, profile = "medium_slick", mods = {

        adhesion = 0.535, airConductionRate = 0.016875, airCoolingRate = 0.014, brakeGainRate = 1.0,
        casingCompliance = 0.235, coreCoolRate = 0.031, coreVelCoolRate = 0.0074, skinCoreConductance = 0.122,

        gripMultiplier = 1.05, longGripMult = 1, latGripMult = 1.00,

        optimalPressure = 26.5, optimalTemp = 83, pressureSensitivity = 1.125, rollingRes = 1.05, rollingHystScale = 2.5,
        staticCoolingRate = 0.060, slipHeatRate = 7.90, workHeatRate = 4.30, wearRate = 0.00155,
        rollingWearCoef = 48, scalarTreadWearScale = 7.1,
        treadInertia = 0.3717, carcassInertia = 0.6018, thermalReactionRate = 1.485, tempPlateau = 15.3,
        coldWidth = 32.3, hotWidth = 23.1, gripFloor = 0.24, coldWearMult = 1.971,
        hotWearMult = 3.375, grainTempRatio = 0.78, blisterTempRatio = 1.635, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.50,
        bottomOutSensitivity = 1.15, scrubSensitivity = 1.70, skinVelCoolScale = 0.90
    } },
    { softness = 0.80, profile = "soft_slick", mods = {

        adhesion = 0.55, airConductionRate = 0.01725, airCoolingRate = 0.014, brakeGainRate = 1.1,
        casingCompliance = 0.22, coreCoolRate = 0.031, coreVelCoolRate = 0.0076, skinCoreConductance = 0.130,

        gripMultiplier = 1.00, longGripMult = 1, latGripMult = 1.00,

        optimalPressure = 26, optimalTemp = 82, pressureSensitivity = 1.2, rollingRes = 1.22, rollingHystScale = 2.20,

        staticCoolingRate = 0.140, slipHeatRate = 14.38, workHeatRate = 7.62, wearRate = 0.00255,
        rollingWearCoef = 70, scalarTreadWearScale = 4.7,
        treadInertia = 0.3444, carcassInertia = 0.5576, thermalReactionRate = 1.55, tempPlateau = 15.1,
        coldWidth = 56.1, hotWidth = 34.5, gripFloor = 0.24, coldWearMult = 2.35,
        hotWearMult = 4.70, grainTempRatio = 0.78, blisterTempRatio = 1.62, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.55,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.75, skinVelCoolScale = 0.85
    } },
    { softness = 0.875, profile = "supersoft_slick", mods = {
        adhesion = 0.565, airConductionRate = 0.017625, airCoolingRate = 0.014, brakeGainRate = 1.5,
        casingCompliance = 0.205, coreCoolRate = 0.031, coreVelCoolRate = 0.0078, skinCoreConductance = 0.138,

        gripMultiplier = 1.00, longGripMult = 1, latGripMult = 1.00,

        optimalPressure = 25.5, optimalTemp = 80, pressureSensitivity = 1.275, rollingRes = 1.39, rollingHystScale = 2.20,
        staticCoolingRate = 0.060, slipHeatRate = 16.03, workHeatRate = 8.33, wearRate = 0.00355,
        rollingWearCoef = 92, scalarTreadWearScale = 4.7,
        treadInertia = 0.3171, carcassInertia = 0.5134, thermalReactionRate = 1.615, tempPlateau = 14.7,
        coldWidth = 54.7, hotWidth = 33.7, gripFloor = 0.24, coldWearMult = 2.73,
        hotWearMult = 6.025, grainTempRatio = 0.78, blisterTempRatio = 1.59, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 0.75, camberSensitivity = 1.60,
        bottomOutSensitivity = 1.25, scrubSensitivity = 1.80, skinVelCoolScale = 1.00
    } }
}

local UTILITY_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "highway_utility_utility", mods = {
        adhesion = 0.4, airConductionRate = 0.01275, airCoolingRate = 0.02875, brakeGainRate = 0.6,
        casingCompliance = 0.3, coreCoolRate = 0.0403, coreVelCoolRate = 0.0092, skinCoreConductance = 0.064,

        gripMultiplier = 1.27, longGripMult = 1, latGripMult = 1,
        optimalPressure = 44, optimalTemp = 60, pressureSensitivity = 0.32, rollingRes = 0.84,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 4.2, wearRate = 0.00032,

        scalarTreadWearScale = 0.33,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 2.928, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.3, scrubSensitivity = 1.1
    } },
    { tread = 0.60, profile = "highway_utility_utility", mods = {
        adhesion = 0.38, airConductionRate = 0.012375, airCoolingRate = 0.03, brakeGainRate = 0.5625,
        casingCompliance = 0.325, coreCoolRate = 0.04205, coreVelCoolRate = 0.0092, skinCoreConductance = 0.060,

        gripMultiplier = 1.23, longGripMult = 1, latGripMult = 1,
        optimalPressure = 40, optimalTemp = 58, pressureSensitivity = 0.30, rollingRes = 0.96,
        staticCoolingRate = 0.08, slipHeatRate = 7.612, workHeatRate = 4.05, wearRate = 0.00027,

        scalarTreadWearScale = 0.36,
        treadInertia = 0.609, carcassInertia = 0.986, thermalReactionRate = 1.225, tempPlateau = 17,
        coldWidth = 58, hotWidth = 52.5, gripFloor = 0.26, coldWearMult = 1.755,
        hotWearMult = 2.908, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.875,
        wetGripScale = 1.091, dryGripScale = 1, trackConductivityMult = 0.875, camberSensitivity = 0.75,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.05
    } },
    { tread = 0.70, profile = "allterrain_utility_utility", mods = {
        adhesion = 0.36, airConductionRate = 0.012, airCoolingRate = 0.03125, brakeGainRate = 0.525,
        casingCompliance = 0.35, coreCoolRate = 0.0438, coreVelCoolRate = 0.0092, skinCoreConductance = 0.056,

        gripMultiplier = 1.17, longGripMult = 1, latGripMult = 1,
        optimalPressure = 36, optimalTemp = 56, pressureSensitivity = 0.28, rollingRes = 1.08,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 3.9, wearRate = 0.00022,

        scalarTreadWearScale = 0.43,
        treadInertia = 0.63, carcassInertia = 1.02, thermalReactionRate = 1.25, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.888, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1
    } },
    { tread = 0.85, profile = "mudterrain_utility_utility", mods = {
        adhesion = 0.32, airConductionRate = 0.01125, airCoolingRate = 0.03375, brakeGainRate = 0.45,
        casingCompliance = 0.4, coreCoolRate = 0.0473, coreVelCoolRate = 0.0108, skinCoreConductance = 0.048,

        gripMultiplier = 1.21, longGripMult = 1, latGripMult = 1,
        optimalPressure = 28, optimalTemp = 52, pressureSensitivity = 0.22, rollingRes = 1.35,
        staticCoolingRate = 0.08, slipHeatRate = 6.51, workHeatRate = 3.6, wearRate = 0.00018,

        scalarTreadWearScale = 0.50,
        treadInertia = 0.714, carcassInertia = 1.156, thermalReactionRate = 1.2, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.872, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 1, scrubSensitivity = 0.9
    } },
    { tread = 0.95, profile = "logger_utility_utility", mods = {
        adhesion = 0.3, airConductionRate = 0.0105, airCoolingRate = 0.03625, brakeGainRate = 0.375,
        casingCompliance = 0.45, coreCoolRate = 0.0508, coreVelCoolRate = 0.0116, skinCoreConductance = 0.04,

        gripMultiplier = 0.93, longGripMult = 1, latGripMult = 1,
        optimalPressure = 24, optimalTemp = 50, pressureSensitivity = 0.18, rollingRes = 1.55,
        staticCoolingRate = 0.08, slipHeatRate = 6.09, workHeatRate = 3.3, wearRate = 0.00014,

        scalarTreadWearScale = 0.61,
        treadInertia = 0.798, carcassInertia = 1.292, thermalReactionRate = 1.15, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.856, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.9, scrubSensitivity = 0.8
    } }
}

local COMMERCIAL_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "highway_steer_truck", mods = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.03125, brakeGainRate = 0.225,
        casingCompliance = 0.12, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,

        gripMultiplier = 1.10, longGripMult = 1, latGripMult = 1,
        optimalPressure = 105, optimalTemp = 62, pressureSensitivity = 0.1, rollingRes = 0.62, rollingHystScale = 1,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 2.4, wearRate = 0.00006,

        scalarTreadWearScale = 1.0,
        treadInertia = 1.764, carcassInertia = 2.856, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.824, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.8, scrubSensitivity = 1.2
    } },
    { tread = 0.60, profile = "highway_trailer_truck", mods = {
        adhesion = 0.3, airConductionRate = 0.00825, airCoolingRate = 0.0325, brakeGainRate = 0.15,
        casingCompliance = 0.1, coreCoolRate = 0.056, coreVelCoolRate = 0.0128, skinCoreConductance = 0.036,

        gripMultiplier = 1.04, longGripMult = 1, latGripMult = 1,

        optimalPressure = 110, optimalTemp = 62, pressureSensitivity = 0.09, rollingRes = 0.58, rollingHystScale = 16,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 2.16, wearRate = 0.00005,

        scalarTreadWearScale = 1.0,
        treadInertia = 2.184, carcassInertia = 3.536, thermalReactionRate = 1.1, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.82, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.9, scrubSensitivity = 1.2
    } },
    { tread = 0.70, profile = "traction_drive_truck", mods = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.0325, brakeGainRate = 0.225,
        casingCompliance = 0.15, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,

        gripMultiplier = 1.06, longGripMult = 1, latGripMult = 1,
        optimalPressure = 95, optimalTemp = 62, pressureSensitivity = 0.13, rollingRes = 0.75, rollingHystScale = 1,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 2.7, wearRate = 0.00008,

        scalarTreadWearScale = 0.90,
        treadInertia = 1.89, carcassInertia = 3.06, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.832, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.7, scrubSensitivity = 1.2
    } },
    { tread = 0.80, profile = "traction_drive_truck", mods = {
        adhesion = 0.325, airConductionRate = 0.009, airCoolingRate = 0.035, brakeGainRate = 0.225,
        casingCompliance = 0.165, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.038,

        gripMultiplier = 1.03, longGripMult = 1, latGripMult = 1,

        optimalPressure = 87.5, optimalTemp = 59, pressureSensitivity = 0.11, rollingRes = 0.90, rollingHystScale = 1,
        staticCoolingRate = 0.08, slipHeatRate = 7.087, workHeatRate = 3.0, wearRate = 0.00010,

        scalarTreadWearScale = 0.69,
        treadInertia = 1.953, carcassInertia = 3.162, thermalReactionRate = 1.225, tempPlateau = 17,
        coldWidth = 58, hotWidth = 52.5, gripFloor = 0.26, coldWearMult = 1.695,
        hotWearMult = 2.840, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.875,
        wetGripScale = 1.085, dryGripScale = 0.97, trackConductivityMult = 0.875, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.55, scrubSensitivity = 1.15
    } },
    { tread = 0.90, profile = "heavy_offroad_truck", mods = {
        adhesion = 0.3, airConductionRate = 0.009, airCoolingRate = 0.0375, brakeGainRate = 0.225,
        casingCompliance = 0.18, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.036,

        gripMultiplier = 0.97, longGripMult = 1, latGripMult = 1,

        optimalPressure = 80, optimalTemp = 56, pressureSensitivity = 0.09, rollingRes = 1.05, rollingHystScale = 1,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.00012,

        scalarTreadWearScale = 0.63,
        treadInertia = 2.016, carcassInertia = 3.264, thermalReactionRate = 1.25, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.848, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1.1
    } }
}

local ATV_UTV_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "hardpack_utv_utv", mods = {
        adhesion = 0.35, airConductionRate = 0.012, airCoolingRate = 0.0375, brakeGainRate = 0.45,
        casingCompliance = 0.8, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.04,

        gripMultiplier = 1.25, longGripMult = 1, latGripMult = 1,
        optimalPressure = 14, optimalTemp = 55, pressureSensitivity = 0.25, rollingRes = 1.1,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 3.6, wearRate = 0.0025,

        scalarTreadWearScale = 0.21,
        treadInertia = 0.336, carcassInertia = 0.544, thermalReactionRate = 1.65, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 3.8, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    } },
    { tread = 0.60, profile = "hardpack_utv_utv", mods = {
        adhesion = 0.325, airConductionRate = 0.011625, airCoolingRate = 0.03875, brakeGainRate = 0.4125,
        casingCompliance = 0.825, coreCoolRate = 0.04725, coreVelCoolRate = 0.0108, skinCoreConductance = 0.038,

        gripMultiplier = 1.21, longGripMult = 1, latGripMult = 1,
        optimalPressure = 12, optimalTemp = 52.5, pressureSensitivity = 0.225, rollingRes = 1.175,
        staticCoolingRate = 0.08, slipHeatRate = 6.562, workHeatRate = 3.45, wearRate = 0.00215,

        scalarTreadWearScale = 0.21,
        treadInertia = 0.357, carcassInertia = 0.578, thermalReactionRate = 1.575, tempPlateau = 17,
        coldWidth = 58, hotWidth = 52.5, gripFloor = 0.26, coldWearMult = 1.695,
        hotWearMult = 3.66, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.085, dryGripScale = 1, trackConductivityMult = 0.875, camberSensitivity = 0.45,
        bottomOutSensitivity = 0.55, scrubSensitivity = 0.8
    } },
    { tread = 0.70, profile = "allterrain_utv_utv", mods = {
        adhesion = 0.3, airConductionRate = 0.01125, airCoolingRate = 0.04, brakeGainRate = 0.375,
        casingCompliance = 0.85, coreCoolRate = 0.049, coreVelCoolRate = 0.0112, skinCoreConductance = 0.036,

        gripMultiplier = 1.11, longGripMult = 1, latGripMult = 1,
        optimalPressure = 10, optimalTemp = 50, pressureSensitivity = 0.2, rollingRes = 1.25,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.0018,

        scalarTreadWearScale = 0.23,
        treadInertia = 0.378, carcassInertia = 0.612, thermalReactionRate = 1.5, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 3.52, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.8
    } },
    { tread = 0.85, profile = "mud_utv_utv", mods = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.9, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,

        gripMultiplier = 0.95, longGripMult = 1, latGripMult = 1,
        optimalPressure = 7, optimalTemp = 48, pressureSensitivity = 0.15, rollingRes = 1.4,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3, wearRate = 0.0014,

        scalarTreadWearScale = 0.28,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.35, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 3.36, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    } }
}

local VINTAGE_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "vintage_biasply_vintage", mods = {
        adhesion = 0.28, airConductionRate = 0.0135, airCoolingRate = 0.02375, brakeGainRate = 0.6,
        casingCompliance = 0.65, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,

        gripMultiplier = 1.07, longGripMult = 1, latGripMult = 1,
        optimalPressure = 24, optimalTemp = 56, pressureSensitivity = 0.45, rollingRes = 0.94,
        staticCoolingRate = 0.08, slipHeatRate = 6.5, workHeatRate = 5.7, wearRate = 0.0004,

        scalarTreadWearScale = 0.37,
        treadInertia = 0.50, carcassInertia = 0.82, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1.4
    } },
    { tread = 0.575, profile = "vintage_biasply_vintage", mods = {
        adhesion = 0.315, airConductionRate = 0.013875, airCoolingRate = 0.025, brakeGainRate = 0.675,
        casingCompliance = 0.60, coreCoolRate = 0.03765, coreVelCoolRate = 0.0086, skinCoreConductance = 0.076,

        gripMultiplier = 1.11, longGripMult = 1, latGripMult = 1,
        optimalPressure = 27, optimalTemp = 58, pressureSensitivity = 0.435, rollingRes = 0.91,
        staticCoolingRate = 0.08, slipHeatRate = 6.9, workHeatRate = 5.45, wearRate = 0.000475,

        scalarTreadWearScale = 0.28,
        treadInertia = 0.49, carcassInertia = 0.80, thermalReactionRate = 1.22, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.99, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.6,
        wetGripScale = 1.0, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.6,
        bottomOutSensitivity = 0.85, scrubSensitivity = 1.3
    } },
    { tread = 0.65, profile = "classic_radial_vintage", mods = {
        adhesion = 0.35, airConductionRate = 0.01425, airCoolingRate = 0.02625, brakeGainRate = 0.75,
        casingCompliance = 0.55, coreCoolRate = 0.0368, coreVelCoolRate = 0.0084, skinCoreConductance = 0.072,

        gripMultiplier = 1.23, longGripMult = 1, latGripMult = 1,
        optimalPressure = 30, optimalTemp = 60, pressureSensitivity = 0.42, rollingRes = 0.88,
        staticCoolingRate = 0.08, slipHeatRate = 7.4, workHeatRate = 5.05, wearRate = 0.00055,

        scalarTreadWearScale = 0.22,
        treadInertia = 0.48, carcassInertia = 0.78, thermalReactionRate = 1.28, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 3.02, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.7,
        wetGripScale = 1.025, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.7,
        bottomOutSensitivity = 0.9, scrubSensitivity = 1.2
    } }
}

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

    local streetLike = {
        crawler = true, paddle = true, winter = true,
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
