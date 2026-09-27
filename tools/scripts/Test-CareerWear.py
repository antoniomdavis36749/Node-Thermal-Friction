"""Player-car wear save and restore, using the real thermal module."""
from __future__ import annotations

import sys
from pathlib import Path

import lupa

ROOT = Path(__file__).resolve().parents[1].parent
LUA = ROOT / "lua" / "vehicle" / "extensions" / "auto" / "tireWearThermals.lua"
EXT = ROOT / "lua" / "vehicle" / "extensions"


def boot(seated: bool):
    ext = str(EXT).replace("\\", "/")
    lua_file = str(LUA).replace("\\", "/")
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().print = lambda *a: None
    seated_s = "true" if seated else "false"
    lua.execute(
        f"""
package.path = package.path .. ";{ext}/?.lua"
obj = {{}}
function obj:getYawAngularVelocity() return 0 end
function obj:getID() return 1 end
electrics = {{ values = {{}} }}
v = {{ data = {{ model = "scintilla" }}, config = {{ itemId = 42 }} }}
playerInfo = {{ firstPlayerSeated = {seated_s} }}
guihooks = {{}}
FS = {{ directoryCreate = function() end }}
_wear = nil
_wearPath = nil
function jsonWriteFile(path, obj)
  _wearPath = path
  _wear = obj
  return true
end
function jsonReadFile(path)
  if path == _wearPath then return _wear end
end
wheels = {{ wheelRotators = {{ [0] = {{
  name = "RR", radius = 0.33, tireWidth = 0.25, pressure = 32,
  treadCoef = 0.5, softnessCoef = 0.8, hubRadius = 0.2,
  downForce = 4000, lastSlip = 0, lastSideSlip = 0, slipEnergy = 0,
  angularVelocity = 0, propulsionTorque = 0, brakingTorque = 0, brakeTorque = 2000,
  wheelSpeed = 0, dynamicRadius = 0.33, peakForce = 4000, contactDepth = 0,
  contactMaterialID1 = 1,
}} }} }}
"""
    )
    mod = lua.eval(f'function() return assert(loadfile("{lua_file}"))() end')()
    lua.execute("M = ...", mod)
    return lua


def read_scalar(lua):
    return lua.eval(
        """function()
  local td
  local i = 1
  while true do
    local name, value = debug.getupvalue(M.updateGFX, i)
    if not name then break end
    if name == "tyreData" then td = value break end
    i = i + 1
  end
  local _, F = debug.getupvalue(M.updateGFX, 1)
  local data = td[0]
  return data.scalarTreadCondition or -1, data.nodeWearPeak or -1, F.careerWearPath()
end"""
    )()


def main() -> int:
    fail = 0
    lua = boot(True)
    lua.eval("function() M.onInit() end")()
    lua.eval(
        """function()
  local td
  local i = 1
  while true do
    local name, value = debug.getupvalue(M.updateGFX, i)
    if not name then break end
    if name == "tyreData" then td = value break end
    i = i + 1
  end
  td[0].scalarTreadCondition = 82.5
  td[0].nodeWearPeak = 0.15
  td[0].zoneCondition = {90, 88, 91}
  local _, F = debug.getupvalue(M.updateGFX, 1)
  F.careerWearSave()
  td[0].scalarTreadCondition = 100
  td[0].nodeWearPeak = 0
  F.careerWearLoad()
end"""
    )()
    scalar, peak, path = read_scalar(lua)
    print(f"restored scalar={scalar} peak={peak} path={path}")
    if abs(float(scalar) - 82.5) > 1e-6 or abs(float(peak) - 0.15) > 1e-6:
        print("FAIL: player wear did not restore")
        fail += 1
    if "item42" not in str(path):
        print("FAIL: career item id was not the file key")
        fail += 1

    lua.eval(
        """function()
  playerInfo.firstPlayerSeated = false
  local _, F = debug.getupvalue(M.updateGFX, 1)
  local td
  local i = 1
  while true do
    local name, value = debug.getupvalue(M.updateGFX, i)
    if not name then break end
    if name == "tyreData" then td = value break end
    i = i + 1
  end
  td[0].scalarTreadCondition = 10
  F.careerWearSave()
  td[0].scalarTreadCondition = 100
  playerInfo.firstPlayerSeated = true
  F.careerWearLoad()
end"""
    )()
    scalar, peak, _path = read_scalar(lua)
    if abs(float(scalar) - 82.5) > 1e-6:
        print(f"FAIL: a non-player save overwrote the file ({scalar})")
        fail += 1
    else:
        print("OK: traffic save left the player file alone")

    lua.eval("function() M.onReset() end")()
    scalar, _peak, _path = read_scalar(lua)
    if abs(float(scalar) - 100) > 1e-6:
        print(f"FAIL: reset did not start fresh ({scalar})")
        fail += 1
    else:
        print("OK: reset starts the tires fresh")

    if fail:
        print(f"OVERALL: FAIL - {fail}")
        return 1
    print("OVERALL: PASS - player wear persists, traffic does not write, reset starts fresh.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
