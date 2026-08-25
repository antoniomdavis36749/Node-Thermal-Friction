-- lua/vehicle/extensions/tireWearThermalsTemp.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max = math.min, math.max

function M.install(F, deps)
    local getEnvTemp = deps.getEnvTemp or function() return deps.ENV_TEMP end
    local TEMP_NODE_COUNT = deps.TEMP_NODE_COUNT
    local WORKING_TEMP = deps.WORKING_TEMP
    local DEFAULT_MODS = deps.DEFAULT_MODS
    local THERMAL_TOPOLOGY = deps.THERMAL_TOPOLOGY
    local lerp = deps.lerp

    F.CalcBiasWeights = function(loadBias, pressureRatio)
        -- combinedBias / pressureRatio can be unset before first prepareWheelFrame
        loadBias = loadBias or 0
        pressureRatio = pressureRatio or 1.0
        local dampedBias = loadBias * 0.40
        local weightLeft = max(0.15, -0.75 * dampedBias + 1)
        local weightRight = max(0.15, 0.75 * dampedBias + 1)
    
        local loadBiasSq = dampedBias * dampedBias
        local weightCenter = (loadBiasSq < 1e-5) and 1 or max(0, -1 / (1 + 5 / loadBiasSq) + 1)
    
        -- Under-inflation expands footprint to outer shoulders (concave structural collapsing)
        -- Over-inflation balloons tire centerline (crown bulging)
        if pressureRatio < 1.0 then
            local underInfFactor = (1.0 - pressureRatio) * 0.40
            weightLeft = weightLeft * (1.0 + underInfFactor)
            weightRight = weightRight * (1.0 + underInfFactor)
            weightCenter = weightCenter * max(0.3, 1.0 - underInfFactor * 1.5)
        elseif pressureRatio > 1.0 then
            local overInfFactor = min(1.0, pressureRatio - 1.0) * 0.30
            weightLeft = weightLeft * max(0.4, 1.0 - overInfFactor * 1.2)
            weightRight = weightRight * max(0.4, 1.0 - overInfFactor * 1.2)
            weightCenter = weightCenter * (1.0 + overInfFactor * 1.5)
        end
    
        local weightSum = weightLeft + weightCenter + weightRight
        if weightSum <= 0 then weightSum = 1 end
        return weightLeft / weightSum, weightCenter / weightSum, weightRight / weightSum
    end
    -- Migrate legacy 5-node tables (skin×3, core, air) → 8-node in place
    F.ensureTempNodes = function(temps, envTemp)
        envTemp = envTemp or getEnvTemp()
        if type(temps) ~= "table" then
            return { envTemp, envTemp, envTemp, envTemp, envTemp, envTemp, envTemp, envTemp }
        end
        if temps[8] ~= nil then
            for i = 1, TEMP_NODE_COUNT do
                temps[i] = temps[i] or envTemp
            end
            return temps
        end
        -- Legacy: [1..3]=skin, [4]=single carcass, [5]=air
        local core = temps[4] or envTemp
        local air = temps[5] or envTemp
        temps[1] = temps[1] or envTemp
        temps[2] = temps[2] or envTemp
        temps[3] = temps[3] or envTemp
        temps[4], temps[5], temps[6] = core, core, core
        temps[7] = core
        temps[8] = air
        return temps
    end

    F.TempRingsToAvgTemp = function(temps, loadBias, pressureRatio, localEnvTemp)
        local fallbackEnv = localEnvTemp or getEnvTemp()
        if not temps then return fallbackEnv end
        local wLeft, wCenter, wRight = F.CalcBiasWeights(loadBias, pressureRatio)
        return (temps[1] or fallbackEnv) * wLeft + (temps[2] or fallbackEnv) * wCenter + (temps[3] or fallbackEnv) * wRight
    end

    F.TempCarcassToAvgTemp = function(temps, loadBias, pressureRatio, localEnvTemp)
        local fallbackEnv = localEnvTemp or getEnvTemp()
        if not temps then return fallbackEnv end
        local wLeft, wCenter, wRight = F.CalcBiasWeights(loadBias, pressureRatio)
        return (temps[4] or fallbackEnv) * wLeft + (temps[5] or fallbackEnv) * wCenter + (temps[6] or fallbackEnv) * wRight
    end

    -- Skin-led grip thermometer with carcass lag; cold → more carcass weight (P2)
    F.EffectiveTyreTemp = function(temps, loadBias, pressureRatio, localEnvTemp, mods)
        local skin = F.TempRingsToAvgTemp(temps, loadBias, pressureRatio, localEnvTemp)
        local carcass = F.TempCarcassToAvgTemp(temps, loadBias, pressureRatio, localEnvTemp)
        local topo = THERMAL_TOPOLOGY
        local blend = topo.gripBlendWarm
        if mods then
            local tOpt = mods.optimalTemp or WORKING_TEMP
            local coldW = max(15.0, mods.coldWidth or DEFAULT_MODS.coldWidth)
            -- 0 at/above opt, 1 when skin is ~0.65·coldWidth below opt
            local coldness = max(0.0, min(1.0, (tOpt - skin) / (coldW * 0.65)))
            coldness = coldness * coldness * (3.0 - 2.0 * coldness) -- smoothstep
            blend = lerp(topo.gripBlendWarm, topo.gripBlendCold, coldness)
        end
        return skin * (1.0 - blend) + carcass * blend
    end

    F.tempDistToWearMult = function(tempDist)
        return -1.8 / (1 + 0.01 * (tempDist * (tempDist or 1))) + 2.8
    end
end

return M

