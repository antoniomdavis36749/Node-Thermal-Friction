# Verification

Index of which file owns each claim: `DOCUMENTATION.md`. After a drive, add a row to `history/CHANGELOG.md`. A lock also goes in `history/LOCKS.md`. A rejected change goes in `history/FAILURES.md`.

Read this before a drive, a retune, or calling a pass done. Maturity belongs to one claim. A whole phase can be smoked while one flag inside it is still only coded.

## Ladder

1. **Coded.** It loads. It decides nothing.
2. **Soft-sim.** A script PASS. The gate scripts follow the live per-tire gates. `Test-ReplayRecordedThermal.ps1` runs the real thermal module outside the game. A script PASS is still not a drive verdict.
3. **Smoke.** One live drive, judged by feel. A smoke can reject a change. It cannot lock a number. The GT3 is smoke-only for heat.
4. **Logged.** A CSV answers the question that was asked. One route cannot retune a locked band.
5. **A/B.** One switch, same car, same maneuver, against a pass you already accepted.
6. **Locked.** The number stays until that same protocol misses.

## What each step may change

- Smoke: stop, or keep going. No number edits.
- Log: answer the question on the card. No locked-number edits.
- A/B of an enable flag: keep the flag, or leave it off. The locked scales stay.
- Lock: only after the protocol that owns that number.

## You are off track if

- The open card below is undriven and you start the next item.
- Two runs differ in track temp, compound, or car, and you compare them.
- GT3 heat is treated as a verdict.
- A soft-sim PASS is treated as a live verdict.
- Native °C is fed into the Node-Thermal grip bands.
- A locked scale is nudged because a different flag's A/B felt hot.
- The layout-damp A/B is driven on plain Sport. Softness 0.8 remaps to 0.65, under the 0.72 gate, so that damp never applied.
- The log is off, or `layoutDamp` is not 0 on a damp-off run.
- The car was reset mid-stint and `stintKm` is read as the whole run.

## Open card

**Public source is on `main`.** Version 0.2.2. Do not retune `longGripMult` 1.18, stick-flex gain 0.22, or the layout-damp scales. The BeamNG website zip is a separate upload of the packer output.

## Closed cards

**Career wear.** 2026-09-26. The player car writes `settings/ntf-player-wear/<id>.json`. A career vehicle uses its item id. The same corner and tire restore scalar life, node peak, zones, grain, and blister. Traffic does not write that file. A vehicle reset starts the tires fresh and stores that fresh state. `Test-CareerWear.ps1`.

**NodeProbe stays out of the release zip.** 2026-09-26. `Pack-Release.ps1` removes the probe extension, its state file, and its controller. The packed module still loads, and `ensureNodeCollisionProbe` is absent there. The working copy still has the three files and still installs the probe.

**Locked-band golden.** 2026-09-26. `Test-LockedBandGolden.ps1` runs the real thermal module and compares 49 outputs to `tools/golden/locked-bands.txt`. Stick flex falls 11.92, 8.03, 4.05, then 0 at slip ratio 0.30. Drag long grip 1.18, grip multiplier 1.32, grip level 0.80, damp scales 0.58/0.48 and 0.45/0.38, scalar life 4.7, node-wear scales, the camber ladder, and the 0.70 grip floor are in that file. A move fails the check.

**Recorded-log replay.** 2026-09-26. The real thermal module loaded outside BeamNG and stepped every slip ratio in `tools/output/stick-flex-drift-telemetry.csv`. 472 samples above 0.30 produced stick flex 0. 9267 samples at or below 0.12 still produced it. `Test-ReplayRecordedThermal.ps1`.

**Soft-sim gate rewrite.** 2026-09-26. Drive, corner, and geometry scripts score radius × this tire's static load and wheel slip. Chassis G does not move the gate or the heat. Street slip cap stays off. `Test-CornerLoadHeat.ps1`, `Test-DriveHeatMatrix.ps1`, `Test-FwdDriveHeatEdge.ps1`, and `Test-SetupGeometryMatrix.ps1` passed.

**Drag launch.** 2026-09-26. Burnside `meo_drag_a` at the West Coast drag strip, one stint, 2.5 km, profile Drag, layout damp on. Log: `tools/output/stick-flex-drift-telemetry.csv`. The low-pressure axle (wheels 0 and 1, 8.6 psi) spun twice: slip about 2.2 at 0.02 km, then about 1.0 at 0.6 km, when the middles flashed 72°C and 80°C. Long grip stayed about 1.50 on both hits. Combined grip held at 1.30. Scalar life stayed 100. Node condition about 98. Blister 0. `longGripMult` 1.18 stays.

**Stick flex fade.** 2026-09-26. Sport drift, 2.1 km, layout damp on. Log: `tools/output/stick-flex-drift-telemetry.csv`. Driven rears (wheels 2 and 3) had 88 and 90 samples with slip ratio above 0.30. `stickFlex` was 0 on every one of them. Inside the window the term fell: rear wheel 3 mean flex about 4.0, then 1.7, then 1.1, then 0. Rear middle peaks 99°C and 103°C. Fronts stayed cooler (peaks 61°C and 66°C). Gain 0.22 and the 0.12 / 0.30 window stay.

**Layout damp stays on.** 2026-09-26. Medium slick, FWD, 11.1 km, `layoutDamp` 0. Driven fronts ran Hot (open-gate middles about 91°C and 97°C, peaks 112°C and 130°C, screen avg 108°C and 118°C against opt 90°C). Rears stayed undriven and Cold (about 47–52°C on the open gate, screen avg 68°C and 70°C). `fwd_soft_drive_damp` never appeared, so the off switch was live. The damp was holding that front heat down. Scales stay 0.58/0.48 and 0.45/0.38.

Native temperature stays a logged thermometer. The drive queue that was open for this baseline is done.
