-- lua/vehicle/extensions/tireWearThermalsAero.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
-- Native aero sample for Pitwall/CSV (display path; heat uses wd.downForce at scale 1.0).
local M = {}

local min, max, abs = math.min, math.max, math.abs
local vec3 = _G.vec3
local axleKeyCache = {}
local axleVec = {}

local function fillAxle(slot, x, y, z)
    local ctor = vec3 or _G.vec3
    if not ctor then return nil end
    local v = axleVec[slot]
    if not v then
        v = ctor(x, y, z)
        axleVec[slot] = v
        if axleVec.setter == nil then
            axleVec.setter = type(v.set) == "function"
        end
        return v
    end
    if axleVec.setter then
        v:set(x, y, z)
    else
        v.x, v.y, v.z = x, y, z
    end
    return v
end

M.wheelAxleKey = function(name)
    if name == nil or name == "" then return nil end
    local cached = axleKeyCache[name]
    if cached ~= nil then
        if cached == "" then return nil end
        return cached
    end
    local n = string.lower(tostring(name))
    local k
    if string.find(n, "rr", 1, true) or string.find(n, "rl", 1, true) then k = "r"
    elseif string.find(n, "fr", 1, true) or string.find(n, "fl", 1, true) then k = "f"
    elseif string.match(n, "^r") then k = "r"
    elseif string.match(n, "^f") then k = "f"
    end
    axleKeyCache[name] = k or ""
    return k
end

M.reset = function(state)
    state.ok = false
    state.liftN, state.dragN, state.sideN = 0, 0, 0
    state.frontN, state.rearN = 0, 0
    state.frontPct, state.rearPct, state.copPct = 0, 0, 0
    state.fracPct, state.totalLoadN = 0, 0
    state.nFront, state.nRear = 0, 0
end

-- Stock aeroDebug.lua: calcTotalAeroForces + CoP torque → axle downforce. Display/CSV only.
-- One pcall fence: missing 0.35 APIs or userdata :dot/:cross throw skip this frame.
local function sampleInner(state, ctx)
    local obj = ctx.obj
    local wheels = ctx.wheels
    local wheelCache = ctx.wheelCache
    if not obj or not wheels or not wheels.wheelRotators then return end
    local force = obj:calcTotalAeroForces()
    if not force then return end
    local fwd = obj:getDirectionVector()
    local up = obj:getDirectionVectorUp()
    if not fwd or not up then return end
    local backward = -fwd
    local leftVec = backward:cross(up)
    state.sideN = force:dot(leftVec)
    state.dragN = force:dot(backward)
    state.liftN = -(force:dot(up))
    state.ok = true

    local totalLoad, nFront, nRear = 0, 0, 0
    local fx, fy, fz, rx, ry, rz = 0, 0, 0, 0, 0, 0
    local origin = obj:getPosition()

    for i, wd in pairs(wheels.wheelRotators) do
        local w = wheelCache[i]
        local load = (w and w.loadRaw) or (wd.downForce or 0)
        totalLoad = totalLoad + load
        local axle = M.wheelAxleKey(wd.name)
        if axle == "f" then
            nFront = nFront + 1
        elseif axle == "r" then
            nRear = nRear + 1
        end
        if origin and wd.node1 then
            local p1 = obj:getNodePosition(wd.node1)
            if p1 then
                local mid = p1
                if wd.node2 then
                    local p2 = obj:getNodePosition(wd.node2)
                    if p2 then mid = (p1 + p2) * 0.5 end
                end
                mid = mid + origin
                if axle == "f" then
                    fx, fy, fz = fx + mid.x, fy + mid.y, fz + mid.z
                elseif axle == "r" then
                    rx, ry, rz = rx + mid.x, ry + mid.y, rz + mid.z
                end
            end
        end
    end
    state.totalLoadN = totalLoad
    state.nFront, state.nRear = nFront, nRear
    if totalLoad > 1 then
        state.fracPct = state.liftN / totalLoad * 100
    end

    if nFront < 1 or nRear < 1 or not origin then return end
    local cop = obj:calcCenterOfPressureRel()
    if not cop then return end
    local copVec = cop + origin
    local torque = obj:calcTotalAeroTorque(cop)
    if not torque then return end

    local frontAxle = fillAxle(1, fx / nFront, fy / nFront, fz / nFront)
    local rearAxle = fillAxle(2, rx / nRear, ry / nRear, rz / nRear)
    if not frontAxle or not rearAxle then return end
    local wheelbase = (frontAxle - rearAxle):length()
    if wheelbase < 0.5 then return end
    local frontAxleToCOP = copVec - frontAxle
    local rearAxleToCOP = copVec - rearAxle
    state.rearN = -(frontAxleToCOP:cross(force) - torque):dot(leftVec) / wheelbase
    state.frontN = (rearAxleToCOP:cross(force) - torque):dot(leftVec) / wheelbase
    local den = abs(state.frontN) + abs(state.rearN)
    if den > 1 then
        state.frontPct = state.frontN / den * 100
        state.rearPct = state.rearN / den * 100
    end
    local wbVec = rearAxle - frontAxle
    state.copPct = max(-20, min(120, frontAxleToCOP:dot(wbVec) / (wheelbase * wheelbase) * 100))
end

M.sample = function(state, ctx)
    M.reset(state)
    if not pcall(sampleInner, state, ctx) then
        M.reset(state)
    end
end

M.wheelShare = function(state, name, loadN)
    local axle = M.wheelAxleKey(name)
    if axle == "f" and state.nFront > 0 and (abs(state.frontN) + abs(state.rearN)) > 1 then
        return state.frontN / state.nFront
    end
    if axle == "r" and state.nRear > 0 and (abs(state.frontN) + abs(state.rearN)) > 1 then
        return state.rearN / state.nRear
    end
    if state.totalLoadN > 1 and loadN then
        return state.liftN * (loadN / state.totalLoadN)
    end
    return 0
end

-- Phase 3: load_kg multiplier for heat. 1.0 = no discount. Writes data.aeroHeatThermalFrac.
M.heatThermalFrac = function(state, data, name, loadRaw, airspeed, topo)
    local frac = 1.0
    local scale = topo.aeroHeatScale
    if scale < 0.999 and loadRaw > 50 and state.ok and airspeed >= (topo.aeroHeatSpeedStart or 15) then
        local aeroN = M.wheelShare(state, name, loadRaw)
        if aeroN > 0 then
            local aeroFrac = aeroN / loadRaw
            local cap = topo.aeroHeatMaxFrac or 0.48
            if aeroFrac > cap then aeroFrac = cap end
            frac = 1.0 - aeroFrac * (1.0 - scale)
        end
    end
    if data then data.aeroHeatThermalFrac = frac end
    return frac
end

return M
