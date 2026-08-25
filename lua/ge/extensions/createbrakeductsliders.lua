-- Injects Front/Rear brake cooling duct sliders into every vehicle's Tuning menu.
-- Values persist in .pc configs via vars["$WheelCoolingDuctFront/Rear"].
-- Compatible with BeamNG 0.35+ variable system (documentation.beamng.com/.../variables/).
-- Upstream authorship: see CREDITS.md / NOTICE.

local M = {}

local variablesById = {}
local lastSentFront, lastSentRear = nil, nil
local sendTimer = 0
local SEND_INTERVAL = 0.5

local function makeDuctVar(name, title, subCategory, savedVal)
    return {
        name = name,
        category = "Brakes",
        subCategory = subCategory,
        title = title,
        description = "Tire/rim cooling duct opening. 1%=Closed (stock / no ducts), 100%=Fully open. Boosts tire & rim air cooling and slightly reduces brake→rim heat soak. Does NOT change native rotor cooling. Saved with vehicle configs.",
        type = "range",
        unit = "%",
        min = 1,
        minDis = 1,
        max = 100,
        maxDis = 100,
        step = 1,
        stepDis = 1,
        default = 1, -- Closed by default: most cars have no ducts
        val = savedVal or 1
    }
end

local function readSavedDucts(vehID)
    local front, rear = nil, nil
    local ok, veh = pcall(function()
        if be and be.getObjectByID then return be:getObjectByID(vehID) end
        return nil
    end)
    if not ok or not veh or not veh.partConfig then return front, rear end

    local partConfig = veh.partConfig
    local tablePartConfig = nil
    if type(jsonReadFile) == "function" and type(partConfig) == "string" and not partConfig:find("^{") then
        tablePartConfig = jsonReadFile(partConfig)
    end
    if not tablePartConfig and type(deserialize) == "function" then
        local ok2, decoded = pcall(deserialize, partConfig)
        if ok2 then tablePartConfig = decoded end
    end
    if type(tablePartConfig) == "table" and type(tablePartConfig.vars) == "table" then
        front = tablePartConfig.vars["$WheelCoolingDuctFront"]
        rear = tablePartConfig.vars["$WheelCoolingDuctRear"]
    end
    return front, rear
end

local function isOwnVehicle(vehID)
    local MP = (extensions and extensions.MPVehicleGE) or _G.MPVehicleGE
    if MP and type(MP.isOwn) == "function" and vehID then
        local ok, own = pcall(MP.isOwn, vehID)
        if ok and own == false then return false end
    end
    return true
end

local function onVehicleSpawned(vehID)
    if not isOwnVehicle(vehID) then return end
    if not core_vehicle_manager or type(core_vehicle_manager.getVehicleData) ~= "function" then return end
    local vehicleData = core_vehicle_manager.getVehicleData(vehID)
    if not vehicleData or not vehicleData.vdata then return end
    local vdata = vehicleData.vdata
    if not vdata.variables then vdata.variables = {} end

    local savedFront, savedRear = readSavedDucts(vehID)

    if not variablesById[vehID] then
        variablesById[vehID] = {
            ["$WheelCoolingDuctFront"] = makeDuctVar("$WheelCoolingDuctFront", "Front Cooling Ducts", "Front", savedFront),
            ["$WheelCoolingDuctRear"] = makeDuctVar("$WheelCoolingDuctRear", "Rear Cooling Ducts", "Rear", savedRear)
        }
    else
        variablesById[vehID]["$WheelCoolingDuctFront"].val = savedFront or variablesById[vehID]["$WheelCoolingDuctFront"].val or 1
        variablesById[vehID]["$WheelCoolingDuctRear"].val = savedRear or variablesById[vehID]["$WheelCoolingDuctRear"].val or 1
    end

    if type(tableMerge) == "function" then
        tableMerge(vdata.variables, variablesById[vehID])
    else
        for k, var in pairs(variablesById[vehID]) do
            vdata.variables[k] = var
        end
    end

    lastSentFront, lastSentRear = nil, nil -- force mailbox refresh
end

-- Restore slider values when a config with vars is applied mid-spawn
local function onSpawnCCallback(vehID)
    if not variablesById[vehID] then return end
    local ok, configDataIn = pcall(function()
        return select(2, debug.getlocal(3, 3))
    end)
    if not ok or type(configDataIn) ~= "string" or configDataIn:sub(1, 1) ~= "{" then return end
    local ok2, desirialized = pcall(deserialize, configDataIn)
    if not ok2 or type(desirialized) ~= "table" or type(desirialized.vars) ~= "table" then return end

    for name, _ in pairs(variablesById[vehID]) do
        if desirialized.vars[name] ~= nil then
            variablesById[vehID][name].val = desirialized.vars[name]
        else
            variablesById[vehID][name].val = variablesById[vehID][name].default or 1
        end
    end
end

local function sendDuctMailbox(force)
    if not be or type(be.sendToMailbox) ~= "function" then return end
    if not core_vehicle_manager or type(core_vehicle_manager.getPlayerVehicleData) ~= "function" then return end
    local pdata = core_vehicle_manager.getPlayerVehicleData()
    if not pdata or not pdata.vdata or not pdata.vdata.variables then return end

    local frontVar = pdata.vdata.variables["$WheelCoolingDuctFront"]
    local rearVar = pdata.vdata.variables["$WheelCoolingDuctRear"]
    local front = (frontVar and tonumber(frontVar.val)) or 1
    local rear = (rearVar and tonumber(rearVar.val)) or 1

    if force or front ~= lastSentFront or rear ~= lastSentRear then
        lastSentFront, lastSentRear = front, rear
        local payload = nil
        if type(serialize) == "function" then
            payload = serialize({ front, rear })
        else
            payload = string.format("{%s,%s}", tostring(front), tostring(rear))
        end
        be:sendToMailbox("tireWearMailboxDuct", payload)
    end
end

local function onSettingsChanged()
    sendDuctMailbox(true)
end

local function onUpdate(dt)
    sendTimer = sendTimer + (dt or 0)
    if sendTimer < SEND_INTERVAL then return end
    sendTimer = 0
    sendDuctMailbox(false)
end

local function onVehicleDestroyed(vehID)
    variablesById[vehID] = nil
end

M.onVehicleSpawned = onVehicleSpawned
M.onSpawnCCallback = onSpawnCCallback
M.onSettingsChanged = onSettingsChanged
M.onUpdate = onUpdate
M.onVehicleDestroyed = onVehicleDestroyed
M.onExtensionUnloaded = function()
    variablesById = {}
    lastSentFront, lastSentRear = nil, nil
end

return M
