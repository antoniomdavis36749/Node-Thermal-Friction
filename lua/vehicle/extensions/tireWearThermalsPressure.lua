-- lua/vehicle/extensions/tireWearThermalsPressure.lua
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local min, max, abs = math.min, math.max, math.abs

function M.install(F, deps)
    local objPcall = deps.objPcall
    local isRemoteMpVehicle = deps.isRemoteMpVehicle
    local getV = deps.getV or function() return deps.v end

    local function nativePressureGroup(wd)
        local v = getV()
        if not wd or not wd.pressureGroup or not v or not v.data or not v.data.pressureGroups then return nil end
        return v.data.pressureGroups[wd.pressureGroup]
    end

    local function getGroupPressurePa(wd)
        local pg = nativePressureGroup(wd)
        if not pg then return nil end
        local ok, pa = objPcall("getGroupPressure", pg)
        if ok and type(pa) == "number" then return pa end
    end

    local function setGroupPressurePa(wd, pa)
        local pg = nativePressureGroup(wd)
        if not pg then return end
        objPcall("setGroupPressure", pg, pa)
    end

    -- Progressive pressure leak via BeamNG native pressure-group API.
    -- Used for ReSpin-owned thermal/wear leaks ONLY. Spike-strip / wd.isPunctured
    -- leaks are owned by stock wheels.lua — never call this while isPunctured.
    F.applyPressureLeakPa = function(wd, leakPaPerSec, dt)
        if isRemoteMpVehicle() then return nil end
        if not wd or leakPaPerSec <= 0 then return nil end
        if wd.isPunctured then return nil end
        local current = getGroupPressurePa(wd)
        if not current then return nil end
        local minPressure = 105000
        local newP = max(minPressure, current - leakPaPerSec * dt)
        setGroupPressurePa(wd, newP)
        return newP
    end

    -- Gauge PSI from native pressure group (absolute Pa → PSI). nil if unavailable.
    F.getNativeGroupPressurePSI = function(wd)
        local absPa = getGroupPressurePa(wd)
        if not absPa then return nil end
        return max(0.1, (absPa - 101325) / 6894.757)
    end

    -- Tuning-menu cold fill ($tirepressure_F / _R, else $tirepressure). nil if unset.
    F.getTuneColdFillPSI = function(isFront)
        local v = getV()
        if not (v and v.data and type(v.data.variables) == "table") then return nil end
        local keys = isFront and { "$tirepressure_F", "$tirepressure" } or { "$tirepressure_R", "$tirepressure" }
        for _, key in ipairs(keys) do
            local var = v.data.variables[key]
            if type(var) == "table" and var.val ~= nil then
                local n = tonumber(var.val)
                if n and n > 1.0 then return n end
            elseif type(var) == "number" and var > 1.0 then
                return var
            end
        end
        return nil
    end

    -- One-shot native restore (spawn / leftover write-back). Gauge PSI → absolute Pa.
    F.setNativeGroupPressurePSI = function(wd, gaugePSI)
        if isRemoteMpVehicle() then return nil end
        if not wd or type(gaugePSI) ~= "number" then return nil end
        if not nativePressureGroup(wd) then return nil end
        setGroupPressurePa(wd, max(105000, (gaugePSI + 14.696) * 6894.757))
        return gaugePSI
    end

    -- True when TPMS / tirePressureControl / inflate electrics look active (don't fight user/AI fill).
    F.isTirePressureInflateActive = function()
        local ev = electrics and electrics.values
        if not ev then return false end
        if ev.tireInflating or ev.tirePressureInflating then return true end
        local tpc = ev.tirePressureControl
        if tpc == true then return true end
        if type(tpc) == "number" and abs(tpc) > 0.01 then return true end
        if type(ev.tirePressureControlActive) == "boolean" and ev.tirePressureControlActive then return true end
        if type(ev.inflateRate) == "number" and abs(ev.inflateRate) > 0.01 then return true end
        return false
    end

    -- Rate-limited Gay-Lussac hot absolute Pa → native pressure group (soft-body stiffness).
    -- Deadband skips tiny deltas; min floor matches BeamNG puncture path. nil if unavailable / no-op.
    F.applyHotPressureWriteback = function(wd, targetAbsPa, dt, maxPsiPerSec, deadbandPsi)
        if isRemoteMpVehicle() then return nil end
        if not wd or type(targetAbsPa) ~= "number" or not dt or dt <= 0 then return nil end
        local current = getGroupPressurePa(wd)
        if not current then return nil end
        local minPressure = 105000
        local target = max(minPressure, targetAbsPa)
        local deltaPa = target - current
        local psiPerPa = 1.0 / 6894.757
        if abs(deltaPa) * psiPerPa < max(0.01, deadbandPsi or 0.15) then
            return current
        end
        local maxStepPa = max(0.0, maxPsiPerSec or 0.35) * 6894.757 * dt
        if maxStepPa <= 0 then return current end
        local step = max(-maxStepPa, min(maxStepPa, deltaPa))
        local newP = max(minPressure, current + step)
        if abs(newP - current) < 1.0 then return current end
        setGroupPressurePa(wd, newP)
        return newP
    end
end

return M

