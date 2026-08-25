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
local trackEnvData = { timeOfDay = 0.5, cloudCover = 0.2 }

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
    trackEnvData.timeOfDay = tod
    trackEnvData.cloudCover = cloudCover
    
    local trackEnvSerialized = ""
    if type(serialize) == "function" then
        trackEnvSerialized = serialize(trackEnvData)
    end

    -- 3. Broadcast environmental values to the global physics mailbox
    if be and type(be.sendToMailbox) == "function" then
        be:sendToMailbox('tireWearMailboxEnvTemp', tostring(envTemp))
        be:sendToMailbox('tireWearMailboxTrackEnv', trackEnvSerialized)
    end
end

M.getGroundModels = getGroundModels
M.onUpdate = onUpdate
M.onExtensionUnloaded = function()
    -- 0.39 preferred unload hook (replaces deprecated onUnload)
end

return M