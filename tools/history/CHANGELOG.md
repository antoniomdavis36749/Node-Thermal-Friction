# Changelog

What landed. This is not a lock list and it is not a failure list. Locks go in `LOCKS.md`. Rejected attempts go in `FAILURES.md`.

Add a row at the top when a change loads, a smoke is accepted, or a log is retrieved. One claim per row.

| Date | What landed | Evidence | Maturity |
| --- | --- | --- | --- |
| 2026-09-26 | Public source moved to 0.2.2 on `main`. Per-tire gates, stick-flex fade, layout damp on, player wear file, NodeProbe omitted from the release zip. Locked scales unchanged. | This tree. BeamNG resource zip is a separate upload. | Source |
| 2026-09-26 | Player-car wear persists across sessions. File is `settings/ntf-player-wear/<id>.json`. Career item id is the key when the vehicle has one. Traffic does not write it. Reset stores a fresh tire. | `Test-CareerWear.ps1` PASS. | Coded |
| 2026-09-26 | NodeProbe is left out of the release zip. The working copy still loads it. The packed module loads without the probe files. | `NodeThermalFriction.zip` has no NodeProbe entries. Working-copy probe install still present. | Packed |
| 2026-09-26 | Golden outputs for the locked bands, taken from the real thermal module. Stick flex, drag grip, damp scales, scalar life, node wear, the camber ladder, and the 0.70 grip floor. A move fails the check. No number was edited. | `tools/golden/locked-bands.txt`. `Test-LockedBandGolden.ps1` PASS, 49 lines. | Harness |
| 2026-09-26 | Real thermal module ran outside the game on the recorded slip-ratio log. Every ratio above 0.30 produced stick flex 0. The full window still produced it. No locked number moved. | `Test-ReplayRecordedThermal.ps1` on `stick-flex-drift-telemetry.csv`. 472 high, 0 leaked. | Harness |
| 2026-09-26 | Soft-sim gates follow the live tire. Vehicle mass and chassis G no longer scale drive heat, corner heat, or shoulder bias. Street slip cap stays off. Locked numbers were not moved. | `Test-CornerLoadHeat.ps1`, `Test-DriveHeatMatrix.ps1`, `Test-FwdDriveHeatEdge.ps1`, `Test-SetupGeometryMatrix.ps1` passed. | Soft-sim |
| 2026-09-26 | Drag launches held. Burnside `meo_drag_a`, 2.5 km, two spin-ups on the 8.6 psi axle. Long grip about 1.50. Middles flashed 72°C and 80°C. Scalar 100, node about 98, blister 0. `longGripMult` 1.18 unchanged. | `stick-flex-drift-telemetry.csv` Drag stint. Quarter-mile achievement in `beamng.log`. | Logged |
| 2026-09-26 | Stick-flex fade confirmed. Sport drift, 2.1 km, layout damp on. Driven rears: every sample with slip ratio above 0.30 had `stickFlex` 0 (88 and 90 samples). The term fell through 0.12–0.30, then stopped. Rear middle peaks 99°C and 103°C. Window and gain 0.22 unchanged. | `stick-flex-drift-telemetry.csv`. | Logged |
| 2026-09-26 | Sport drift, 1.9 km, layout damp on. Rears peaked at 104°C and 103°C middle and ended near 72–77°C. Fronts stayed mostly undriven, peaks 56°C and 70°C. No blister. Rear node wear about 8–9%. Scalar life still about 100%. Stick flex and slip ratio were not in this file. | `layout-damp-off-telemetry.csv` last stint. | Smoked, fade not measured |
| 2026-09-26 | Layout-damp A/B closed. Switch returned to on. Medium slick FWD, 11.1 km, damp off: fronts Hot, rears Cold. | `layout-damp-off-telemetry.csv` last stint. Pitwall at 11.16 km. | Smoked |
| 2026-09-26 | Stage 5 HUD diet. Player stream omits probe, slip, suspension, and heat-knob fields. Pitwall uses `TireWearThermalsPitwall` and still receives the full payload. | Burnside drag spawn printed `ARCH stage 5 OK layoutDamp=1`. | Loaded |
| 2026-09-26 | Stage 4 heat smoke. Sport Plus street, last stint 9.2 km in `layout-damp-off-telemetry.csv`. Middles peaked about 63°C front and 54–59°C rear, then cooled into the low 40s at the stop. `layoutDamp` stayed 0. Duty included `verify_layout_damp_off`. | CSV plus Pitwall at the stop. Not the FWD exit card. | Smoked |
| 2026-09-26 | History comments removed from Lua. Locks, failures, and landed rounds stay in `tools/history/`. Comments that remain state a rule the next edit has to see. | This changelog, `LOCKS.md`, `FAILURES.md`. | Written |
| 2026-09-26 | Stage 3 heat sources. `ctwAccumulateHeat` stores slip, work, brake, and flex energy and does not write `data.temp`. | Two Scintilla loads printed `ARCH stage 3 OK layoutDamp=0`. No missing-function line. | Loaded |
| 2026-09-26 | Stage 2 sensor split. `ctwSenseThermal` reads rates and wheel samples. Prepare still applies underwater cooling, draft, and the wear-contract writes. | Vehicle log: `ARCH stage 2 OK layoutDamp=0`. | Loaded |
| 2026-09-26 | Stage 1 architecture load check. | Scintilla log: `ARCH stage 1 OK layoutDamp=0`. | Loaded |
| 2026-09-26 | Layout damp switch set off for the FWD exit A/B. Scales stay 0.58/0.48 and 0.45/0.38. | `driveLayoutDampEnable = false`. The exit is not driven. | Armed |
| 2026-09-26 | Street log armed, then moved to its own file. Columns include `stintKm`, scalar and node condition, node wear, native tread and core, `layoutDamp`. | `tools/output/corse-street-bank-telemetry.csv` through 26.8 km. Later samples go to `layout-damp-off-telemetry.csv`. | Logged |
| 2026-09-26 | Balanced Corse native-temp config. Sport Plus 245/30R20 and 305/30R20 with native heat coefficients on. Pressure does not follow temperature. | `amd_customs_scintilla_corse_localtest`. Balanced, High DF, and Quali were not replaced. | Probe |
| 2026-09-26 | 26.8 km Corse street run, Sport Plus, dry. Both temperatures plateaued by 10 km. Front node wear about 0.9% per km, rear about 0.23% per km. Scalar life stayed above 99.8%. | CSV above. Pitwall at 27.7 km matched the last flushed row within the flush lag. | Logged |
| 2026-09-26 | Phase 2 tire-normalized inputs in the working copy. Not committed. | GT3 smoke natural. FWD hard exit with damps on: small drive-tire bump, like RWD. | Smoked |
| 2026-09-26 | Phase 1 native API correctness. | Commit `7ba52de`. See `LOCKS.md`. | Locked |
| 2026-09-26 | Verification card, documentation index, and these history files. | `tools/VERIFICATION.md`, `tools/DOCUMENTATION.md`, `tools/history/`. | Written |
| 2026-09-10 | Heat rates reopened on the cornering axis for Sport, Sport Plus, Track Day, and slicks. Wear and scalar locks held. | `tools/README.md` WCU notes. | Landed, heat open |
| 2026-08-30 | Drag long, wet asphalt, street cruise heat, and the camber ladder closed. | `LOCKS.md` and `tools/V2_NODE_WEAR_SPIKE.md`. | Locked |

Older round-by-round heat notes remain in `tools/README.md` and in Lua comments. New rounds go here first.
