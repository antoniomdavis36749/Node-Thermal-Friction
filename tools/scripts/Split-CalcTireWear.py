#!/usr/bin/env python3
"""Split F.CalcTyreWear into thermals + wear helpers with ctw scratch bridging."""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Fields wear helper must read from ctw (set by thermals helper)
CTW_WEAR_FIELDS = [
    "avgWeightedTemp",
    "current_optimal_temp",
    "current_working_temp",
    "tempDistWeighted",
    "isAirborne",
    "loadRaw",
    "slipEnergy",
    "sideSlipEnergy",
    "tyreWidthCoeff",
    "propulsionTorque",
    "brakeTorque",
    "angularVel",
    "wearRate",
    "coldWearMult",
    "hotWearMult",
    "bottomOutSens",
    "wLeft",
    "wCenter",
    "wRight",
    "casing_compliance",
    "contactDepth",
    "rawJBeamTread",
    "gmName",
    "treadCoef",
    "grainTempRatio",
    "blisterTempRatio",
    "tyreWidth",
    "isRaining",
    "isWetSurface",
    "isDryPaved",
    "isLooseSurface",
    "isMudSurface",
    "isSnowSurface",
    "isSandSurface",
    "isGravelSurface",
    "isDirtGrassSurface",
    "isIceSurface",
    "vehNotParked",
    # surface flags table ref
    "sf",
]


def main() -> int:
    path = Path(sys.argv[1])
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

    fn_start = fn_end = split = None
    for i, l in enumerate(lines):
        if l.startswith("F.CalcTyreWear = function"):
            fn_start = i
        if fn_start is not None and fn_end is None and i > fn_start:
            if l.rstrip() == "end" and i + 2 < len(lines) and "COMPRESSED LOOKUP" in lines[i + 2]:
                fn_end = i
                break
    for i in range(fn_start, fn_end):
        if "HEAT CYCLES: compound hardens" in lines[i]:
            split = i
            break

    early = ens = mods = None
    for i in range(fn_start, split):
        if "if not wd or not w or not data then return end" in lines[i]:
            early = i
        if "data.temp = F.ensureTempNodes" in lines[i]:
            ens = i
        if "local mods = data.interpolatedMods" in lines[i]:
            mods = i

    assert all(x is not None for x in (fn_start, fn_end, split, early, ens, mods))

    # Thermals body: from after mods line through line before HEAT CYCLES
    # Include groundModel/trackTemp/isAirborne which are before mods
    thermals_inner = lines[ens + 1 : split]  # blank + groundModel... through before HEAT CYCLES
    # Remove the mods line from thermals_inner if present (mods is a parameter)
    filtered = []
    for l in thermals_inner:
        if "local mods = data.interpolatedMods" in l:
            continue
        filtered.append(l)
    thermals_inner = filtered

    wear_inner = lines[split:fn_end]

    # Store bridge values at end of thermals (before wear)
    store_lines = ["\n", "    -- Bridge locals into ctw scratch for wear helper (Lua local-cap)\n"]
    for f in CTW_WEAR_FIELDS:
        store_lines.append(f"    ctw.{f} = {f}\n")

    # Load bridge at start of wear
    load_lines = ["    -- Reload bridged thermals state from ctw scratch\n"]
    for f in CTW_WEAR_FIELDS:
        load_lines.append(f"    local {f} = ctw.{f}\n")
    load_lines.append("\n")

    indent = "    "
    thermals_fn = (
        ["-- CalcTyreWear thermal integration (own local scope for ~200-cap headroom)\n",
         "F.ctwIntegrateThermals = function(wheelID, dt, localEnvTemp, wd, w, data, mods)\n"]
        + thermals_inner
        + store_lines
        + ["end\n", "\n"]
    )

    wear_fn = (
        ["-- CalcTyreWear wear / damage / pressure (own local scope)\n",
         "F.ctwIntegrateWear = function(wheelID, dt, localEnvTemp, wd, w, data, mods)\n"]
        + load_lines
        + wear_inner
        + ["end\n", "\n"]
    )

    wrapper = [
        "F.CalcTyreWear = function(wheelID, dt, localEnvTemp)\n",
        "    local wd = wheels.wheelRotators[wheelID]\n",
        "    local w = wheelCache[wheelID]\n",
        "    local data = tyreData[wheelID]\n",
        "    if not wd or not w or not data then return end\n",
        "\n",
        "    localEnvTemp = localEnvTemp or ENV_TEMP\n",
        "    dt = dt or 0.01\n",
        "    data.temp = F.ensureTempNodes(data.temp, localEnvTemp)\n",
        "\n",
        "    local mods = data.interpolatedMods or DEFAULT_MODS\n",
        "    F.ctwIntegrateThermals(wheelID, dt, localEnvTemp, wd, w, data, mods)\n",
        "    F.ctwIntegrateWear(wheelID, dt, localEnvTemp, wd, w, data, mods)\n",
        "end\n",
    ]

    scratch = [
        "-- CalcTyreWear scratch: cross-helper state (Lua ~200 local-cap)\n",
        "local ctw = {}\n",
        "\n",
    ]

    new_block = scratch + thermals_fn + wear_fn + wrapper

    out = lines[:fn_start] + new_block + lines[fn_end + 1 :]
    path.write_text("".join(out), encoding="utf-8")
    print(f"Split CalcTyreWear @ {fn_start+1}-{fn_end+1} -> thermals+wear+wrapper")
    print(f"  thermals lines: {len(thermals_inner)}, wear lines: {len(wear_inner)}")
    print(f"  bridged fields: {len(CTW_WEAR_FIELDS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
