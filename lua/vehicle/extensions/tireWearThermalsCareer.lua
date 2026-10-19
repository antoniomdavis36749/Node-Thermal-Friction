-- lua/vehicle/extensions/tireWearThermalsCareer.lua
-- Career wear file. Freeroam, scenario, and traffic do not read or write it.
-- Heat does not read it. The mode flag comes from the GE extension.
local M = {}

local min, max = math.min, math.max

function M.install(F, deps)
    local tyreData = deps.tyreData
    local getWheels = deps.getWheels or function() return deps.wheels end
    local getV = deps.getV or function() return nil end

    F.careerWearIsPlayer = function()
        return F._careerMode and playerInfo and playerInfo.firstPlayerSeated and true or false
    end

    -- GE calls this. False is the default, so a freeroam spawn never reads the file.
    F.setCareerMode = function(on)
        local nextOn = on and true or false
        F._careerMode = nextOn
        if not nextOn then
            F._careerWearPending = nil
            F._careerWearLoaded = nil
            return
        end
        if not F._fullInit or F._careerWearLoaded then return end
        if F._careerWearPending then
            F.applyCareerWear(F._careerWearPending)
            F._careerWearPending = nil
        elseif not F._careerWearFromReset then
            F.careerWearLoad()
        end
        F._careerWearLoaded = true
    end

    F.careerWearPath = function()
        local veh = getV()
        local model = (veh and veh.data and veh.data.model) or "vehicle"
        local item = veh and veh.config and veh.config.itemId
        local id = item and ("item" .. tostring(item)) or tostring(model)
        id = id:gsub("[^%w_%-]", "_")
        if #id > 80 then id = id:sub(1, 80) end
        return "settings/ntf-player-wear/" .. id .. ".json"
    end

    F.collectCareerWear = function()
        local out = {}
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return { v = 1, wheels = out } end
        for i, wd in pairs(wheels.wheelRotators) do
            local data = tyreData[i]
            if data then
                local key = tostring(wd.name or i) .. "|" .. tostring(data.profile1 or "")
                local ring = {}
                if type(data.nodeWearRing) == "table" then
                    for nid, wear in pairs(data.nodeWearRing) do
                        if type(wear) == "number" and wear > 0 then
                            ring[#ring + 1] = { tonumber(nid) or 0, wear }
                        end
                    end
                end
                local zones = data.zoneCondition or {}
                out[key] = {
                    scalar = data.scalarTreadCondition or 100,
                    peak = data.nodeWearPeak or 0,
                    grain = data.graining or 0,
                    blister = data.blistering or 0,
                    z1 = zones[1] or 100,
                    z2 = zones[2] or 100,
                    z3 = zones[3] or 100,
                    ring = ring,
                }
            end
        end
        return { v = 1, wheels = out }
    end

    F.applyCareerWear = function(saved)
        if not F._careerMode then return end
        if type(saved) ~= "table" or type(saved.wheels) ~= "table" then return end
        local wheels = getWheels()
        if not wheels or not wheels.wheelRotators then return end
        for i, wd in pairs(wheels.wheelRotators) do
            local data = tyreData[i]
            if data then
                local key = tostring(wd.name or i) .. "|" .. tostring(data.profile1 or "")
                local row = saved.wheels[key]
                if row then
                    local scalar = tonumber(row.scalar)
                    if scalar then
                        scalar = max(0, min(100, scalar))
                        data.scalarTreadCondition = scalar
                        data.condition = scalar
                    end
                    local peak = tonumber(row.peak)
                    if peak then data.nodeWearPeak = max(0, min(1, peak)) end
                    data.graining = tonumber(row.grain) or data.graining or 0
                    data.blistering = tonumber(row.blister) or data.blistering or 0
                    data.zoneCondition = {
                        tonumber(row.z1) or 100,
                        tonumber(row.z2) or 100,
                        tonumber(row.z3) or 100,
                    }
                    local ring = {}
                    if type(row.ring) == "table" then
                        for _, pair in ipairs(row.ring) do
                            if type(pair) == "table" and pair[1] ~= nil and type(pair[2]) == "number" then
                                ring[pair[1]] = pair[2]
                            end
                        end
                    end
                    data.nodeWearRing = ring
                end
            end
        end
    end

    F.careerWearSig = function(snap)
        local parts = {}
        local wheelsOut = snap and snap.wheels or {}
        for key, row in pairs(wheelsOut) do
            parts[#parts + 1] = key .. ":" .. tostring(row.scalar) .. ":" .. tostring(row.peak)
        end
        table.sort(parts)
        return table.concat(parts, "|")
    end

    F.careerWearSave = function()
        if not F.careerWearIsPlayer() then return end
        if type(jsonWriteFile) ~= "function" then return end
        local path = F.careerWearPath()
        if FS and FS.directoryCreate then
            pcall(function() FS:directoryCreate("settings/ntf-player-wear", true) end)
        end
        local snap = F.collectCareerWear()
        pcall(jsonWriteFile, path, snap, true)
        F._careerWearSig = F.careerWearSig(snap)
    end

    F.careerWearLoad = function()
        if not F.careerWearIsPlayer() then return end
        if type(jsonReadFile) ~= "function" then return end
        local ok, saved = pcall(jsonReadFile, F.careerWearPath())
        if ok then F.applyCareerWear(saved) end
    end

    F.careerWearTick = function(dt)
        if not F.careerWearIsPlayer() then return end
        F._careerWearClock = (F._careerWearClock or 0) + (dt or 0)
        if F._careerWearClock < 20 then return end
        F._careerWearClock = 0
        local snap = F.collectCareerWear()
        if F.careerWearSig(snap) == F._careerWearSig then return end
        F.careerWearSave()
    end
end

return M
