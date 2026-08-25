-- lua/vehicle/extensions/tireWearThermalsNodeProbe.lua
-- Read-only nodeCollision / slipForce probe — Pitwall energy A/B vs wheel slipEnergy.
local M = {}

local ENABLE_NODE_COLLISION_PROBE = true
local CONTROLLER_NAME = "tireWearThermalsNodeProbe"

function M.install(F, deps)
    local State = require("tireWearThermalsNodeProbeState")
    local getWheels = deps.getWheels or function() return deps.wheels end
    local tyreData = deps.tyreData
    local isRemoteMpVehicle = deps.isRemoteMpVehicle or function() return false end

    local function wheelKey(wheelIndex)
        return tonumber(wheelIndex) or wheelIndex
    end

    local function controllerLoaded()
        return controller
            and controller.getController
            and controller.getController(CONTROLLER_NAME) ~= nil
    end

    F.ensureNodeCollisionProbe = function()
        if not ENABLE_NODE_COLLISION_PROBE or isRemoteMpVehicle() then return false end
        State.setEnabled(true)
        State.rebuildTreadMap(getWheels)
        if controllerLoaded() then return true end
        if not controller or not controller.loadControllerExternal then return false end
        local ok, c = pcall(function()
            return controller.loadControllerExternal("tireWearThermalsNodeProbe", CONTROLLER_NAME, {})
        end)
        return ok and c ~= nil
    end

    F.unloadNodeCollisionProbe = function()
        State.setEnabled(false)
        State.resetAll()
        if controller and controller.unloadControllerExternal then
            pcall(function() controller.unloadControllerExternal(CONTROLLER_NAME) end)
        end
    end

    F.resetNodeCollisionProbe = function()
        State.resetSession()
        State.rebuildTreadMap(getWheels)
    end

    -- Live window + session hold (hold survives park-after-lock until vehicle reset).
    F.stepNodeCollisionProbe = function()
        if not ENABLE_NODE_COLLISION_PROBE or isRemoteMpVehicle() then return end
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators or not tyreData then return end

        -- Init often runs before treadNodes exist; refill until mapN > 0.
        local mapN = State.ensureTreadMap(getWheels)
        for i, data in pairs(tyreData) do
            if data then
                local snap, hold = State.snapshotAndClear(wheelKey(i))
                local wd = wheels.wheelRotators[i]
                local wheelCid = wd and wd.lastTreadContactNode or 0

                data.nodeColOn = 1
                data.nodeColMapN = mapN
                -- Live (this GFX window)
                data.nodeColHits = snap.hits
                data.nodeColSlipHits = snap.slipHits
                data.nodeColSlipF = snap.slipForceMax
                data.nodeColSlipV = snap.slipVelMax
                data.nodeColNormalF = snap.normalForceMax
                data.nodeColDepth = snap.depthMax
                data.nodeColEnergy = snap.energySum
                data.nodeColPeakEnergy = snap.peakEnergy or 0
                -- Session hold (stint max / sum until reset)
                data.nodeColHoldHits = hold.hits
                data.nodeColHoldSlipHits = hold.slipHits
                data.nodeColHoldSlipF = hold.slipForceMax
                data.nodeColHoldSlipV = hold.slipVelMax
                data.nodeColHoldEnergy = hold.energySum
                data.nodeColHoldWin = hold.energyMaxWin
                data.nodeColHoldPeakE = hold.peakEnergy
                data.nodeColPeakCid = (hold.peakCid and hold.peakCid > 0) and hold.peakCid or (snap.peakCid or 0)
                data.nodeColWheelCid = wheelCid or 0
                local peakCid = data.nodeColPeakCid or 0
                local match = peakCid > 0 and wheelCid and peakCid == wheelCid
                data.nodeColMatch = match and 1 or 0
            end
        end
    end

    F.clearNodeCollisionProbePublish = function()
        if not tyreData then return end
        for _, data in pairs(tyreData) do
            if data then
                data.nodeColOn = 0
                data.nodeColMapN = 0
                data.nodeColHits = 0
                data.nodeColSlipHits = 0
                data.nodeColSlipF = 0
                data.nodeColSlipV = 0
                data.nodeColNormalF = 0
                data.nodeColDepth = 0
                data.nodeColEnergy = 0
                data.nodeColPeakEnergy = 0
                data.nodeColHoldHits = 0
                data.nodeColHoldSlipHits = 0
                data.nodeColHoldSlipF = 0
                data.nodeColHoldSlipV = 0
                data.nodeColHoldEnergy = 0
                data.nodeColHoldWin = 0
                data.nodeColHoldPeakE = 0
                data.nodeColPeakCid = 0
                data.nodeColWheelCid = 0
                data.nodeColMatch = 0
            end
        end
    end

    F.isNodeCollisionProbeEnabled = function()
        return ENABLE_NODE_COLLISION_PROBE and true or false
    end
end

return M
