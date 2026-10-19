-- Upstream authorship: see CREDITS.md / NOTICE.
local M = {}

-- Fast local cache of frequently accessed primitive functions and tables
local tostring = tostring
local serialize = serialize
local ipairs = ipairs
local pairs = pairs
local type = type
local pcall = pcall

-- Pre-allocated state table to prevent per-frame garbage collection (GC) allocations
local trackEnvData = { timeOfDay = 0.5, cloudCover = 0.2, level = "" }

-- Throttle timer to reduce performance overhead from unthrottled loop serialization
local updateTimer = 0
local UPDATE_INTERVAL = 0.5 -- Update environmental stats at 2Hz (every 0.5s)

-- Manually reads properties directly from the Lua proxy or C++ cdata fallback
local function safeReadFriction(gm)
    local static = gm.staticFrictionCoefficient or (gm.cdata and gm.cdata.staticFrictionCoefficient)
    local sliding = gm.slidingFrictionCoefficient or (gm.cdata and gm.cdata.slidingFrictionCoefficient)
    local strength = gm.strength or (gm.cdata and gm.cdata.strength)
    local rough = gm.roughness or gm.rough or (gm.cdata and (gm.cdata.roughness or gm.cdata.rough))
    local fluidDensity = gm.fluidDensity or (gm.cdata and gm.cdata.fluidDensity)
    local defaultDepth = gm.defaultDepth or (gm.cdata and gm.cdata.defaultDepth)
    local stribeckVelocity = gm.stribeckVelocity or gm.stribeckVel
        or (gm.cdata and (gm.cdata.stribeckVelocity or gm.cdata.stribeckVel))
    return static, sliding, strength, rough, fluidDensity, defaultDepth, stribeckVelocity
end

-- Manually serializes ground model configurations safely using a protected caller
local function getGroundModels(objId)
    local v
    if objId then
        -- Priority: use direct vehicle object resolution; Fallback: scenetree
        if be and type(be.getObjectById) == "function" then
            v = be:getObjectById(objId)
        elseif scenetree then
            v = scenetree.findObjectById(objId)
        end
    elseif be then
        v = be:getPlayerVehicle(0)
    end

    if v and type(v.queueLuaCommand) == "function" and core_environment and core_environment.groundModels then
        -- Build the groundModels table manually as a string
        local cmd = "local gData = {"
        for k, gm in pairs(core_environment.groundModels) do
            local name = tostring(k)
            if #name > 0 and gm then
                local staticFriction = 1.0
                local slidingFriction = 1.0
                local strength = 1.0
                local rough = 0.0
                local fluidDensity = 0.0
                local defaultDepth = 0.0
                local stribeckVelocity = 1.0
                
                -- Read direct and C++ cdata properties safely inside pcall
                local ok, static, sliding, str, r, fluid, defDepth, stribeck = pcall(safeReadFriction, gm)
                if ok then
                    staticFriction = static or 1.0
                    slidingFriction = sliding or 1.0
                    strength = str or 1.0
                    rough = r or 0.0
                    fluidDensity = fluid or 0.0
                    defaultDepth = defDepth or 0.0
                    stribeckVelocity = stribeck or 1.0
                end
                
                cmd = cmd .. "[\"" .. name .. "\"] = { "
                cmd = cmd .. "staticFrictionCoefficient = " .. tostring(staticFriction) .. ", "
                cmd = cmd .. "slidingFrictionCoefficient = " .. tostring(slidingFriction) .. ", "
                cmd = cmd .. "strength = " .. tostring(strength) .. ", "
                cmd = cmd .. "rough = " .. tostring(rough) .. ", "
                cmd = cmd .. "fluidDensity = " .. tostring(fluidDensity) .. ", "
                cmd = cmd .. "defaultDepth = " .. tostring(defaultDepth) .. ", "
                cmd = cmd .. "stribeckVelocity = " .. tostring(stribeckVelocity) .. " }, "
            end
        end
        cmd = cmd .. "debug = 0 }; "
        
        -- DYNAMIC RESOLVER: Duck-types the active extensions in Vehicle Lua
        cmd = cmd .. "local found = false; "
        cmd = cmd .. "if type(extensions) == 'table' then "
        cmd = cmd .. "  for _, ext in pairs(extensions) do "
        cmd = cmd .. "    if type(ext) == 'table' and type(ext.setGroundModels) == 'function' then "
        cmd = cmd .. "      ext.setGroundModels(gData); found = true; "
        cmd = cmd .. "    end "
        cmd = cmd .. "  end "
        cmd = cmd .. "end; "
        
        -- Safe fallback path if no active extension is found
        cmd = cmd .. "if not found then "
        cmd = cmd .. "  if tireWearThermals and tireWearThermals.setGroundModels then "
        cmd = cmd .. "    tireWearThermals.setGroundModels(gData) "
        cmd = cmd .. "  else "
        cmd = cmd .. "    groundModels = gData "
        cmd = cmd .. "  end "
        cmd = cmd .. "end"
        
        v:queueLuaCommand(cmd)
    end
end

-- isTraffic is set only by gameplay_traffic.insertTraffic. Scenario race AI never gets it.
-- Traffic never loads the tire module. Everyone else loads it once.
local ntfState = {}
local ntfAge = {}
local LOAD_FULL = "if extensions and extensions.tireWearThermals and extensions.tireWearThermals.loadFull then extensions.tireWearThermals.loadFull() end"
local SKIP_TRAFFIC = "if extensions and extensions.tireWearThermals and extensions.tireWearThermals.skipTraffic then extensions.tireWearThermals.skipTraffic() end"

local function trafficSystemActive()
    local gt = gameplay_traffic
    if not gt or not gt.getState then return false end
    local ok, st = pcall(gt.getState)
    return ok and (st == "on" or st == "loading" or st == "spawning")
end

local function vehIsPlayer(veh)
    if type(veh.isPlayerControlled) ~= "function" then return false end
    local ok, seated = pcall(veh.isPlayerControlled, veh)
    return ok and seated and true or false
end

local function vehIsTraffic(veh, id)
    if veh.getDynDataFieldbyName then
        local ok, flag = pcall(veh.getDynDataFieldbyName, veh, "isTraffic", 0)
        if ok and (flag == "true" or flag == true) then return true end
    end
    if veh.isTraffic == "true" or veh.isTraffic == true then return true end
    local gt = gameplay_traffic
    if gt and gt.getTrafficData then
        local ok, data = pcall(gt.getTrafficData)
        if ok and type(data) == "table" and (data[id] or data[tonumber(id)]) then return true end
    end
    return false
end

local function sendNtf(veh, id, mode)
    if ntfState[id] == mode then return end
    if mode == "skip" and ntfState[id] == "full" then return end
    ntfState[id] = mode
    veh:queueLuaCommand(mode == "full" and LOAD_FULL or SKIP_TRAFFIC)
end

local function syncTrafficLight()
    if not be or type(be.getObjectCount) ~= "function" then return end
    local seen = {}
    local n = be:getObjectCount()
    for i = 0, n - 1 do
        local veh = be:getObject(i)
        if veh and veh.getId and veh.queueLuaCommand then
            local id = veh:getId()
            seen[id] = true
            ntfAge[id] = (ntfAge[id] or 0) + 1
            local mode = nil
            if vehIsPlayer(veh) then
                mode = "full"
            elseif vehIsTraffic(veh, id) or trafficSystemActive() then
                mode = "skip"
            elseif ntfAge[id] >= 4 then
                mode = "full"
            end
            if mode then sendNtf(veh, id, mode) end
        end
    end
    for id in pairs(ntfState) do
        if not seen[id] then
            ntfState[id] = nil
            ntfAge[id] = nil
        end
    end
end

-- Assigned below. onUpdate closes over this local.
local pushPlayerCareer

-- Main update loop executed with a performance throttle
local function onUpdate(dt)
    updateTimer = updateTimer + dt
    if updateTimer < UPDATE_INTERVAL then return end
    updateTimer = 0

    -- 1. Safely gather environmental metrics with multiple API fallbacks and global late-binding
    local envTemp = 21
    local tod = 0.5
    local cloudCover = 0.2

    if core_environment then
        -- Retrieve temperature safely (GE may return Kelvin or Celsius)
        if type(core_environment.getTemperature) == "function" then
            envTemp = core_environment.getTemperature() or 21
        elseif core_environment.temperature ~= nil then
            envTemp = core_environment.temperature
        end
        -- Normalize to Celsius before mailbox (vehicle also sanitizes, but keep units consistent)
        if type(envTemp) == "number" and envTemp > 180 then
            envTemp = envTemp - 273.15
        end

        -- Retrieve time of day safely
        if type(core_environment.getTimeOfDay) == "function" then
            local todData = core_environment.getTimeOfDay()
            if type(todData) == "table" then
                tod = todData.time or 0.5
            elseif type(todData) == "number" then
                tod = todData
            end
        elseif core_environment.timeOfDay ~= nil then
            tod = core_environment.timeOfDay
        end

        -- Retrieve cloud cover safely
        if type(core_environment.getCloudCover) == "function" then
            cloudCover = core_environment.getCloudCover() or 0.2
        elseif type(core_environment.getCloudScale) == "function" then
            cloudCover = core_environment.getCloudScale() or 0.2
        end
    end

    -- 2. Update values in our pre-allocated table (zero allocations)
    local levelName = ""
    if type(getCurrentLevelIdentifier) == "function" then
        local okLevel, levelId = pcall(getCurrentLevelIdentifier)
        if okLevel and type(levelId) == "string" then levelName = levelId end
    end
    trackEnvData.timeOfDay = tod
    trackEnvData.cloudCover = cloudCover
    trackEnvData.level = levelName
    
    local trackEnvSerialized = ""
    if type(serialize) == "function" then
        trackEnvSerialized = serialize(trackEnvData)
    end

    -- 3. Broadcast environmental values to the global physics mailbox
    if be and type(be.sendToMailbox) == "function" then
        be:sendToMailbox('tireWearMailboxEnvTemp', tostring(envTemp))
        be:sendToMailbox('tireWearMailboxTrackEnv', trackEnvSerialized)
    end

    -- Career wear stays off until this says otherwise. Freeroam never sets it.
    pushPlayerCareer()
end

local CAREER_ON = "if extensions and extensions.tireWearThermals and extensions.tireWearThermals.setCareerMode then extensions.tireWearThermals.setCareerMode(true) end"
local CAREER_OFF = "if extensions and extensions.tireWearThermals and extensions.tireWearThermals.setCareerMode then extensions.tireWearThermals.setCareerMode(false) end"

local function careerIsActive()
    if career_career and type(career_career.isActive) == "function" then
        local ok, active = pcall(career_career.isActive)
        return ok and active and true or false
    end
    return false
end

pushPlayerCareer = function()
    if not be or type(be.getPlayerVehicle) ~= "function" then return end
    local veh = be:getPlayerVehicle(0)
    if not veh or type(veh.queueLuaCommand) ~= "function" then return end
    veh:queueLuaCommand(careerIsActive() and CAREER_ON or CAREER_OFF)
end

local function onVehicleSpawned(vehId)
    if not be or type(be.getPlayerVehicle) ~= "function" then return end
    local player = be:getPlayerVehicle(0)
    if not player or type(player.getId) ~= "function" then return end
    local ok, id = pcall(player.getId, player)
    if ok and id == vehId then pushPlayerCareer() end
end

local function onCareerActive()
    pushPlayerCareer()
end

M.getGroundModels = getGroundModels
M.onUpdate = onUpdate
M.onVehicleSpawned = onVehicleSpawned
M.onCareerActive = onCareerActive
M.onExtensionUnloaded = function()
    ntfState = {}
    ntfAge = {}
end

return M