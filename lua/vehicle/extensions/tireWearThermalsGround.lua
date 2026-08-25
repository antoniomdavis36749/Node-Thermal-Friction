-- lua/vehicle/extensions/tireWearThermalsGround.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max = math.min, math.max

function M.install(F, deps)
    local cache = deps.cache
    local topo = deps.topo
    local MISSING = deps.missing

    F.GetGroundModelData = function(id)
        if not id then return "DOESNT EXIST", MISSING end
        if cache.lut[id] then return cache.lut[id].name, cache.lut[id] end

        local materials = (particles and type(particles.getMaterialsParticlesTable) == "function") and particles.getMaterialsParticlesTable() or {}
        local matData = materials[id] or materials[id + 1] or {}
        local name = matData.name or "DOESNT EXIST"
    
        local rawData = cache.models[name] or { staticFrictionCoefficient = 1, slidingFrictionCoefficient = 1 }
        local data = {
            name = name,
            nameLower = string.lower(name),
            staticFrictionCoefficient = rawData.staticFrictionCoefficient or 1,
            slidingFrictionCoefficient = rawData.slidingFrictionCoefficient or 1,
            strength = rawData.strength,
            rough = rawData.roughnessCoefficient or rawData.rough,
            fluidDensity = rawData.fluidDensity,
            stribeckVelocity = rawData.stribeckVelocity or rawData.stribeckVel or 1,
            defaultDepth = rawData.defaultDepth or 0
        }
    
        cache.lut[id] = data
        return name, data
    end

    -- Path A1/A2: blend primary+secondary GM soft/friction fields into CalcTyreWear scratch.
    -- Must take scratch as arg — module `local ctw` is declared later, so a bare `ctw` here
    -- would resolve as a nil global and disable the vehicle (BeamNG Lua ~200-local split).
    -- Asphalt dry ≈ identity (strength≈1, defaultDepth≈0, fluid≈0, stribeck≈1). Spike mats excluded upstream.
    F.blendGroundThermal = function(w, groundModel, isAirborne, scratch)
        if not scratch then return end
        local gm = groundModel or MISSING
        local rough = tonumber(gm.rough) or 0
        local strength = tonumber(gm.strength)
        if not strength or strength <= 0 then strength = 1.0 end
        local defDepth = tonumber(gm.defaultDepth) or 0
        local fluid = tonumber(gm.fluidDensity) or 0
        local stribeck = tonumber(gm.stribeckVelocity) or 1
        local st = gm.staticFrictionCoefficient or 1
        local sl = gm.slidingFrictionCoefficient or st
        local rough1 = rough
        local dualB = 0
        local gm2 = w and w.groundModel2
        if gm2 and not isAirborne then
            dualB = topo.dualContactBlend or 0.32
            local b1, b2 = 1.0 - dualB, dualB
            rough = rough * b1 + (tonumber(gm2.rough) or 0) * b2
            st = st * b1 + (gm2.staticFrictionCoefficient or 1) * b2
            sl = sl * b1 + (gm2.slidingFrictionCoefficient or gm2.staticFrictionCoefficient or 1) * b2
            local s2 = tonumber(gm2.strength)
            if not s2 or s2 <= 0 then s2 = 1.0 end
            strength = strength * b1 + s2 * b2
            defDepth = defDepth * b1 + (tonumber(gm2.defaultDepth) or 0) * b2
            fluid = fluid * b1 + (tonumber(gm2.fluidDensity) or 0) * b2
            stribeck = stribeck * b1 + (tonumber(gm2.stribeckVelocity) or 1) * b2
        end
        scratch.gmRough = rough
        scratch.gmStatic = st
        scratch.gmSliding = sl
        scratch.gmStrength = strength
        scratch.gmDefDepth = defDepth
        scratch.gmFluid = fluid
        scratch.gmStribeck = stribeck
        scratch.dualContactBlend = dualB
        scratch.dualRoughDelta = max(0, rough - rough1)
        -- Soft-sink / conduction extras from unused GM fields (A1)
        local sRef = max(0.2, topo.softSinkStrengthRef or 1.0)
        local softExtra = max(0, defDepth) * (topo.softSinkDefaultDepthCoef or 2.2)
            + max(0, 1.0 - strength / sRef) * (topo.softSinkStrengthCoef or 0.40)
            + max(0, fluid) * (topo.softSinkFluidCoef or 0.0007)
            + max(0, 1.0 - min(1.0, stribeck / max(0.1, topo.softSinkStribeckRef or 1.0))) * (topo.softSinkStribeckCoef or 0.035)
        scratch.softGmExtra = softExtra
        scratch.condGmExtra = max(0, defDepth) * (topo.gmConductionDefaultDepthCoef or 2.5)
            + max(0, 1.0 - strength / sRef) * (topo.gmConductionStrengthCoef or 0.30)
            + max(0, fluid) * (topo.gmConductionFluidCoef or 0.0005)
    end

    F.setGroundModels = function(data)
        cache.models = data or {}
        cache.lut = {} -- Invalidate LUT cache to force evaluation under the new environment
    end
end

return M

