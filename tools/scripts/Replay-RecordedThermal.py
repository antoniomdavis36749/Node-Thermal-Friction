"""Run the real thermal module outside BeamNG on a recorded CSV.

Feeds each logged slip ratio into the live stick-flex path. Above 0.30 the
extra heat must be zero. At least one sample at or below 0.12 must still
produce it. Does not retune locked numbers.
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import lupa

ROOT = Path(__file__).resolve().parents[1].parent
CSV_PATH = ROOT / "tools" / "output" / "stick-flex-drift-telemetry.csv"
LUA_PATH = ROOT / "lua" / "vehicle" / "extensions" / "auto" / "tireWearThermals.lua"
EXT_DIR = ROOT / "lua" / "vehicle" / "extensions"


def main() -> int:
    if not CSV_PATH.is_file():
        print(f"FAIL: recorded log missing: {CSV_PATH}")
        return 1
    ext = str(EXT_DIR).replace("\\", "/")
    lua_file = str(LUA_PATH).replace("\\", "/")
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().print = lambda *args: print("LUA", *args)
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
    step = lua.eval(
        """function(ratio)
  local wd = wheels.wheelRotators[0]
  wd.lastSlip = ratio * 3.0
  wd.lastSideSlip = 10
  M.updateGFX(0.02)
  local td
  local i = 1
  while true do
    local name, value = debug.getupvalue(M.updateGFX, i)
    if not name then break end
    if name == "tyreData" then td = value break end
    i = i + 1
  end
  local data = td and td[0]
  if not data then return -1, -1 end
  return data.lastSlipRatio or -1, data.lastStickFlexHeat or -1
end"""
    )
    lua.eval("function() M.onInit() end")()

    high = 0
    high_bad = 0
    low_alive = 0
    worst = 0.0
    rows = 0
    with CSV_PATH.open(encoding="utf-8", errors="replace", newline="") as handle:
        for row in csv.DictReader(handle):
            raw = row.get("slipRatio")
            if raw in (None, ""):
                continue
            ratio = float(raw)
            got_ratio, flex = step(ratio)
            rows += 1
            flex = float(flex)
            if ratio > 0.30:
                high += 1
                if flex > 1e-4:
                    high_bad += 1
                    worst = max(worst, flex)
            elif ratio <= 0.12 and flex > 1e-4:
                low_alive += 1

    print(f"rows={rows} above_0.30={high} flex_leaked={high_bad} low_window_alive={low_alive}")
    if rows < 100:
        print("FAIL: recorded log did not yield enough slip-ratio rows")
        return 1
    if high_bad:
        print(f"FAIL: real stick flex was {worst:.4f} on a recorded ratio above 0.30")
        return 1
    if low_alive < 1:
        print("FAIL: real stick flex stayed zero inside the full window")
        return 1
    print("OVERALL: PASS - real thermal Lua, recorded slip ratios, fade holds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
