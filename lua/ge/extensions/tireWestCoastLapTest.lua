-- West Coast Raceway (Belasco) lap / telemetry harness.
-- Default vehicle: ETK K-Series GT-IV DCT (etkc/race_DCT).
-- Override via trigger body key=value (see applyRunProfileFromTrigger).
-- Kingsnake sport-tire pass: vehicle=barstow/kingsnake (ESC not required).
-- Scintilla sport_plus pass: vehicle=scintilla/gts (ESC optional).
--
-- Modes:
--   auto   — slow sensor-aided learn lap (≤10 mph) → repair → 10 aggressive AI laps
--   manual — teleport once, arm tire CSV telemetry, AI disabled (user drives)
--
-- Triggers (under mods/unpacked/Node-Thermal-Friction-dev/tools/):
--   RUN_WC_MANUAL_TEL          → manual telemetry-only
--   RUN_WC_GT4_TEST            → auto AI test (default)
--   RUN_WC_GT4_TEST contents containing "manual" → manual telemetry-only
-- Outputs (CSV / status / result) go under tools/output/.
local M = {}

local logTag = 'tireWestCoastLapTest'
local TARGET_LAPS = 10
local LEARN_LAPS = 1
local LEARN_AGGRESSION = 0.30          -- gentle crawl; sensors + speed limit do the work
local RACE_AGGRESSION = 0.95
local LEARN_MAX_SPEED_MPS = 4.4704     -- 10 mph hard cap during learn
local LEARN_SPEED_ENFORCE_MPS = 5.0    -- soft brake if AI exceeds ~11.2 mph
local DAMAGE_RESET_THRESHOLD = 1200
local STUCK_SPEED = 2.5               -- m/s (race)
local STUCK_TIME = 8.0                -- seconds (race)
local STUCK_SPEED_LEARN = 0.35        -- m/s — crawling is normal under 10 mph
local STUCK_TIME_LEARN = 25.0         -- seconds before learn recover
local OFFTRACK_DIST = 95.0            -- m from script polyline (race)
local OFFTRACK_DIST_LEARN = 55.0      -- polyline distance; densified path stays close
local RECOVER_COOLDOWN = 12.0         -- seconds between recovers
local REENABLE_DELAY = 1.5            -- seconds after reset before AI restart
local LEARN_SPEED_SAMPLE_MAX = 12.0   -- ignore teleport/reset velocity spikes above this (m/s)
local MIN_LEARN_LAP_SEC = 180.0       -- ≤10 mph Belasco is many minutes; sub-3min is bogus
local MIN_RACE_LAP_SEC = 60.0         -- Belasco is ~90–110s; anything under 60s is invalid
local LAP_ARM_GRACE_SEC = 25.0        -- after recover/teleport, ignore finish until out-and-back
local FINISH_ENTER_M = 28.0           -- enter finish gate radius
local FINISH_EXIT_M = 48.0            -- hysteresis: must leave before next count
local ARM_MIN_NODES = 8               -- must hit this many checkpoints before finish counts
local NODE_HIT_RADIUS_EXTRA = 28      -- m beyond waypoint radius to register a hit
local MPH_PER_MPS = 2.2369362920544

local function getToolsDir()
  -- Relative to BeamNG user folder (io.open works here; absolute Windows paths often fail in GELUA)
  return 'mods/unpacked/Node-Thermal-Friction-dev/tools'
end

local function getOutDir()
  return getToolsDir() .. '/output'
end

local function pathJoin(dir, name)
  return dir .. '/' .. name
end

local state = {
  phase = 'boot',
  finished = false,
  failReason = nil,
  runKind = 'auto',     -- auto | manual
  lap = 0,              -- timed aggressive laps only
  learnLap = 0,
  mode = 'learning',    -- learning | racing | manual
  aggression = LEARN_AGGRESSION,
  startTime = 0,
  raceStartTime = 0,
  aiStarted = false,
  prefabSpawned = false,
  telemetryArmed = false,
  telemetryArmPending = false,
  telemetryArmFailCount = 0,
  telemetryArmRequestedAt = 0,
  teleportedOnce = false,
  resetCount = 0,
  lastRecoverTime = -999,
  needReenableAi = false,
  reenableTimer = 0,
  stuckTimer = 0,
  aiMode = nil,
  lapGraceUntil = 0,       -- os.clock deadline: no lap scoring
  lastLapTime = 0,         -- os.clock of last accepted lap cross
  lapArmed = false,
  insideFinish = false,
  nextNode = 2,            -- sequential checkpoint index (1 = finish)
  nodesHit = 0,            -- checkpoints hit since last finish
  lapTimes = {},           -- accepted race lap times (sec)
  learnLapTimes = {},
  lastDist = nil,
  learnMaxSpeedMps = 0,
  learnSpeedViolations = 0,
  learnSpeedOk = true,
  currentSpeedMps = 0,
  -- Run profile (overridable from trigger body; GT-IV defaults keep old scripts working)
  vehicle = 'etkc/race_DCT',
  vehicleLabel = 'ETK GT-IV DCT',
  telemetryCsvName = 'wc-gt4-lap-telemetry.csv',
  statusJsonName = 'wc-gt4-lap-status.json',
  resultTxtName = 'wc-gt4-lap-result.txt',
}

local function resultPath()
  return pathJoin(getOutDir(), state.resultTxtName or 'wc-gt4-lap-result.txt')
end

local function statusPath()
  return pathJoin(getOutDir(), state.statusJsonName or 'wc-gt4-lap-status.json')
end

local function telemetryPath()
  return pathJoin(getOutDir(), state.telemetryCsvName or 'wc-gt4-lap-telemetry.csv')
end

-- Parse optional key=value lines from a trigger file body into the run profile.
-- Always resets to GT-IV defaults first so a prior Kingsnake session cannot stick.
local function applyRunProfileFromTrigger(body)
  state.vehicle = 'etkc/race_DCT'
  state.vehicleLabel = 'ETK GT-IV DCT'
  state.telemetryCsvName = 'wc-gt4-lap-telemetry.csv'
  state.statusJsonName = 'wc-gt4-lap-status.json'
  state.resultTxtName = 'wc-gt4-lap-result.txt'
  if not body or body == '' then return end
  local vehicle = body:match('[%s\n]vehicle=([%w%._/%-]+)') or body:match('^vehicle=([%w%._/%-]+)')
  local label = body:match('[%s\n]label=([^\r\n]+)') or body:match('^label=([^\r\n]+)')
  local tel = body:match('[%s\n]telemetryCsv=([%w%._%-]+)') or body:match('^telemetryCsv=([%w%._%-]+)')
  local st = body:match('[%s\n]statusJson=([%w%._%-]+)') or body:match('^statusJson=([%w%._%-]+)')
  local res = body:match('[%s\n]resultTxt=([%w%._%-]+)') or body:match('^resultTxt=([%w%._%-]+)')
  local profile = (body:match('[%s\n]profile=([%w%._%-]+)') or body:match('^profile=([%w%._%-]+)') or ''):lower()

  if profile == 'kingsnake' then
    if not vehicle then vehicle = 'barstow/kingsnake' end
    if not label then label = 'Barstow Kingsnake' end
    if not tel then tel = 'wc-kingsnake-lap-telemetry.csv' end
    if not st then st = 'wc-kingsnake-lap-status.json' end
    if not res then res = 'wc-kingsnake-lap-result.txt' end
  elseif profile == 'scintilla' then
    if not vehicle then vehicle = 'scintilla/gts' end
    if not label then label = 'Civetta Scintilla GTs' end
    if not tel then tel = 'wc-scintilla-lap-telemetry.csv' end
    if not st then st = 'wc-scintilla-lap-status.json' end
    if not res then res = 'wc-scintilla-lap-result.txt' end
  end

  if vehicle and vehicle ~= '' then
    state.vehicle = vehicle:gsub('%.pc$', '')
  end
  if label and label:match('%S') then
    state.vehicleLabel = label:match('^%s*(.-)%s*$')
  end
  if tel and tel ~= '' then state.telemetryCsvName = tel end
  if st and st ~= '' then state.statusJsonName = st end
  if res and res ~= '' then state.resultTxtName = res end
end

local function writeJson(path, tbl)
  local ok, err = pcall(function()
    local encoded = jsonEncode(tbl)
    -- Prefer BeamNG writeFile (user-folder aware); fall back to io.open
    if type(writeFile) == 'function' then
      writeFile(path, encoded)
      return
    end
    if type(jsonWriteFile) == 'function' then
      jsonWriteFile(path, tbl, true)
      return
    end
    local f = io.open(path, 'w')
    if not f then
      f = io.open('/' .. path, 'w')
    end
    if not f then error('open failed: ' .. tostring(path)) end
    f:write(encoded)
    f:close()
  end)
  if not ok then
    log('E', logTag, 'jsonWrite failed: ' .. tostring(err) .. ' path=' .. tostring(path))
  end
end

local function appendResult(line)
  local ok, err = pcall(function()
    local path = resultPath()
    local text = tostring(line) .. '\n'
    if type(writeFile) == 'function' and FS and FS:fileExists(path) then
      -- read-append-write when writeFile can't append
      local prev = ''
      pcall(function()
        local rf = io.open(path, 'r')
        if rf then prev = rf:read('*a') or ''; rf:close() end
      end)
      writeFile(path, prev .. text)
      return
    end
    local f = io.open(path, 'a')
    if not f then f = io.open('/' .. path, 'a') end
    if f then
      f:write(text)
      f:close()
    end
  end)
  if not ok then
    log('E', logTag, 'appendResult failed: ' .. tostring(err))
  end
end

local function setPhase(p, extra)
  state.phase = p
  -- Manual sessions use 4 timed laps; auto uses TARGET_LAPS (10 aggressive)
  local timedTarget = (state.runKind == 'manual') and 4 or TARGET_LAPS
  if extra and type(extra.targetLaps) == 'number' then
    timedTarget = extra.targetLaps
  end
  local payload = {
    phase = state.phase,
    runKind = state.runKind,
    mode = state.mode,
    lap = state.lap,
    learnLap = state.learnLap,
    targetLaps = timedTarget,
    raceTargetLaps = TARGET_LAPS,
    learnLaps = LEARN_LAPS,
    aggression = state.aggression,
    aiStarted = state.aiStarted,
    telemetryArmed = state.telemetryArmed,
    finished = state.finished,
    failReason = state.failReason,
    resetCount = state.resetCount,
    nodesHit = state.nodesHit,
    nextNode = state.nextNode,
    lapArmed = state.lapArmed,
    lapTimes = state.lapTimes,
    learnLapTimes = state.learnLapTimes,
    learnMaxSpeedMps = state.learnMaxSpeedMps,
    learnMaxSpeedMph = state.learnMaxSpeedMps * MPH_PER_MPS,
    learnSpeedViolations = state.learnSpeedViolations,
    learnSpeedOk = state.learnSpeedOk,
    learnCapMph = 10,
    currentSpeedMps = state.currentSpeedMps,
    currentSpeedMph = state.currentSpeedMps * MPH_PER_MPS,
    elapsed = state.startTime > 0 and (os.clock() - state.startTime) or 0,
    raceElapsed = state.raceStartTime > 0 and (os.clock() - state.raceStartTime) or 0,
    vehicle = state.vehicle or 'etkc/race_DCT',
    vehicleLabel = state.vehicleLabel or 'ETK GT-IV DCT',
    track = 'west_coast_usa/quickrace/race_track (Belasco)',
    telemetryCsv = telemetryPath(),
    extra = extra,
  }
  writeJson(statusPath(), payload)
  log('I', logTag, 'phase=' .. p .. ' runKind=' .. tostring(state.runKind)
    .. ' mode=' .. tostring(state.mode)
    .. ' lap=' .. tostring(state.lap) .. ' learn=' .. tostring(state.learnLap)
    .. ' nodes=' .. tostring(state.nodesHit) .. ' armed=' .. tostring(state.lapArmed)
    .. ' tel=' .. tostring(state.telemetryArmed))
end

local function getPlayerVeh()
  if be and be.getPlayerVehicle then
    return be:getPlayerVehicle(0)
  end
  return nil
end

-- Checkpoint positions from levels/west_coast_usa/quickrace/race_track.prefab (lap order).
-- Index 1 = Checkpoint_finish; 2..13 = Checkpoint_1 .. Checkpoint_12.
local BELASCO_FINISH = vec3(391.869995, -252.528, 144.863998)
local BELASCO_SCRIPT = {
  { x = 391.8700, y = -252.5280, z = 144.8640, r = 12.0 }, -- finish / start
  { x = 33.3243,  y = -199.2640, z = 123.9135, r = 10.8 }, -- Checkpoint_1
  { x = 167.4147, y = -469.5417, z = 142.5712, r = 9.6 },  -- Checkpoint_2
  { x = -7.5180,  y = -657.8444, z = 131.8818, r = 9.0 },  -- Checkpoint_3
  { x = -110.8354,y = -427.7834, z = 123.8155, r = 13.7 }, -- Checkpoint_4
  { x = -278.6839,y = -198.5779, z = 119.1800, r = 9.0 },  -- Checkpoint_5
  { x = 368.6414, y = 293.2215,  z = 119.6627, r = 8.7 },  -- Checkpoint_6
  { x = 723.2717, y = 659.9144,  z = 130.3621, r = 10.9 }, -- Checkpoint_7
  { x = 785.1316, y = 315.8590,  z = 158.5645, r = 11.1 }, -- Checkpoint_8
  { x = 869.9496, y = 168.1190,  z = 159.0081, r = 10.4 }, -- Checkpoint_9
  { x = 848.1912, y = 121.1950,  z = 149.4293, r = 11.0 }, -- Checkpoint_10
  { x = 729.1861, y = -148.1200, z = 146.7421, r = 8.0 },  -- Checkpoint_11
  { x = 680.0966, y = -225.3247, z = 146.7461, r = 11.4 }, -- Checkpoint_12
}

local function nearestScriptIndex(pos)
  local bestI, bestD = 1, 1e12
  for i, n in ipairs(BELASCO_SCRIPT) do
    local d = pos:distance(vec3(n.x, n.y, n.z))
    if d < bestD then bestD = d; bestI = i end
  end
  return bestI, bestD
end

-- Distance to the closed polyline of checkpoint centers (not just nearest node).
-- Sparse Belasco nodes are hundreds of metres apart; mid-segment cars look "offtrack"
-- if we only measure node distance.
local function distToScriptPolyline(pos)
  local best = 1e12
  local nCount = #BELASCO_SCRIPT
  for i = 1, nCount do
    local a = BELASCO_SCRIPT[i]
    local b = BELASCO_SCRIPT[(i % nCount) + 1]
    local ax, ay, az = a.x, a.y, a.z
    local bx, by, bz = b.x, b.y, b.z
    local abx, aby, abz = bx - ax, by - ay, bz - az
    local apx, apy, apz = pos.x - ax, pos.y - ay, pos.z - az
    local ab2 = abx * abx + aby * aby + abz * abz
    local t = 0
    if ab2 > 1e-6 then
      t = (apx * abx + apy * aby + apz * abz) / ab2
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx, cy, cz = ax + abx * t, ay + aby * t, az + abz * t
    local dx, dy, dz = pos.x - cx, pos.y - cy, pos.z - cz
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < best then best = d end
  end
  return best
end

-- Densify checkpoint script for AI pathing (~35 m spacing) so crawl stays on track.
local function densifyScript(nodes, spacing)
  spacing = spacing or 35.0
  local out = {}
  local nCount = #nodes
  for i = 1, nCount do
    local a = nodes[i]
    local b = nodes[(i % nCount) + 1]
    table.insert(out, { x = a.x, y = a.y, z = a.z, r = a.r or 10 })
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len > spacing then
      local steps = math.floor(len / spacing)
      for s = 1, steps - 1 do
        local t = s / steps
        local r = (a.r or 10) * (1 - t) + (b.r or 10) * t
        table.insert(out, {
          x = a.x + dx * t,
          y = a.y + dy * t,
          z = a.z + dz * t,
          r = r,
        })
      end
    end
  end
  return out
end

local function resetLapProgress()
  state.lapArmed = false
  state.insideFinish = false
  state.nextNode = 2
  state.nodesHit = 0
  state.lastDist = nil
end

local function teleportToRacetrack(veh)
  local sp = scenetree.findObject('race_track_standing_spawn')
      or scenetree.findObject('spawns_racetrack')
  if not sp then
    local pos = BELASCO_FINISH
    local rot = quatFromDir(vec3(1, 0, 0), vec3(0, 0, 1))
    spawn.safeTeleport(veh, pos, rot, nil, nil, false, true)
    return 'belasco_finish_fallback'
  end
  local pos = sp:getPosition()
  local rot = quat(sp:getRotation())
  spawn.safeTeleport(veh, pos, rot, nil, nil, false, true)
  return sp:getName() or 'spawn'
end

local function teleportToNearestNode(veh, pos)
  local idx = nearestScriptIndex(pos)
  local n = BELASCO_SCRIPT[idx]
  local nextN = BELASCO_SCRIPT[(idx % #BELASCO_SCRIPT) + 1]
  local p = vec3(n.x, n.y, n.z)
  local dir = vec3(nextN.x - n.x, nextN.y - n.y, nextN.z - n.z)
  if dir:length() < 0.1 then dir = vec3(1, 0, 0) end
  dir:normalize()
  local rot = quatFromDir(dir, vec3(0, 0, 1))
  spawn.safeTeleport(veh, p, rot, nil, nil, false, true)
  return idx
end

-- Vehicle auto/ modules register as basename via loadAtRoot(..., "").
-- Short-name extensions.tireWearThermals lazy-loads the NON-auto path and
-- logs "extension unavailable" if auto load was skipped — never call that blindly.
local VEH_TEL_EXT_PATH = 'lua/vehicle/extensions/auto/tireWearThermals'
local VEH_TEL_EXT_NAME = 'tireWearThermals'

local function armTelemetry(veh, intervalSec)
  if not veh then return end
  local telPath = telemetryPath()
  -- Buffered CSV I/O allows denser sampling; default 1.0s (manual was 3.0s for open/close lag)
  -- Header: legacy wall..film + appended UI-stream cols (profile/purpose/patch/native aero/dutyMods/gates).
  -- Parsers that only read legacy indices remain valid; new fields are suffix-only.
  local interval = intervalSec or 1.0
  -- Always re-queue: vehicle onReset used to clear path; keep CSV alive for full stint
  local cmd = string.format([[
    local ext = rawget(_G, %q)
    if not (ext and type(ext.setTelemetryCsv) == 'function') then
      pcall(function()
        if extensions and extensions.loadAtRoot then
          extensions.loadAtRoot(%q, '')
        end
      end)
      ext = rawget(_G, %q)
    end
    local armed = false
    if ext and type(ext.setTelemetryCsv) == 'function' then
      ext.setTelemetryCsv(true, %q, %s)
      armed = true
    end
    if obj and type(obj.queueGameEngineLua) == 'function' then
      obj:queueGameEngineLua(
        'if tireWestCoastLapTest and tireWestCoastLapTest.onTelemetryArmResult then tireWestCoastLapTest.onTelemetryArmResult('
        .. tostring(armed) .. ') end')
    end
  ]], VEH_TEL_EXT_NAME, VEH_TEL_EXT_PATH, VEH_TEL_EXT_NAME, telPath, tostring(interval))
  veh:queueLuaCommand(cmd)
  -- Do NOT set telemetryArmed=true here — wait for vehicle onTelemetryArmResult
  state.telemetryArmPending = true
  state.telemetryArmRequestedAt = os.clock()
  state.telemetryIntervalSec = interval
end

local function flushTelemetry(veh)
  if not veh then return end
  veh:queueLuaCommand(string.format([[
    local ext = rawget(_G, %q)
    if not (ext and type(ext.flushTelemetryCsv) == 'function') then
      pcall(function()
        if extensions and extensions.loadAtRoot then
          extensions.loadAtRoot(%q, '')
        end
      end)
      ext = rawget(_G, %q)
    end
    if ext and type(ext.flushTelemetryCsv) == 'function' then
      ext.flushTelemetryCsv()
    end
  ]], VEH_TEL_EXT_NAME, VEH_TEL_EXT_PATH, VEH_TEL_EXT_NAME))
end

-- Vehicle → GE confirmation after setTelemetryCsv attempt (avoids optimistic false positives)
local function onTelemetryArmResult(ok)
  state.telemetryArmPending = false
  if ok then
    state.telemetryArmed = true
    state.telemetryArmFailCount = 0
    log('I', logTag, 'telemetry arm CONFIRMED by vehicle extension')
    appendResult('telemetry arm CONFIRMED (vehicle setTelemetryCsv ok)')
    if state.phase == 'arming' or state.phase == 'manual_telemetry' then
      setPhase(state.phase, {
        telemetryArmed = true,
        telemetryConfirmed = true,
        ai = 'disabled',
      })
    end
    return
  end
  state.telemetryArmed = false
  state.telemetryArmFailCount = (state.telemetryArmFailCount or 0) + 1
  log('E', logTag, 'telemetry arm FAILED — vehicle extension unavailable (fail #'
    .. tostring(state.telemetryArmFailCount) .. ')')
  appendResult('FAIL: vehicle extension ' .. VEH_TEL_EXT_NAME .. ' unavailable / setTelemetryCsv missing')
  if state.runKind == 'manual' and state.telemetryArmFailCount >= 2 then
    state.failReason = 'telemetry extension unavailable'
    state.finished = true
    setPhase('failed', {
      note = 'vehicle extension tireWearThermals failed to load — no CSV',
      telemetryArmed = false,
      ai = 'disabled',
    })
    guihooks.trigger('toastrMsg', {
      type = 'error',
      title = 'Telemetry Failed',
      msg = 'Vehicle tire extension unavailable — CSV not armed',
    })
  end
end

local function toLuaScriptNodes(script)
  local parts = {}
  for _, n in ipairs(script or {}) do
    if n.v then
      table.insert(parts, string.format('{x=%0.4f,y=%0.4f,z=%0.4f,r=%0.3f,v=%0.4f}',
        n.x, n.y, n.z, n.r or 4, n.v))
    else
      table.insert(parts, string.format('{x=%0.4f,y=%0.4f,z=%0.4f,r=%0.3f}', n.x, n.y, n.z, n.r or 4))
    end
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function buildClosedScript(densify)
  local base = BELASCO_SCRIPT
  if densify then
    base = densifyScript(BELASCO_SCRIPT, 35.0)
  end
  local script = {}
  for _, n in ipairs(base) do
    -- Do NOT set node.v: BeamNG docs say forced v skips awareness + routeSpeedLimit.
    table.insert(script, { x = n.x, y = n.y, z = n.z, r = n.r })
  end
  local first = base[1]
  table.insert(script, { x = first.x, y = first.y, z = first.z, r = first.r })
  return script
end

-- opts.learn = true → ≤10 mph, sensor-aided (avoidCars awareness + IMU + routeSpeed limit)
local function queueAiDrive(veh, aggression, laps, opts)
  if not veh then return end
  opts = opts or {}
  local learn = opts.learn == true
  -- Learn uses densified path so AI follows track arc; race uses sparse checkpoints.
  local script = buildClosedScript(learn)

  if learn then
    veh:queueLuaCommand(string.format([[
      ai.setMode('disabled')
      -- Sensor-aided crawl:
      --  * AI planner uses vehicle IMU (sensors.gx/gy/gz) for traction limits
      --  * setAvoidCars + awarenessForceCoef = proximity / obstacle awareness
      --  * routeSpeed limit hard-caps at 10 mph (no per-node v — that skips awareness)
      ai.setAvoidCars('on')
      ai.setParameters({
        awarenessForceCoef = 0.85,
        lookAheadKv = 0.45,
        edgeDist = 1.5,
        understeerThrottleControl = 'on',
        oversteerThrottleControl = 'on',
        throttleTcs = 'on',
        abBrakeControl = 'on',
        underSteerBrakeControl = 'on',
        targetSpeedSmootherRate = 4
      })
      ai.setSpeed(%s)
      ai.setSpeedMode('limit')
      ai.driveUsingPath({
        script = %s,
        noOfLaps = %d,
        aggression = %s,
        avoidCars = 'on',
        driveInLane = 'off',
        routeSpeed = %s,
        routeSpeedMode = 'limit'
      })
    ]], tostring(LEARN_MAX_SPEED_MPS), toLuaScriptNodes(script), laps,
      tostring(aggression), tostring(LEARN_MAX_SPEED_MPS)))
    state.aiMode = 'learn_sensor_limit:' .. tostring(#script)
  else
    veh:queueLuaCommand(string.format([[
      ai.setMode('disabled')
      ai.setSpeed(nil)
      ai.setSpeedMode('off')
      ai.setAvoidCars('off')
      ai.setParameters({ awarenessForceCoef = 0.25, edgeDist = 0 })
      ai.driveUsingPath({
        script = %s,
        noOfLaps = %d,
        aggression = %s,
        avoidCars = 'off',
        driveInLane = 'off'
      })
    ]], toLuaScriptNodes(script), laps, tostring(aggression)))
    state.aiMode = 'race_script:' .. tostring(#script)
  end
  state.aggression = aggression
end

local function startAiLaps(veh)
  if state.aiStarted or not veh then return false end

  local prefabPath = '/levels/west_coast_usa/quickrace/race_track.prefab'
  if FS:fileExists(prefabPath) and not state.prefabSpawned then
    local name = generateObjectNameForClass('Prefab', 'tireWcRacePrefab_')
    pcall(function()
      spawnPrefab(name, prefabPath, '0 0 0', '0 0 1', '1 1 1')
    end)
    state.prefabSpawned = true
  end

  -- Slow sensor-aided learn lap first (≤10 mph), then aggressive timed laps.
  state.mode = 'learning'
  state.aggression = LEARN_AGGRESSION
  state.learnLap = 0
  state.lap = 0
  state.learnMaxSpeedMps = 0
  state.learnSpeedViolations = 0
  state.learnSpeedOk = true
  queueAiDrive(veh, LEARN_AGGRESSION, LEARN_LAPS + 2, { learn = true })

  state.aiStarted = true
  state.startTime = os.clock()
  setPhase('learning', { aiMode = state.aiMode, learnCapMph = 10 })
  appendResult(string.format(
    'AI SLOW LEARN start cap=%.2f m/s (10 mph) aggression=%.2f sensorAided=1 then race aggression=%.2f x%d mode=%s',
    LEARN_MAX_SPEED_MPS, LEARN_AGGRESSION, RACE_AGGRESSION, TARGET_LAPS, tostring(state.aiMode)))
  return true
end

local function armLapGrace(seconds)
  local untilT = os.clock() + (seconds or LAP_ARM_GRACE_SEC)
  if untilT > state.lapGraceUntil then
    state.lapGraceUntil = untilT
  end
  resetLapProgress()
end

local function recoverVehicle(veh, reason)
  local now = os.clock()
  if (now - state.lastRecoverTime) < RECOVER_COOLDOWN then return end
  state.lastRecoverTime = now
  state.resetCount = state.resetCount + 1
  state.stuckTimer = 0
  -- Drop poisoned max from teleport spike if any
  if state.learnMaxSpeedMps > LEARN_SPEED_SAMPLE_MAX then
    state.learnMaxSpeedMps = 0
  end
  armLapGrace(LAP_ARM_GRACE_SEC)

  local pos = veh:getPosition() or BELASCO_FINISH
  local nodeIdx = teleportToNearestNode(veh, pos)
  -- Prefer a mid-track node if recovery put us on finish (avoids instant lap cross)
  if nodeIdx == 1 then
    nodeIdx = teleportToNearestNode(veh, vec3(BELASCO_SCRIPT[3].x, BELASCO_SCRIPT[3].y, BELASCO_SCRIPT[3].z))
  end
  -- Continue forward from recovered node, but do NOT credit pre-crash progress
  state.nodesHit = 0
  state.lapArmed = false
  state.insideFinish = false
  if nodeIdx >= #BELASCO_SCRIPT then
    state.nextNode = 1 -- approaching finish; still unarmed until a full loop
  elseif nodeIdx > 1 then
    state.nextNode = nodeIdx + 1
  else
    state.nextNode = 2
  end
  if be and be.resetVehicle then
    pcall(function() be:resetVehicle(0) end)
  end
  veh:queueLuaCommand('obj:requestReset(RESET_PHYSICS)')
  state.needReenableAi = true
  state.reenableTimer = 0
  appendResult(string.format('RECOVER #%d reason=%s node=%d mode=%s nodesHit=%d',
    state.resetCount, tostring(reason), nodeIdx, tostring(state.mode), state.nodesHit))
  setPhase(state.mode == 'learning' and 'learning' or 'racing', { recover = reason })
end

local function getVehDamage(veh)
  if not veh or not map or not map.objects then return 0 end
  local id = veh:getID()
  local obj = map.objects[id]
  if obj and obj.damage then return obj.damage end
  return 0
end

local function getVehSpeed(veh)
  if not veh then return 0 end
  local ok, vel = pcall(function() return veh:getVelocity() end)
  if ok and vel then return vel:length() end
  return 0
end

local function finishTest(reason)
  if state.finished then return end
  state.finished = true
  state.failReason = reason
  setPhase(reason and 'failed' or 'complete')

  local veh = getPlayerVeh()
  if veh then
    flushTelemetry(veh)
    veh:queueLuaCommand(string.format([[
      ai.setMode('disabled')
      local ext = rawget(_G, %q)
      if ext and type(ext.setTelemetryCsv) == 'function' then
        ext.setTelemetryCsv(false)
      end
    ]], VEH_TEL_EXT_NAME))
  end
  state.telemetryArmed = false
  state.telemetryArmPending = false

  local elapsed = state.startTime > 0 and (os.clock() - state.startTime) or 0
  local raceElapsed = state.raceStartTime > 0 and (os.clock() - state.raceStartTime) or 0
  appendResult('==== WEST COAST BELASCO RESULT ====')
  appendResult(string.format('vehicle=%s (%s)', state.vehicle or '?', state.vehicleLabel or '?'))
  appendResult('track=Belasco Motorsports Park / race_track')
  appendResult(string.format('learnAggression=%.2f raceAggression=%.2f learnCapMph=10', LEARN_AGGRESSION, RACE_AGGRESSION))
  appendResult(string.format('learnMaxSpeedMph=%.2f learnSpeedViolations=%d learnSpeedOk=%s',
    state.learnMaxSpeedMps * MPH_PER_MPS, state.learnSpeedViolations, tostring(state.learnSpeedOk)))
  appendResult(string.format('learnLaps=%d timedLaps=%d/%d resets=%d',
    state.learnLap, state.lap, TARGET_LAPS, state.resetCount))
  if #state.learnLapTimes > 0 then
    local parts = {}
    for _, t in ipairs(state.learnLapTimes) do table.insert(parts, string.format('%.1f', t)) end
    appendResult('learnLapTimesSec=' .. table.concat(parts, ','))
  end
  if #state.lapTimes > 0 then
    local parts = {}
    local sum = 0
    for _, t in ipairs(state.lapTimes) do
      table.insert(parts, string.format('%.1f', t))
      sum = sum + t
    end
    appendResult('raceLapTimesSec=' .. table.concat(parts, ','))
    appendResult(string.format('raceLapAvgSec=%.1f best=%.1f', sum / #state.lapTimes, math.min(unpack(state.lapTimes))))
  end
  appendResult(string.format('elapsedSec=%.1f raceElapsedSec=%.1f', elapsed, raceElapsed))
  appendResult(string.format('status=%s', reason and ('FAIL:' .. reason) or 'OK'))
  appendResult('telemetry=' .. telemetryPath())
  appendResult('statusJson=' .. statusPath())
  guihooks.trigger('toastrMsg', {
    type = reason and 'error' or 'success',
    title = 'NTF Lap Test',
    msg = reason and ('Failed: ' .. reason) or ('Completed ' .. TARGET_LAPS .. ' aggressive laps'),
  })
end

local bootTimer = 0
local sampleTimer = 0
local telemetryFlushTimer = 0
local lapPollTimer = 0
local recoverPollTimer = 0
local learnSpeedPollTimer = 0
local MANUAL_TELEMETRY_INTERVAL = 1.0
local MANUAL_FLUSH_SEC = 45.0

local function beginAggressiveStint(veh)
  state.mode = 'racing'
  state.aggression = RACE_AGGRESSION
  state.lap = 0
  state.lapTimes = {}
  state.raceStartTime = os.clock()
  state.lastLapTime = os.clock()
  state.stuckTimer = 0
  armLapGrace(LAP_ARM_GRACE_SEC)

  -- Repair + place at start, then aggressive AI after short delay
  teleportToRacetrack(veh)
  if be and be.resetVehicle then
    pcall(function() be:resetVehicle(0) end)
  end
  veh:queueLuaCommand('obj:requestReset(RESET_PHYSICS)')
  state.needReenableAi = true
  state.reenableTimer = 0
  state.pendingRaceAi = true
  setPhase('racing', { switchedFromLearn = true })
  appendResult(string.format('LEARN complete — starting aggressive stint aggression=%.2f laps=%d',
    RACE_AGGRESSION, TARGET_LAPS))
end

local function disableAi(veh)
  if not veh then return end
  veh:queueLuaCommand([[
    ai.setMode('disabled')
    ai.setSpeed(nil)
    ai.setSpeedMode('off')
    if ai.setAvoidCars then ai.setAvoidCars('off') end
  ]])
  state.aiStarted = false
  state.needReenableAi = false
  state.reenableTimer = 0
  state.pendingRaceAi = false
  state.aiMode = 'disabled'
end

local function clearTriggers()
  pcall(function() os.remove(pathJoin(getToolsDir(), 'RUN_WC_GT4_TEST')) end)
  pcall(function() os.remove(pathJoin(getToolsDir(), 'RUN_WC_MANUAL_TEL')) end)
  pcall(function() os.remove(pathJoin(getToolsDir(), 'STOP_WC_TEST')) end)
end

-- User/harness abort: kill AI, disarm CSV, mark stopped (does not quit BeamNG).
local function abortUserStop(reason)
  reason = reason or 'user_abort'
  clearTriggers()
  local veh = getPlayerVeh()
  disableAi(veh)
  if veh then
    flushTelemetry(veh)
    veh:queueLuaCommand(string.format([[
      local ext = rawget(_G, %q)
      if ext and type(ext.setTelemetryCsv) == 'function' then
        ext.setTelemetryCsv(false)
      end
    ]], VEH_TEL_EXT_NAME))
  end
  state.telemetryArmed = false
  state.telemetryArmPending = false
  state.finished = true
  state.failReason = reason
  setPhase('stopped', { note = reason, telemetryArmed = false, ai = 'disabled' })
  appendResult('==== TEST STOPPED BY USER ====')
  appendResult(tostring(reason))
  appendResult('telemetry=off AI=disabled phase=stopped')
  guihooks.trigger('toastrMsg', {
    type = 'warning',
    title = 'NTF Lap Test',
    msg = 'Stopped — telemetry off, AI disabled',
  })
end

local function pollStopTrigger()
  local stopPath = pathJoin(getToolsDir(), 'STOP_WC_TEST')
  local sf = io.open(stopPath, 'r')
  if not sf then return false end
  local body = sf:read('*a') or ''
  sf:close()
  pcall(function() os.remove(stopPath) end)
  abortUserStop((body:match('%S') and body:match('^[^\r\n]+')) or 'user aborted')
  return true
end

-- Returns runKind ('auto'|'manual') and trigger name, or nil,nil if none.
-- Also applies vehicle/CSV profile from trigger body (key=value / profile=kingsnake).
local function readTriggerMode()
  local manPath = pathJoin(getToolsDir(), 'RUN_WC_MANUAL_TEL')
  local mf = io.open(manPath, 'r')
  if mf then
    local body = mf:read('*a') or ''
    mf:close()
    applyRunProfileFromTrigger(body)
    return 'manual', 'RUN_WC_MANUAL_TEL'
  end
  local autoPath = pathJoin(getToolsDir(), 'RUN_WC_GT4_TEST')
  local af = io.open(autoPath, 'r')
  if af then
    local contents = af:read('*a') or ''
    af:close()
    applyRunProfileFromTrigger(contents)
    if contents:lower():find('manual', 1, true) then
      return 'manual', 'RUN_WC_GT4_TEST'
    end
    return 'auto', 'RUN_WC_GT4_TEST'
  end
  return nil, nil
end

local function shouldAutoStart()
  local kind = readTriggerMode()
  return kind ~= nil
end

local function ensurePrefab()
  local prefabPath = '/levels/west_coast_usa/quickrace/race_track.prefab'
  if FS:fileExists(prefabPath) and not state.prefabSpawned then
    local name = generateObjectNameForClass('Prefab', 'tireWcRacePrefab_')
    pcall(function()
      spawnPrefab(name, prefabPath, '0 0 0', '0 0 1', '1 1 1')
    end)
    state.prefabSpawned = true
    appendResult('prefab spawned')
  end
end

local function enterManualTelemetry(veh, reason)
  disableAi(veh)
  ensurePrefab()
  if veh and not state.teleportedOnce then
    local where = teleportToRacetrack(veh)
    state.teleportedOnce = true
    appendResult('teleport=' .. tostring(where))
  end
  if veh then
    armTelemetry(veh)
  end
  state.runKind = 'manual'
  state.mode = 'manual'
  state.aggression = 0
  state.aiStarted = false
  state.finished = false
  state.failReason = nil
  if state.startTime <= 0 then
    state.startTime = os.clock()
  end
  setPhase('manual_telemetry', {
    telemetryArmed = state.telemetryArmed,
    ai = 'disabled',
    targetLaps = 4,
    telemetryIntervalSec = state.telemetryIntervalSec or 1.0,
    note = 'User drives 4 Belasco laps; AI off; CSV buffered @1s; survives resets',
  })
  appendResult(tostring(reason or 'manual telemetry armed'))
  appendResult('AI=disabled phase=manual_telemetry targetLaps=4')
  appendResult(string.format('vehicle=%s (%s)', state.vehicle or '?', state.vehicleLabel or '?'))
  appendResult(string.format('telemetryIntervalSec=%.1f (buffered CSV; denser than old 3s lag workaround)', state.telemetryIntervalSec or 1.0))
  appendResult('telemetry=' .. telemetryPath())
  appendResult('CSV retains data across vehicle reset (append-only + arm marker)')
  appendResult('DRIVE NOW — 4 Belasco laps; telemetry CSV is armed (ESC not required for this tune pass)')
  guihooks.trigger('toastrMsg', {
    type = 'info',
    title = 'Manual Telemetry',
    msg = string.format('AI off — %s CSV @1s. Drive 4 laps.', state.vehicleLabel or 'vehicle'),
  })
end

local function beginSequence(reason, runKind)
  runKind = runKind or 'auto'
  state.finished = false
  state.runKind = runKind
  state.lap = 0
  state.learnLap = 0
  state.mode = (runKind == 'manual') and 'manual' or 'learning'
  state.aggression = (runKind == 'manual') and 0 or LEARN_AGGRESSION
  state.aiStarted = false
  state.prefabSpawned = false
  state.telemetryArmed = false
  state.telemetryArmPending = false
  state.telemetryArmFailCount = 0
  state.telemetryArmRequestedAt = 0
  state.teleportedOnce = false
  state.startTime = 0
  state.raceStartTime = 0
  state.failReason = nil
  state.resetCount = 0
  state.lastRecoverTime = -999
  state.needReenableAi = false
  state.reenableTimer = 0
  state.stuckTimer = 0
  state.pendingRaceAi = false
  state.aiMode = nil
  state.lapGraceUntil = 0
  state.lastLapTime = 0
  state.lapTimes = {}
  state.learnLapTimes = {}
  state.learnMaxSpeedMps = 0
  state.learnSpeedViolations = 0
  state.learnSpeedOk = true
  state.currentSpeedMps = 0
  resetLapProgress()
  bootTimer = 0
  sampleTimer = 0
  telemetryFlushTimer = 0
  lapPollTimer = 0
  recoverPollTimer = 0
  learnSpeedPollTimer = 0
  clearTriggers()
  setPhase('boot')
  pcall(function()
    local f = io.open(resultPath(), 'w')
    if f then
      local label = state.vehicleLabel or state.vehicle or 'vehicle'
      if runKind == 'manual' then
        f:write(string.format('WEST COAST RACEWAY — %s MANUAL DRIVE + TELEMETRY ONLY\n', label))
      else
        f:write(string.format('WEST COAST RACEWAY — %s LEARN + 10 LAP AGGRESSIVE TEST\n', label))
      end
      f:write(os.date('!%Y-%m-%d %H:%M:%SZ') .. '\n')
      f:write(string.format('vehicle=%s\n', state.vehicle or '?'))
      f:write(string.format('telemetry=%s\n\n', telemetryPath()))
      f:close()
    end
  end)
  appendResult(tostring(reason or 'starting sequence') .. ' runKind=' .. tostring(runKind)
    .. ' vehicle=' .. tostring(state.vehicle))
end

local function isActiveRunPhase()
  return state.phase == 'boot' or state.phase == 'teleport' or state.phase == 'arming'
      or state.phase == 'start_ai' or state.phase == 'learning' or state.phase == 'racing'
      or state.phase == 'manual_telemetry'
end

-- Hot-switch / idle poll: consume trigger and start (or switch to) the right mode.
local function tryConsumeTrigger(reasonPrefix)
  local kind, trigName = readTriggerMode()
  if not kind then return false end
  if kind == 'manual' then
    if state.phase == 'manual_telemetry' and state.runKind == 'manual' then
      clearTriggers()
      return false
    end
    -- If an AI run is mid-flight, stop AI and flip to telemetry-only without full relaunch.
    if state.aiStarted or state.phase == 'learning' or state.phase == 'racing'
        or state.phase == 'start_ai' or state.phase == 'arming' then
      clearTriggers()
      local veh = getPlayerVeh()
      enterManualTelemetry(veh, (reasonPrefix or 'trigger') .. ' — hot-switch from AI via ' .. tostring(trigName))
      return true
    end
    beginSequence((reasonPrefix or 'trigger') .. ' via ' .. tostring(trigName), 'manual')
    return true
  end
  -- auto
  if state.runKind == 'manual' and state.phase == 'manual_telemetry' then
    -- ignore auto trigger while user is mid manual session unless they relaunch
    clearTriggers()
    appendResult('ignored auto trigger while manual_telemetry active')
    return false
  end
  beginSequence((reasonPrefix or 'trigger') .. ' via ' .. tostring(trigName), 'auto')
  return true
end
-- Advance sequential checkpoint progress; arm only after most of the lap.
local function updateLapProgress(pos)
  local guard = 0
  while guard < 3 do
    guard = guard + 1
    local idx = state.nextNode
    if idx < 1 or idx > #BELASCO_SCRIPT then
      state.nextNode = 2
      break
    end
    -- While collecting checkpoints, skip finish (index 1) until armed + enter gate
    if idx == 1 then
      if state.nodesHit >= ARM_MIN_NODES then
        state.lapArmed = true
      end
      break
    end
    local n = BELASCO_SCRIPT[idx]
    local d = pos:distance(vec3(n.x, n.y, n.z))
    local hitR = (n.r or 10) + NODE_HIT_RADIUS_EXTRA
    if d <= hitR then
      state.nodesHit = state.nodesHit + 1
      local nxt = idx + 1
      if nxt > #BELASCO_SCRIPT then
        nxt = 1 -- approach finish after Checkpoint_12
      end
      state.nextNode = nxt
      if state.nodesHit >= ARM_MIN_NODES then
        state.lapArmed = true
      end
    else
      break
    end
  end
end

local function acceptFinishCross(veh, now, sinceLast)
  state.lastLapTime = now
  resetLapProgress()
  -- After accepting, require a fresh loop (start looking for Checkpoint_1)
  state.nextNode = 2
  state.nodesHit = 0
  state.insideFinish = true

  if state.mode == 'learning' then
    state.learnLap = state.learnLap + 1
    table.insert(state.learnLapTimes, sinceLast)
    appendResult(string.format('LEARN LAP %d/%d at t=%.1fs (lap=%.1fs) maxMph=%.2f violations=%d ok=%s',
      state.learnLap, LEARN_LAPS, now - state.startTime, sinceLast,
      state.learnMaxSpeedMps * MPH_PER_MPS, state.learnSpeedViolations, tostring(state.learnSpeedOk)))
    setPhase('learning', {
      learnCross = state.learnLap,
      lapSec = sinceLast,
      learnMaxSpeedMph = state.learnMaxSpeedMps * MPH_PER_MPS,
      learnSpeedOk = state.learnSpeedOk,
    })
    if state.learnLap >= LEARN_LAPS then
      beginAggressiveStint(veh)
    end
  else
    state.lap = state.lap + 1
    table.insert(state.lapTimes, sinceLast)
    appendResult(string.format('RACE LAP %d/%d at t=%.1fs (lap=%.1fs)',
      state.lap, TARGET_LAPS, now - state.raceStartTime, sinceLast))
    flushTelemetry(veh)
    setPhase('racing', { lapCross = state.lap, lapSec = sinceLast })
    if state.lap >= TARGET_LAPS then
      finishTest(nil)
    end
  end
end

local function onUpdate(dt)
  if pollStopTrigger() then return end
  if state.finished then return end
  dt = dt or 0.016

  -- Always allow a manual trigger to abort AI mid-run and flip to telemetry-only.
  if state.phase ~= 'idle' and state.phase ~= 'mission_start' and state.phase ~= 'loaded' then
    local kind = readTriggerMode()
    if kind == 'manual' and state.phase ~= 'manual_telemetry' then
      tryConsumeTrigger('update poll')
      return
    end
  end

  if state.phase == 'idle' or state.phase == 'mission_start' then
    bootTimer = bootTimer + dt
    if bootTimer > 2.0 then
      bootTimer = 0
      tryConsumeTrigger('trigger detected')
    end
    return
  end

  bootTimer = bootTimer + dt

  if not isActiveRunPhase() then
    return
  end

  local veh = getPlayerVeh()
  if not veh then
    if bootTimer > 120 and state.runKind ~= 'manual' then
      finishTest('no player vehicle')
    end
    return
  end

  -- Manual mode: keep CSV armed, AI off, no learn/race/recover automation.
  -- Manual does not run lap gates here — flush on safety timer / disarm / session end.
  if state.phase == 'manual_telemetry' or (state.runKind == 'manual' and state.phase ~= 'boot'
      and state.phase ~= 'teleport' and state.phase ~= 'arming') then
    if state.phase ~= 'manual_telemetry' then
      enterManualTelemetry(veh, 'enter manual from phase=' .. tostring(state.phase))
    end
    state.currentSpeedMps = getVehSpeed(veh)
    sampleTimer = sampleTimer + dt
    telemetryFlushTimer = telemetryFlushTimer + dt
    if telemetryFlushTimer >= MANUAL_FLUSH_SEC then
      telemetryFlushTimer = 0
      flushTelemetry(veh)
    end
    -- Slow heartbeat: re-arm every 8s so CSV stays armed across vehicle reloads;
    -- also flush so disk catches up without waiting for the 45s safety timer.
    if sampleTimer > 8.0 then
      sampleTimer = 0
      disableAi(veh)
      flushTelemetry(veh)
      armTelemetry(veh, state.telemetryIntervalSec or MANUAL_TELEMETRY_INTERVAL)
      setPhase('manual_telemetry', {
        telemetryArmed = state.telemetryArmed,
        ai = 'disabled',
        targetLaps = 4,
        telemetryIntervalSec = state.telemetryIntervalSec or MANUAL_TELEMETRY_INTERVAL,
        heartbeat = true,
      })
    end
    return
  end

  if state.phase == 'boot' and bootTimer > 3.0 then
    ensurePrefab()
    setPhase('teleport')
    local where = teleportToRacetrack(veh)
    state.teleportedOnce = true
    appendResult('teleport=' .. tostring(where))
    armTelemetry(veh)
    setPhase('arming')
    bootTimer = 0
  elseif state.phase == 'arming' and bootTimer > 4.0 then
    if state.runKind == 'manual' then
      enterManualTelemetry(veh, 'arming complete — manual telemetry only (no AI)')
      bootTimer = 0
      return
    end
    setPhase('start_ai')
    if not startAiLaps(veh) then
      finishTest(state.failReason or 'ai start failed')
    end
    bootTimer = 0
    state.lastLapTime = os.clock()
    armLapGrace(LAP_ARM_GRACE_SEC)
  end

  if state.aiStarted and not state.finished and state.runKind ~= 'manual' then
    -- After recover / learn→race transition, re-enable AI
    if state.needReenableAi then
      state.reenableTimer = state.reenableTimer + dt
      if state.reenableTimer >= REENABLE_DELAY then
        state.needReenableAi = false
        state.reenableTimer = 0
        local lapsLeft
        if state.pendingRaceAi or state.mode == 'racing' then
          state.pendingRaceAi = false
          state.mode = 'racing'
          state.aggression = RACE_AGGRESSION
          lapsLeft = math.max(1, TARGET_LAPS - state.lap + 1)
          queueAiDrive(veh, RACE_AGGRESSION, lapsLeft, { learn = false })
          if state.raceStartTime <= 0 then state.raceStartTime = os.clock() end
          setPhase('racing', { aiReenabled = true })
          appendResult(string.format('AI re-enabled racing aggression=%.2f lapsLeft=%d', RACE_AGGRESSION, lapsLeft))
        else
          lapsLeft = math.max(1, LEARN_LAPS - state.learnLap + 2)
          queueAiDrive(veh, LEARN_AGGRESSION, lapsLeft, { learn = true })
          setPhase('learning', { aiReenabled = true })
          appendResult(string.format('AI re-enabled SLOW LEARN cap=10mph aggression=%.2f', LEARN_AGGRESSION))
        end
        armTelemetry(veh)
      end
    end

    sampleTimer = sampleTimer + dt
    if sampleTimer > 5.0 then
      sampleTimer = 0
      armTelemetry(veh)
      setPhase(state.mode == 'learning' and 'learning' or 'racing')
    end

    -- Learn-phase speed cap: track + reinforce AI limit; soft-brake if overshoot
    if state.mode == 'learning' and not state.needReenableAi then
      learnSpeedPollTimer = learnSpeedPollTimer + dt
      local speed = getVehSpeed(veh)
      state.currentSpeedMps = speed
      -- Ignore physics spikes from teleport / reset (can be thousands of m/s for 1 frame)
      if speed <= LEARN_SPEED_SAMPLE_MAX and os.clock() >= state.lapGraceUntil then
        if speed > state.learnMaxSpeedMps then
          state.learnMaxSpeedMps = speed
        end
      elseif speed > LEARN_SPEED_SAMPLE_MAX then
        -- Physics spike (teleport/reset) — never let it poison learnMax
        if state.learnMaxSpeedMps > LEARN_SPEED_SAMPLE_MAX then
          state.learnMaxSpeedMps = 0
        end
      end
      if learnSpeedPollTimer >= 0.5 then
        learnSpeedPollTimer = 0
        if speed > LEARN_MAX_SPEED_MPS * 1.05 and speed <= LEARN_SPEED_SAMPLE_MAX then
          state.learnSpeedViolations = state.learnSpeedViolations + 1
          state.learnSpeedOk = false
          veh:queueLuaCommand(string.format([[
            ai.setSpeed(%s)
            ai.setSpeedMode('limit')
            ai.setAvoidCars('on')
          ]], tostring(LEARN_MAX_SPEED_MPS)))
          if state.learnSpeedViolations <= 3 or (state.learnSpeedViolations % 10) == 0 then
            appendResult(string.format('LEARN SPEED CAP hit mph=%.1f (cap=10) viol=#%d',
              speed * MPH_PER_MPS, state.learnSpeedViolations))
          end
        elseif speed > LEARN_SPEED_ENFORCE_MPS and speed <= LEARN_SPEED_SAMPLE_MAX then
          veh:queueLuaCommand(string.format([[
            ai.setSpeed(%s)
            ai.setSpeedMode('limit')
          ]], tostring(LEARN_MAX_SPEED_MPS)))
        end
      end
    elseif state.mode == 'racing' then
      state.currentSpeedMps = getVehSpeed(veh)
    end

    -- Damage / stuck / off-track recovery
    recoverPollTimer = recoverPollTimer + dt
    if recoverPollTimer > 1.0 and not state.needReenableAi then
      recoverPollTimer = 0
      local damage = getVehDamage(veh)
      local speed = getVehSpeed(veh)
      state.currentSpeedMps = speed
      local pos = veh:getPosition()
      local nearDist = distToScriptPolyline(pos or BELASCO_FINISH)
      local stuckSpd = (state.mode == 'learning') and STUCK_SPEED_LEARN or STUCK_SPEED
      local stuckTime = (state.mode == 'learning') and STUCK_TIME_LEARN or STUCK_TIME
      local offDist = (state.mode == 'learning') and OFFTRACK_DIST_LEARN or OFFTRACK_DIST

      if damage >= DAMAGE_RESET_THRESHOLD then
        recoverVehicle(veh, string.format('damage=%.0f', damage))
      elseif speed < stuckSpd then
        state.stuckTimer = state.stuckTimer + 1.0
        if state.stuckTimer >= stuckTime then
          recoverVehicle(veh, string.format('stuck speed=%.1f offtrack=%.0f', speed, nearDist))
        end
      else
        state.stuckTimer = 0
      end

      -- Off-track vs densified polyline; learn uses wider gate + only when nearly stopped
      local offtrackSpeedGate = (state.mode == 'learning') and 0.8 or 8.0
      if nearDist > offDist and speed < offtrackSpeedGate then
        recoverVehicle(veh, string.format('offtrack dist=%.0f', nearDist))
      end
    end

    -- Closed-loop lap gate: sequential checkpoints + finish hysteresis + min time
    lapPollTimer = lapPollTimer + dt
    if lapPollTimer > 0.25 then
      lapPollTimer = 0
      local pos = veh:getPosition()
      local now = os.clock()
      if pos then
        local d = pos:distance(BELASCO_FINISH)
        state.lastDist = d

        if now >= state.lapGraceUntil then
          updateLapProgress(pos)

          -- Hysteresis around finish / script node 0
          if state.insideFinish then
            if d > FINISH_EXIT_M then
              state.insideFinish = false
              -- Passed start/finish without scoring — keep collecting from Checkpoint_1
              if state.nextNode == 1 then
                state.nextNode = 2
              end
            end
          elseif d < FINISH_ENTER_M then
            local sinceLast = now - (state.lastLapTime > 0 and state.lastLapTime or state.startTime)
            local minSec = (state.mode == 'learning') and MIN_LEARN_LAP_SEC or MIN_RACE_LAP_SEC
            if not state.lapArmed or state.nodesHit < ARM_MIN_NODES then
              appendResult(string.format(
                'IGNORED finish (not armed nodes=%d/%d next=%d dist=%.0f) mode=%s',
                state.nodesHit, ARM_MIN_NODES, state.nextNode, d, tostring(state.mode)))
              state.insideFinish = true
              state.nextNode = 1
            elseif sinceLast < minSec then
              appendResult(string.format(
                'IGNORED finish cross (%.1fs < min %.0fs) nodes=%d mode=%s',
                sinceLast, minSec, state.nodesHit, tostring(state.mode)))
              state.insideFinish = true
            else
              acceptFinishCross(veh, now, sinceLast)
            end
          end
        end
      end
    end

    -- Safety timeout (~75 min wall: slow learn can be 15–25 min + 10 race laps)
    if state.startTime > 0 and (os.clock() - state.startTime) > 4500 then
      finishTest('timeout')
    end
  end
end

local function onWorldReadyState(ready)
  if ready ~= 2 then return end
  if isActiveRunPhase() then
    appendResult('world ready — keeping active phase=' .. tostring(state.phase))
    return
  end
  if not tryConsumeTrigger('world ready') then
    setPhase('idle')
  end
end

local function onExtensionLoaded()
  setPhase('loaded')
  log('I', logTag, 'Loaded West Coast Belasco lap test (auto AI + manual telemetry; vehicle via trigger profile)')
  log('I', logTag, 'Triggers: RUN_WC_MANUAL_TEL=manual | RUN_WC_GT4_TEST=auto; body keys: profile=kingsnake|scintilla|vehicle=...|telemetryCsv=...')
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onWorldReadyState = onWorldReadyState
M.onTelemetryArmResult = onTelemetryArmResult
M.onClientStartMission = function()
  if isActiveRunPhase() then
    appendResult('mission start — keeping active phase=' .. tostring(state.phase))
    return
  end
  if not tryConsumeTrigger('mission start') then
    setPhase('mission_start')
  end
end

return M
