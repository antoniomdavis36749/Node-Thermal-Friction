"""Golden outputs for the locked bands, from the real thermal module.

A locked number that moves fails this check. The script does not edit Lua.
"""
from __future__ import annotations

import sys
from pathlib import Path

import lupa

ROOT = Path(__file__).resolve().parents[1].parent
LUA_PATH = ROOT / "lua" / "vehicle" / "extensions" / "auto" / "tireWearThermals.lua"
EXT_DIR = ROOT / "lua" / "vehicle" / "extensions"
GOLDEN = ROOT / "tools" / "golden" / "locked-bands.txt"

RATIOS = (0.0, 0.12, 0.18, 0.24, 0.30, 0.31)


def load_runtime():
    ext = str(EXT_DIR).replace("\\", "/")
    lua_file = str(LUA_PATH).replace("\\", "/")
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().print = lambda *_args: None
    lua.execute(
        f"""
package.path = package.path .. ";{ext}/?.lua"
obj = {{}}
function obj:getYawAngularVelocity() return 0 end
function obj:getRollPitchYawAngularVelocity() return 0, 0, 0 end
function obj:getVelocity() return nil end
function obj:getID() return 1 end
electrics = {{ values = {{ airspeed = 0 }} }}
sensors = {{ gx = 0, gy = 0 }}
v = {{ data = {{ nodes = {{}} }} }}
guihooks = {{}}
wheels = {{ wheelRotators = {{ [0] = {{
  name = "RR", radius = 0.33, tireWidth = 0.25, pressure = 32,
  treadCoef = 0.5, softnessCoef = 0.8, hubRadius = 0.2,
  downForce = 4000, lastSlip = 0, lastSideSlip = 10, slipEnergy = 0.05,
  angularVelocity = 30, propulsionTorque = 200, brakingTorque = 0, brakeTorque = 2000,
  wheelSpeed = 12, dynamicRadius = 0.33, peakForce = 4000, contactDepth = 0,
  contactMaterialID1 = 1, node1 = 1, node2 = 2,
}} }} }}
"""
    )
    mod = lua.eval(f'function() return assert(loadfile("{lua_file}"))() end')()
    lua.execute("M = ...", mod)
    return lua


def snapshot(lua) -> list[str]:
    text = lua.eval(
        f"""function()
  M.onInit()
  local lines = {{}}
  local function add(s) lines[#lines+1] = s end
  local wd = wheels.wheelRotators[0]
  local function tyreData()
    local i = 1
    while true do
      local name, value = debug.getupvalue(M.updateGFX, i)
      if not name then return nil end
      if name == "tyreData" then return value end
      i = i + 1
    end
  end
  local function topo()
    local i = 1
    while true do
      local name, value = debug.getupvalue(M.updateGFX, i)
      if not name then return nil end
      if name == "topo" then return value end
      i = i + 1
    end
  end
  for _, asked in ipairs({{{", ".join(str(r) for r in RATIOS)}}}) do
    wd.lastSlip = asked * 3.0
    wd.lastSideSlip = 10
    M.updateGFX(0.02)
    local data = tyreData()[0]
    add(string.format("stick %.2f %.6f %.6f", asked, data.lastSlipRatio or -1, data.lastStickFlexHeat or -1))
  end
  local t = topo()
  local keys = {{
    "stickFlexGain", "stickFlexSlipRef", "stickFlexSlipRatioFull", "stickFlexSlipRatioZero",
    "gripLevelScale", "driveLayoutDampEnable", "driveStreetSlipCapEnable",
    "drivePropFwdSoftScale", "drivePropFwdSoftCarcassScale",
    "drivePropAwdSoftScale", "drivePropAwdSoftCarcassScale",
  }}
  for i = 1, #keys do
    local k = keys[i]
    local v = t[k]
    if type(v) == "boolean" then v = v and 1 or 0 end
    add(string.format("topo %s %.6f", k, tonumber(v) or -1))
  end
  local profiles = require("tireWearThermalsProfiles")
  local function point(list, tread, softness, field)
    for i = 1, #list do
      local pt = list[i]
      local treadOk = tread == nil or math.abs((pt.tread or -1) - tread) < 1e-6
      local softOk = softness == nil or math.abs((pt.softness or -1) - softness) < 1e-6
      if treadOk and softOk then
        return pt.mods[field]
      end
    end
  end
  local function prof(tag, value)
    add(string.format("profile %s %.6f", tag, tonumber(value) or -1))
  end
  prof("drag.longGripMult", profiles.STANDALONE_MODIFIERS.drag.longGripMult)
  prof("drag.gripMultiplier", profiles.STANDALONE_MODIFIERS.drag.gripMultiplier)
  prof("sport_plus.nodeWearScale", point(profiles.PROFILE_POINTS, 0.30, nil, "nodeWearScale"))
  prof("track_day.nodeWearScale", point(profiles.PROFILE_POINTS, 0.40, nil, "nodeWearScale"))
  prof("sport.nodeWearScale", point(profiles.PROFILE_POINTS, 0.50, nil, "nodeWearScale"))
  prof("standard_060.nodeWearScale", point(profiles.PROFILE_POINTS, 0.60, nil, "nodeWearScale"))
  prof("standard_070.nodeWearScale", point(profiles.PROFILE_POINTS, 0.70, nil, "nodeWearScale"))
  prof("soft_slick.scalarTreadWearScale", point(profiles.SLICK_SPECTRUM_POINTS, nil, 0.80, "scalarTreadWearScale"))
  prof("supersoft_slick.scalarTreadWearScale", point(profiles.SLICK_SPECTRUM_POINTS, nil, 0.875, "scalarTreadWearScale"))
  local seen = {{}}
  local constSeen = {{}}
  local function harvest(fn)
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    local i = 1
    while true do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if type(value) == "number" and (name:sub(1, 7) == "CAMBER_" or name == "SCALAR_GRIP_FADE_FLOOR") then
        if not constSeen[name] then
          constSeen[name] = true
          add(string.format("const %s %.6f", name, value))
        end
      elseif type(value) == "function" then
        harvest(value)
      end
      i = i + 1
    end
  end
  local _, F = debug.getupvalue(M.updateGFX, 1)
  harvest(F.CalculateTyreGrip)
  harvest(require("tireWearThermalsNodeWear").install)
  table.sort(lines)
  return table.concat(lines, "\\n")
end"""
    )()
    return str(text).splitlines()


def main() -> int:
    lines = snapshot(load_runtime())
    if "--write" in sys.argv:
        GOLDEN.parent.mkdir(parents=True, exist_ok=True)
        GOLDEN.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"Wrote {GOLDEN} ({len(lines)} lines)")
        return 0
    if not GOLDEN.is_file():
        print(f"FAIL: golden file missing: {GOLDEN}")
        return 1
    golden = [ln for ln in GOLDEN.read_text(encoding="utf-8").splitlines() if ln.strip()]
    if lines != golden:
        live = set(lines)
        old = set(golden)
        print("FAIL: locked-band outputs moved")
        for row in sorted(old - live):
            print(f"  golden {row}")
        for row in sorted(live - old):
            print(f"  live   {row}")
        return 1
    print(f"OVERALL: PASS - {len(lines)} locked-band outputs match the golden file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
