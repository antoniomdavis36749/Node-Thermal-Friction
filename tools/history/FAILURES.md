# Failures

Attempts that missed, and defects that must not come back. Add a row at the top when a live run rejects a change. A soft-sim PASS does not clear a row.

| Date | What was tried | What happened | Do not |
| --- | --- | --- | --- |
| 2026-09-26 | Read the 22 km Corse street run from a CSV. | Telemetry was armed at `Node-Thermal-Friction-dev`, which is not the loaded folder. The run left a Pitwall screenshot and no file. | Arm the log on a folder BeamNG is not running. The live copy is `Node-Thermal-Friction-work`. |
| 2026-09-26 | Use native rubber °C as the Node-Thermal grip temperature. | On the 26.8 km Corse log, native tread started at 15°C while Node-Thermal bands were already 37–39°C, then sat about 10°C cooler in the steady window, and flashed hotter than Node-Thermal on the driven rears at the end. | Feed native °C into the locked grip bands. It stays a second thermometer until a dedicated bypass test. |
| 2026-09-10 area | Path A6 as the Soft C4 heat pin. | 4-lap still about 58/69/72/76°C against opt 82 after the patch-fraction edits. | Stack more Path A on Soft to chase that pin. |
| 2026-09-10 area | Skin retention via track conductivity 1.15→0.88, then 0.88→0.75. | Clean Track ~15°C still left the front near 58°C. | Use track conduction as the front-window lever on that protocol. |
| 2026-09-10 area | Static cool 0.076→0.060. | FR still about 55–60°C at Track 15°C. Static cool is a small fraction of on-track speed cool. | Cut static cool again to warm a cruising front. |
| 2026-09-26 | Trust a soft-sim PASS for Phase 2. | `tools/scripts` still score the removed chassis-G terms and the old mass gates. | Treat those PASS lines as the live car. |
| 2026-09-26 | Enable the street residual-slip soft-cap to cool FWD exits. | The cap is off because turning it on cools driven street tires against every calibrated band. | Enable it inside the layout-damp A/B. It needs its own card. |
| — | Read `wd.brakeTorque` as the torque being applied. | That field is brake capacity. The drive-heat gate stayed open and brake wear ran whenever the car moved. Phase 1 locked `brakingTorque`. | Restore the capacity read. |
| — | Let chassis G pick the shoulder, blister abuse, or a convection bonus. | The two G shoulder terms disagreed left to right. Phase 2 removed them. | Put chassis G back into shoulder, blister, or convection. |
| — | Scale wear and drive gates by vehicle mass. | A front-heavy car and a light car did not match the tire in contact. Phase 2 uses the tire's own static load. | Put vehicle mass back into those gates. |
| — | Turn brake lock-fade back on so a no-ABS car locks. | Lock belongs to BeamNG. | Re-enable `ENABLE_BRAKE_LOCK_FADE` as that fix. |
| — | Run Node-Thermal grip and a second node-wear mod together. | Two absolute friction writers. Policy A forbids it. | Add another `setFrictionThermalSensitivity` writer. |

Pitwall sometimes throws an Angular `$rootScope:infdig` digest loop. That is a UI watcher loop. It is not a tire-physics failure and it is not an architecture-stage failure.
