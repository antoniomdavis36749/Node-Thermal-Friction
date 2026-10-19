-- lua/vehicle/extensions/auto/tireWearThermals.lua
-- The seated car parses the tire module on its first GFX step.
-- A car you are not driving prints lite and does not parse it.
-- tools/FULL_HEAT_AI (an empty file, dev only, not in the release zip) lets
-- those cars parse it too. Each one then writes tools/output/ntf-ai-<id>.csv.
-- There is no traffic on/off switch.
-- The app open flags stay on this table so the UI can call them before load.
-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

local IMPL = "tireWearThermalsImpl"
local loaded = false
local classicWanted = false
local crewWanted = false
local pitwallWanted = false
local pitwallProbeWanted = false
local implSetClassicOpen = nil
local implSetCrewOpen = nil
local implSetPitwallOpen = nil
local implSetPitwallProbe = nil
local careerWanted = false
local implSetCareerMode = nil
local liteNoted = false

local HOOKS = {
    "updateGFX", "update", "onReset", "onSerialize", "onDeserialized",
    "onSettingsChanged", "onExtensionUnloaded",
}

local function applyHudGates()
    if type(implSetClassicOpen) == "function" then
        implSetClassicOpen(classicWanted)
    end
    if type(implSetCrewOpen) == "function" then
        implSetCrewOpen(crewWanted)
    end
    if type(implSetPitwallOpen) == "function" then
        implSetPitwallOpen(pitwallWanted)
    end
    if type(implSetPitwallProbe) == "function" then
        implSetPitwallProbe(pitwallProbeWanted)
    end
end

local function applyCareerMode()
    if type(implSetCareerMode) == "function" then
        implSetCareerMode(careerWanted)
    end
end

local function loadFull()
    if loaded then
        applyHudGates()
        return
    end
    local t0 = (os and os.clock and os.clock()) or 0
    local ok, implOrErr = pcall(require, IMPL)
    if not ok then
        print("tireWearThermals load failed: " .. tostring(implOrErr))
        return
    end
    local impl = implOrErr
    loaded = true
    local init = impl.onInit
    implSetClassicOpen = impl.setClassicOpen
    implSetCrewOpen = impl.setCrewOpen
    implSetPitwallOpen = impl.setPitwallOpen
    implSetPitwallProbe = impl.setPitwallProbe
    implSetCareerMode = impl.setCareerMode
    applyCareerMode()
    for k, v in pairs(impl) do
        M[k] = v
    end
    M.loadFull = loadFull
    M.skipTraffic = M.skipTraffic
    M.setClassicOpen = function(open)
        classicWanted = open and true or false
        applyHudGates()
    end
    M.setCrewOpen = function(open)
        crewWanted = open and true or false
        applyHudGates()
    end
    M.setPitwallOpen = function(open)
        pitwallWanted = open and true or false
        if not pitwallWanted then pitwallProbeWanted = false end
        applyHudGates()
    end
    M.setPitwallProbe = function(open)
        pitwallProbeWanted = open and true or false
        applyHudGates()
    end
    M.setCareerMode = function(on)
        careerWanted = on and true or false
        applyCareerMode()
    end
    if extensions and extensions.hookUpdate then
        for i = 1, #HOOKS do
            extensions.hookUpdate(HOOKS[i])
        end
    end
    if init then init() end
    applyHudGates()
    local t1 = (os and os.clock and os.clock()) or t0
    print(string.format("tireWearThermals load %.2f ms", (t1 - t0) * 1000))
end

local devAiCache = nil

local function devAiHeat()
    if devAiCache ~= nil then return devAiCache end
    local f = io.open("mods/unpacked/Node-Thermal-Friction-work/tools/FULL_HEAT_AI", "r")
    if f then
        f:close()
        devAiCache = true
    else
        devAiCache = false
    end
    return devAiCache
end

local function gateUpdateGFX(dt)
    -- Unseated cars never parse the tire module unless the dev file is present.
    if not (playerInfo and playerInfo.firstPlayerSeated) and not devAiHeat() then
        if not liteNoted then
            liteNoted = true
            print("tireWearThermals lite")
        end
        return
    end
    loadFull()
    local step = M.updateGFX
    if type(step) == "function" and step ~= gateUpdateGFX then
        step(dt)
    end
end

M.loadFull = loadFull

M.skipTraffic = function()
    if loaded then return end
    print("tireWearThermals traffic skip")
end

M.setClassicOpen = function(open)
    classicWanted = open and true or false
    if loaded then applyHudGates() end
end

M.setCrewOpen = function(open)
    crewWanted = open and true or false
    if loaded then applyHudGates() end
end

M.setPitwallOpen = function(open)
    pitwallWanted = open and true or false
    if not pitwallWanted then pitwallProbeWanted = false end
    if loaded then applyHudGates() end
end

M.setPitwallProbe = function(open)
    pitwallProbeWanted = open and true or false
    if loaded then applyHudGates() end
end

M.setCareerMode = function(on)
    careerWanted = on and true or false
    if loaded then
        applyCareerMode()
    end
end

-- Vehicle auto extensions are timed inside onExtensionLoaded. Parsing the
-- tire module there is the slow line. The seated car parses it on the first
-- GFX step instead.
M.onExtensionLoaded = function() end
M.onInit = function() end
M.updateGFX = gateUpdateGFX

return M
