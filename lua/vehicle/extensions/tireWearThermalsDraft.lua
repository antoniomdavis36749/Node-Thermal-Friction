-- lua/vehicle/extensions/tireWearThermalsDraft.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max = math.min, math.max

function M.install(F, deps)
    local draft = deps.draft
    local getVehicleAirspeedRef = deps.getVehicleAirspeedRef
    local getFreestreamAirspeed = deps.getFreestreamAirspeed

    -- Recompute pack-air / convection vs native 0.39 interAero.
    F.refreshDraftCompat = function()
        if draft.hasNativeInterAero then
            -- Drag/cooling freestream already handled by setWindAero → airflowspeed.
            draft.convectionMult = 1.0
            local fromInfer = draft.inferredWake * draft.nativeAirTempMax
            local fromCompanion = draft.airTempDelta
            draft.airTempEffective = max(0, min(draft.airTempCap, max(fromInfer, fromCompanion)))
        else
            draft.convectionMult = 1.0 - draft.coolingWake * draft.coolingReduction
            draft.airTempEffective = draft.airTempDelta
        end
    end

    -- Infer wake shelter from native aero: airflowspeed drops vs vehicle airspeed in a tow.
    F.updateInferredNativeWake = function(dt)
        if not draft.hasNativeInterAero then
            draft.inferredWake = 0
            return
        end
        local spd = getVehicleAirspeedRef()
        local air = getFreestreamAirspeed()
        local target = 0
        if spd >= draft.inferMinSpeed then
            local deadband = max(draft.inferDeadbandMin, spd * draft.inferDeadband)
            local deficit = max(0, (spd - air) - deadband)
            local ref = max(1.0, spd * draft.inferRefFrac)
            target = max(0, min(1, deficit / ref))
        end
        local k = min(1.0, (dt or 0.05) * draft.inferSmooth)
        draft.inferredWake = draft.inferredWake + (target - draft.inferredWake) * k
        if draft.inferredWake < 0.008 and target < 0.008 then
            draft.inferredWake = 0
        end
    end

    -- Optional legacy companion (LuuksDraftingMod). On 0.39+, convection cut is ignored;
    -- airTempDelta can still raise pack ambient if stronger than inference.
    F.setDraftWake = function(wake, side, push, airTempDelta)
        draft.wake = max(0, min(1, tonumber(wake) or 0))
        draft.side = max(0, min(1, tonumber(side) or 0))
        draft.push = max(0, min(1, tonumber(push) or 0))
        draft.airTempDelta = max(0, min(draft.airTempCap, tonumber(airTempDelta) or 0))
        draft.coolingWake = max(draft.wake, draft.side * 0.7, draft.push * 0.25)
        draft.lastRxClock = os.clock()
        F.refreshDraftCompat()
    end

    F.decayDraftWake = function(dt)
        F.updateInferredNativeWake(dt)

        if draft.coolingWake <= 0 and draft.airTempDelta <= 0 then
            if not draft.hasNativeInterAero then
                draft.convectionMult = 1.0
                draft.airTempEffective = 0
            else
                F.refreshDraftCompat()
            end
            return
        end
        if (os.clock() - draft.lastRxClock) < draft.staleSec then
            F.refreshDraftCompat()
            return
        end
        local k = min(1.0, (dt or 0.05) * 3.0)
        draft.wake = draft.wake + (0 - draft.wake) * k
        draft.side = draft.side + (0 - draft.side) * k
        draft.push = draft.push + (0 - draft.push) * k
        draft.airTempDelta = draft.airTempDelta + (0 - draft.airTempDelta) * k
        draft.coolingWake = max(draft.wake, draft.side * 0.7, draft.push * 0.25)
        if draft.coolingWake < 0.001 then
            draft.wake, draft.side, draft.push, draft.coolingWake, draft.airTempDelta = 0, 0, 0, 0, 0
        end
        F.refreshDraftCompat()
    end
end

return M

