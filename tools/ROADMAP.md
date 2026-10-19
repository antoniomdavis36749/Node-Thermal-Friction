# Roadmap

The forward plan to a finished mod, written as tasks another agent can pick up. This file owns the task list and its order. It does not own a number, a lock, a band label, or the open drive. Those stay in `VERIFICATION.md`, `history/LOCKS.md`, and `SPECTRA_STATUS.md`. When a task lands, add the CHANGELOG row, tick the task here, and correct the owner file in the same edit.

Reviewed 2026-10-11.

## Where the mod stands

**Code and branches**

- Private `testing/main` is at `fc8dd20`, the axle-scale commit. Not committed yet: rear flex and rear soak back to 1, medium rolling 2.5, the ETK K native-race test config under `vehicles/etkk/`, and doc edits. They stay local until a lock, or until the user asks.
- Public `main` on Node-Thermal-Friction is 0.2.3. Repo listings are core 39082 and compat 39083, still showing 0.2.2 until the website form is submitted.
- The compat tires repo `Node-Thermal-Friction-Tires-dev` is clean at `06bfcb8`, 2026-09-23.
- The AMD test-car mods (`mods/unpacked/amd_customs_*`) hold the voting configs and the NTF medium-slick AMD tire JBeams. None of them is in git.
- `tools/output/code-stamp.txt` sat at `3e9930e` from 10-04 until 2026-10-11, so every run in that stretch reads "differs from current code". It now reads `fc8dd20`.

**Locked** (evidence in `history/LOCKS.md`)

- Phase 1 native API, Policy A, A2 fade floor 0.70, scalar life 4.7, node-wear scales, camber ladder.
- Layout damps 0.58/0.48 and 0.45/0.38. Stick-flex fade, gain 0.22, window 0.12 to 0.30. Drag `longGripMult` 1.18.
- Street: Sport cruise, Sport Plus heat under 100°C, the wet asphalt grip path.
- Highway trailer rolling 16. Soft slick rolling 2.20 on native race tires.

**Coded, not locked**

- Front corner flex and front brake soak 1.35. Sized on one car, the Bastion Nordschleife. It still needs the two-of-three vote.
- Rear corner flex and rear brake soak back to 1.
- Soft slick brake 1.1, static cooling 0.140, flex 0.00125. These stay until a car misses the window.
- Medium rolling 2.5. Blocked on S-01.

**Not baselined on the current heat code**

- Hard slick. One GT3 smoke at rolling 1.00, cold of the window.
- Supersoft slick. No data.
- Vanilla race tire wear. It borrows the Soft C4 wear package.

**Provisional bands** (`SPECTRA_STATUS.md`): wet and winter beyond asphalt, rally, drift, truck, light truck, utility, vintage, all-terrain, mud, crawler, paddle.

## What "finished" means

1. Hard, medium, soft, and supersoft slicks, and the native race tire, each have a locked straight scale and a corner pass on the three voting cars.
2. The axle scales are locked or removed.
3. Vanilla race tires have their own wear factors. Slick scalar life is re-read on the new heat.
4. Every street and utility band is either locked or carries an honest provisional label in the HUD and the listing.
5. One tested core zip and one compat zip, packed from the same revision, are on the Repo, and the docs match them.

## Rules for agents on these tasks

- Agents cannot drive BeamNG. A task marked **Drive** needs the user at the wheel. The agent prepares the config and the read, then reads the run with `Read-NtfRun.py`.
- Follow `VERIFICATION.md` and `.cursor/rules/verification.mdc`. A soft-sim PASS is not a verdict. Locked numbers stay.
- One claim per task. Add a CHANGELOG row when it lands. Commit and push only on a lock or when the user asks. Do not change git config.
- After a code edit that a drive will test, run `python tools/scripts/Read-NtfRun.py stamp`.

## Order

1. **Now.** S-02 is logged on all three cars and they do not agree. Rolling 2.5 stays. S-03 stays closed. S-04 is the next drive: Belasco, Vivace native race, then the Sunburst. S-09 can be driven. P-03, E-01, and E-06 are coded and each still needs the drive on its card. The next seat also splits the load time (P-01) while `tools/FRAME_TIMER` is present.
2. **Then.** S-02 on the Bastion, S-03, S-05. That closes the native-race band and opens R-01, the next tester drop. S-09 can be driven. M-01 and M-02 after S-01. E-05 after H-01.
3. **Then.** S-06, S-07, W-01 drive, W-02, S-08. Then R-02 and R-03. M-04 before R-03.
4. **Last.** B-01 to B-03. E-06.

## Slick heat (critical path)

- [x] **S-01 Medium straight slip runaway.** Done 2026-10-11. The cause is on the open card. Slip starts at km 1.5, 62°C and 22.8 psi, while grip is still climbing. The native-race tire at the same psi holds slip at 0.001 under more torque. The A/B is `pressureHotWritebackEnable = false` on the same Bastion straight. It still does not block S-02. The new-fill Bastion straight `20261012-190510-18087-1` held cruise slip at 0.001 with the writeback on. Stick-flex gain 0.22 and the 0.12/0.30 window stay.
  - Evidence. Bastion GT4 Balanced, NTF medium slick AMD 345/35-19 at 21.5/20.5 psi cold, rolling 2.5, smallgrid. Run `20261011-063818-43148-3` started cold at 37.7°C. In the first half of the run the driven rear middle tracked the native-race run, about 61°C against 56°C. In the second half, rear slip ratio rose from about 0.01 to 0.10 at 71–82 m/s. Grip stayed at its 1.30 cap and drive torque stayed near 600 Nm. Stick flex rose from 2 to 12, flex heat from 8 to 23, pressure from 22.7 to 25.0 psi, and the middle from 61°C to 126°C, still climbing when the run ended. The shoulders were 86°C and 94°C. The native-race run `20261011-070059-43148-2` on the same car held slip at 0.000 at 740 Nm. Logged rear heat input was only 22% higher on medium, 36 against 29 per row, while the rise above air was about four times larger. The compounds are close: rolling × `rollingRes` is 2.63 against 2.68.
  - Suspects, most likely first. (1) The hot-pressure writeback, `pressureHotWritebackEnable` in `tireWearThermalsWear.lua` near line 401, moves native inflation with NTF temperature. (2) Stick flex reads native slip, `w.slipRatio = abs(wd.lastSlip) / max(3, groundSpeed)` in `tireWearThermalsPhysicsLoop.lua` line 174, and that can close a loop below the 0.12 full point. (3) The tire part: `softnessCoef` 0.65 and the low Bastion cold pressures against the 26.5–27 psi anchors. (4) The friction actually written for medium above 100°C.
  - The trace is on the open card. A pressure write cannot assign `lastSlip`. It can only change the next native step through `setGroupPressure`. The slip starts at +0.6 psi, which is too small to be that start.
  - The trace and the soft-sim are done. `Test-HotPressureWriteback.ps1` passes. The remaining piece is the one straight with the switch off.

- [ ] **S-02 Medium rolling 2.5 straight.** Logged, not agreed. Vivace `20261011-221340-20357-2` driven 65.1°C and 65.2°C at 74.7 m/s. Sunburst `20261011-222905-22847-1` fronts 56.7°C and 56.9°C at 76.3 m/s. Bastion `20261012-190510-18087-1` rears 56.5°C and 55.9°C at 78.0 m/s, 12.28 km, cruise slip 0.001. Two cars are about 12°C under 68.5°C. Kept at 2.5 on 2026-10-12. The 3.50 and 2.68 steps were not taken. S-03 stays closed.
  - Configs. Cold fill 25.5/25.5 on all four. Vivace `amd_customs_race_balanced`. Sunburst `amd_customs_balanced`. ETK K `amd_customs_balanced`, which does not vote. Bastion `amd_customs_gt4_balanced`. The Bastion straight was driven with the writeback on.
  - Protocol. Smallgrid, 12 km, steady at about 75–80 m/s. Roll off without wheelspin.
  - Read. Driven settled median against the 68.5°C cold edge of the medium window, 68.5–99.5°C. Undriven tires stay below the window. If the driven slip ratio climbs past about 0.03 at steady speed, the run belongs to S-01, not to a rolling step.
  - Done when. Two of the three voting cars agree. Then the CHANGELOG row and S-03.

- [ ] **S-03 Medium corner check.** Drive. After the straights agree. Belasco sizes; Hirochi and Automation confirm. Settled medians inside 68.5–99.5°C, with peaks that tip over and come back. All three Belasco runs are logged, and the Sunburst redo is `20261012-201316-306272-1`. The cold axle is the rear on the Vivace and the Sunburst, and the front on the Bastion. A rolling step to 3.70 puts the Vivace FL on the 99.5°C edge and leaves the coldest tire on each car short. About 4.4 would put the Sunburst RR on 68.5°C and the Vivace FL near 106°C. The 0.65 anchor is on a 4.44 trial as of 2026-10-12. The 0.725 anchor stays at 2.5. The point prediction puts the Vivace FL near 107°C. Sunburst at 4.44 is logged: Belasco fronts 104.3 and 93.2°C with FL over for 55 s, Hirochi fronts 103.3 and 106.7°C, Automation fronts 89.1 and 107.4°C. Rears are inside. Vivace is next. Vivace at 4.44 is logged. Belasco `20261012-211823-495275-1`, 12.5 km: 117.7, 108.3, 83.8, 77.2°C. The prediction was 107, 95, 78, 71. FL stayed over for 251 s and FR for 159 s. Hirochi `20261012-212835-503627-1`, 8.4 km: 115.3, 112.8, 82.3, 80.2°C. Automation `20261012-213733-520331-1`, 8.7 km: 103.5, 114.5, 76.7, 86.5°C. Rears are inside on all three. While the fronts were over, rolling was about 55% of the heat. Bastion at 4.44 is logged, all twelve inside on the three tracks. The 0.65 anchor is now on a 3.80 trial, fit from each tire's measured 2.5 → 4.44 move. Predicted 29 of 36 inside. The Vivace fronts stay hot. On 2026-10-13 corner flex became one scale, 0.75, on every tire. At 3.80 the Belasco point prediction is Vivace 99.5, 92.0, 75.2, 69.2; Sunburst 91.6, 82.4, 77.1, 66.6; Bastion 75.7, 67.2, 86.3, 76.8. Vivace FL is on the hot edge. Sunburst RR and Bastion FR sit just under 68.5°C. Camber scrub, standing wave, slip share, worn-tread mass, and the two radiation paths are coded. A fresh tire below 80 m/s changes only by camber scrub. Logged 2026-10-14: Vivace FL 105.5°C hot for 101 s, the other three inside. Sunburst and Bastion all inside. Sunburst is 7.84 km.

- [ ] **S-04 Front soak vote.** Drive. Can go now.
  - Corner flex is one scale, 0.75, on every tire as of 2026-10-13. The 1.35 front flex step is no longer loaded.
  - Front soak 1.35 and rear soak 1 were sized on the Bastion Nordschleife only. The Hirochi reads at front 1.35 and rear 0.74 had fronts inside (Vivace 83.8/81.3°C, Sunburst 71.8/72.5°C) and rears cold (Vivace 62.4/60.1°C, Sunburst 58.7/58.0°C). The rear soak restore to 1 has not been driven yet.
  - Drive Belasco on the Vivace and the Sunburst native-race configs at flex 0.75, front soak 1.35, rear soak 1.
  - Done when. Two of the three cars agree on front soak 1.35 and it locks, or a different front soak step is sized from the log.

- [ ] **S-05 Close the native-race band.** Agent, after S-04. Rolling 2.20 is locked. Flex scale 0.75, front soak 1.35, brake 1.1, static cooling 0.140, and flex gain 0.00125 each get a lock row once the protocol has held them. Then commit and push the private repo on `testing/main` and `main`.

- [ ] **S-06 Hard slick baseline.** Prediction is on the card, 2026-10-11. The straight is not logged.
  - Driven rise above 21°C air scales with `rollingHystScale` times `rollingRes`. The reference is soft 2.20 times 1.22, product 2.684, and the 80 m/s fit rise of 50.3°C. Hard 0.50 has `rollingRes` 0.98 and cold edge 73.4°C, so the cold-edge scale is 2.85. Hard 0.575 has `rollingRes` 1.00 and cold edge 71.0°C, so the scale is 2.67. At scale 1.0 the same ratio predicts about 39°C. The GT3 smoke at rolling 1.00 was driven 66.6°C and 65.9°C, undriven 45.8°C and 45.9°C, cold of 73.4–106.6°C. It is smoke, so it bounds the ratio and does not set the scale.
  - Drive the AMD Endurance configs on smallgrid at scale 1.0, then corners. Do not code 2.85 before that straight.

- [ ] **S-07 Supersoft baseline.** Prediction is on the card, 2026-10-11. No straight yet. Softness 0.875, `rollingRes` 1.39, no `rollingHystScale`. Cold edge 65.3°C (80 ± 14.7). The same rise-per-product as S-06 gives scale 1.70, and about 47°C at scale 1.0. Drive the Quali configs on smallgrid at scale 1.0 first.

- [ ] **S-08 Fifth-car hot rears.** Drive, later. ETK K Hirochi rears settled 114.4°C and 108.7°C, about 58% rolling. The car does not vote. This is the "cooling by car class" step, and it waits until the voters are locked.

- [ ] **S-09 Held-speed check of the 2.20 straight.** Drive. E-02 flags this run. This does not reopen the lock by itself.
  - Evidence. The lock straight `20261010-170451-133868-1` (Bastion, native race) did not hold speed. Median speed was 79.3 m/s over km 0–6, 81.4 over km 6–10, and 66.9 over km 10–16. The settled third is km 10–16, so the driven settled 67.8°C and 66.5°C were read at about 67 m/s. E-02's equal thirds on the same run are 77.4 / 81.4 / 66.3 m/s, and it flags the settled third by 15.1 m/s. A warm-up fit on the first 6 km puts the driven rears at 71.8°C and 70.8°C, and the reader withholds that fit because the speed flag is set. The undriven fronts barely move with speed: fit 54.5°C and 52.4°C against settled 54.8°C and 53.3°C.
  - Drive. The same Bastion native-race config on smallgrid, 12 km, held at 80 m/s through the settled third. Use the E-01 held-speed mode if it is ready.
  - Done when. The run passes the E-02 checks and its driven settled median is on the open card. If it is within the 2.2°C Bastion floor of 66.9°C, the lock stands. If it is further above, the record goes to the user, who decides whether the cruise goal is read at a held speed and whether 2.20 reopens through the protocol. The Belasco half of the pair, `20261010-171007-191147-2`, is a corner read and is not in question.

## Wear

- [ ] **W-01 Vanilla race tire wear.** Prediction is on the card, 2026-10-11. The drive is still open. Softness 1.0 remaps to 0.80 (`tireWearThermalsClassify.lua` line 301) and uses that anchor's wear: `wearRate` 0.00255, `rollingWearCoef` 70, `scalarTreadWearScale` 4.7. There is no life log that separates a stock race tire from the soft slick, so the predicted profile is those three numbers, on a route that does not edit the 0.80 anchor. The code stays shared until the 22 km Belasco run. Soft scalar 4.7 stays locked.
- [ ] **W-02 Slick scalar life on the new heat.** Drive, after S-05. Read scalar and node wear from the Belasco lock runs. The reference is the medium note: 7.6 points over the 12 km straight.

## Tooling (agent only, can start now)

- [x] **T-01 Heat shares in the reader.** Done 2026-10-11. `read` prints each tire's heat share over the run, and over the rows above the hot edge. `split` takes `--run`. Run `20261011-063818-43148-3` reads RR 54% rolling, 37% flex, 9% soak.
- [x] **T-02 Clean-straight flag.** Done 2026-10-11. `read` prints driven slip for the first third and the settled window. On a grid track, a settled median above 0.02 prints NOT A CLEAN STRAIGHT. `063553-1`, `063818-3`, and `064325-1` flag at 0.06–0.10. `065650-1` (0.011), `070059-2`, and the accepted straights `20261010-170451-133868-1` and `20261010-124201-136883-3` (0.000–0.001) do not.
- [x] **T-03 Stale-stamp warning.** Done 2026-10-11. `read` warns when the `lua=` hash in `code-stamp.txt` is not the current code hash.
- [x] **T-04 Golden coverage.** Done 2026-10-11. Soft slick rolling 2.20 and highway trailer rolling 16 are in the golden. 51 outputs pass.
- [x] **T-05 Replay harness.** Done 2026-10-11. The golden check had the same fault: it crashed on the unseated stub, so neither check ran from stage 6 (2026-09-27) until now. Both stubs are seated. The replay takes `--file` and `-h` and defaults to the newest log. It passes on the v6 and the older log. The golden's original 49 outputs still matched, so no locked number moved while the checks were down. The PowerShell wrappers had been calling a broken temp venv and exiting before Python ran. They now fall back to `python`, and the golden, career-wear, and replay wrappers pass.

## Testing efficiency (agent, can start now)

The noise floors, 2.2–7.1°C, are as large as most knob steps, and most of that noise is the driver. These tasks cut driver noise and the number of runs. None of them changes a heat number.

- [ ] **E-01 AI lap harness on the live folder.** Code is in, 2026-10-11. The smoke is the user's.
  - The trigger folder is resolved from `tireWestCoastLapTest.lua`, so the live `-work` folder works. `tools/RUN_WC_GT4_TEST` is the Belasco auto session. `tools/RUN_WC_MANUAL_TEL` is manual. `tools/RUN_WC_STRAIGHT` is the held-speed straight: load smallgrid, sit in the car, and create that file. Body lines `speed=80` and `km=12` are optional. The log is `tools/output/straight-telemetry.csv`. `tools/STOP_WC_TEST` stops a run.
  - Done when. The user starts one auto Belasco session and one held-speed straight, and `Read-NtfRun.py read` reads both. Then two repeat runs per voting car set the AI floor. If it is smaller than the driver floor, it becomes the floor for AI runs.

- [x] **E-02 Speed and start checks in the reader.** Done 2026-10-11. `read` prints speed by third, starting temperature, and first and settled psi. On a grid track the settled third flags when it is more than 5 m/s off the middle third. The first third is the launch and is not the gate. A grid run under 12 km flags, and a coldest tire above 45°C flags. Logged cold starts sit near 36°C. The lock straight flags by 15.1 m/s. The 3.1 straight `20261010-124201-136883-3` flags by 8.5 m/s.

- [x] **E-03 Fitted settled estimate.** Done 2026-10-11. On a grid run whose speed is held, `read` fits the first 6 km and prints Tinf, L, and the miss against the settled median. L at the 11.9 km cap prints FIT NOT SETTLED. The three-straight check is 10 of 12 tires within 1°C, and the two misses are the withheld lock-straight rears. Seven printed long straights are 21 of 28 tires within 1°C. A vote still wants 12 km.

- [x] **E-04 Heat-share prediction command.** Done 2026-10-11. `predict --run --knob rolling|flex|soak --axle front|rear|all --scale` scales that share of the settled rise above ambient. The band is half to double, and `--floor` says whether the closer end clears. On `20261010-173736-194181-1`, flex front 1.35 is +2.5°C and +2.2°C beside the hand +2.3°C. Flex and soak rear 0.74 together are -7.9°C and -7.6°C beside the hand -8°C. The pair form with `--rolling-delta` is unchanged. Static cooling stays a hand estimate. The numbers are in the script docstring.

- [x] **E-05 Cold pressures in the test configs.** Done 2026-10-11. The user asked for one fill. Front equals rear on every AMD test config.
  - Cold fill is the compound optimum divided by 1.06, so the hot target stays on the anchor. Hard 26.5. Medium 25.5. Medium-soft 25.0. Soft and native race 24.5. Supersoft and quali 24.0. Same front and rear, same on Bastion, Vivace, Sunburst, ETK K, and the GT3. The 2.20 lock was logged at the old Bastion native fill, 20.5/21.5.

- [ ] **E-06 Full heat on AI cars.** Code is in, 2026-10-11. The switch is off. Low priority.
  - Create `tools/FULL_HEAT_AI`, then spawn the other cars. Each unseated car runs full heat and writes `tools/output/ntf-ai-<id>.csv`. The seated car keeps its own log. The release zip does not ship `tools/`, so players stay on the lite step. Read an AI log with `Read-NtfRun.py read --file` that path. The default file skips `ntf-ai-` names. P-03's frame log includes `id`, so each car's cost is on its own line once `tools/FRAME_TIMER` is present.
  - Done when. Two cars log full heat in one session and the reader reads both files. Smoke only. Delete `FULL_HEAT_AI` afterward so traffic does not stay on the full path.

## Model realism (agent code behind a switch, then Drive)

Each of these changes heat. The code goes in behind a switch that is off by default, and the golden passes with it off. Nothing changes in play until a card is driven. A locked number that would move needs its own card.

- [ ] **M-01 Pressure against the right reference.** Agent, then Drive. Read it with S-01, where pressure is the first suspect.
  - Now. The heat path divides hot pressure by the cold fill (`tireWearThermalsImpl.lua` lines 1245–1250). `flexModifier` runs from 2.0 when flat to 0.5 at the fill and stays at 0.5 above it. `F.CalcBiasWeights` (`tireWearThermalsTemp.lua` line 15) reads a ratio above 1 as over-inflation and moves heat to the middle. So a warming tire always reads as over-inflated, and a 20.5 psi tire gets the same flex as a 30 psi tire. The grip path already measures against a hot target, `data.targetHotPressurePSI` (`tireWearThermalsImpl.lua` line 2118).
  - Real tires. Under-inflation adds flex and heats the shoulders. Over-inflation heats the middle. The S-01 run shows the opposite: middle 126°C, shoulders 86°C and 94°C, on a tire filled well below the medium anchors.
  - Decision for the user. `data.targetHotPressurePSI` comes from `F.seedHotTargetPSI` (`tireWearThermalsPressure.lua` line 61). It equals the compound `optimalPressure` when the cold fill is within 12% of the design cold (optimum ÷ 1.06). Otherwise it follows the fill, at cold plus 1.5–12 psi. Measuring against it removes the "warming reads as over-inflated" effect but does not penalize a low fill. Measuring against `optimalPressure` does both. Put both on the open card and let the user pick.
  - Steps. Shape the curves so a tire at its reference gets the flex and the split it gets today when warm, so locked bands do not move at the right pressure. Below the reference, more flex and more shoulder heat. Above it, less flex and more middle heat.
  - Done when. The switch is coded, the golden passes with it off, a soft-sim with it on shows no locked band moving at the anchor pressures, and a one-switch A/B on the Bastion medium config is ready to drive.

- [ ] **M-02 Stick flex from slip power.** Agent, after S-01.
  - `w.slipRatio` (`tireWearThermalsPhysicsLoop.lua` line 174) is slip speed over ground speed. Real tire heat follows force times slip speed. In the S-01 run, slip ratio rose from about 0.01 to 0.10 at constant torque, and stick flex followed it from 2 to 12.
  - Check the old branch `cursor/slip-power-corner-heat-921e` (H-02) first. It may hold earlier work.
  - Stick-flex gain 0.22 and the 0.12/0.30 window are locked. This needs its own card, a replay on the v6 log that shows the same fade, and the two-of-three vote.
  - Done when. The card, the switch, and the replay are ready, and S-01 has said whether slip ratio is part of the runaway.

- [x] **M-03 Where the front heat goes missing.** Done 2026-10-11. The finding is on the open card. No number changed. Front flex is about half the rear flex on the RWD laps, and front soak is about twice the rear soak. Settled slip heat is about 0. One axle scale cannot fit the ETK K hot rears and the Vivace and Sunburst cold rears.

- [ ] **M-04 Hot day, warm-up, and cool-down.** Setup note is in, 2026-10-11. The drive is before R-03.
  - Every logged run is at air 21°C and track 15°C. That track reading is the night case of `F.getTrackTemp`: sun factor 0, then track = air − 6°C. Air comes from `core_environment.getTemperature` through the GE mailbox (`lua/ge/extensions/tireWearThermals.lua`). The vehicle smooths it at 0.40 per second, capped at 2.5°C/s. Track is not its own slider. Clear noon adds up to 32°C. Rain holds the track near air.
  - Set them in the environment controls: air temperature, time of day, cloud cover. Air 30°C at clear noon is a track near 62°C. Air 30°C and track near 45°C is noon with cloud cover about 0.62, because the sun gain is then about 15°C. The grip windows do not move with the air. A tire that sat on a cold edge is at least 9°C hotter when the air is 30°C instead of 21°C, and hotter again when the track is no longer a heat sink.
  - Drive. One Belasco run per locked band at the hot setting. One out-lap from cold: a slick should reach its window within a lap or two. One cool-down in-lap.
  - Done when. Each locked band stays inside its window on the hot day, or the miss is on the open card.

## Docs (agent only)

- [x] **D-01 Trim the open card.** Done 2026-10-11. The open card went from 22.7 KB to 5.4 KB: the medium card, the fifth car, a short native-race card, and the floors that still apply. The Pass 1 and corner-flex log moved, unedited, to the top of Closed cards. Every run id still on the open card is in CHANGELOG. No number changed.
- [ ] **D-02 Tester checklist.** `RELEASE_CHECKLIST_TESTERS.md` still says 0.2.1, 2026-09-19, and the `-dev` folder. Update it after R-01 picks the version. The live folder is `-work`.
- [x] **D-03 Compat inventory encoding.** Closed 2026-10-11, not a defect. The file is valid UTF-8. The broken dashes came from PowerShell `Get-Content` reading it without `-Encoding UTF8`.

## Release

- [ ] **R-01 0.3.0 private tester drop.** Agent work plus a user smoke, after S-05. Bump `mod_info/TWTRS_NTF/info.json`, update the `LISTING.md` change notes, run `Pack-Release.ps1`, run the clean-zip smoke, then D-02.
- [ ] **R-02 Compat pack refresh.** Softness check is in. On 2026-10-11 the user chose compat for the AMD NTF tires.
  - `Node-Thermal-Friction-Tires-dev` slick files: hard 0.50, medium 0.65, supersoft 0.875. Those land on the anchors. The file named soft slick is softness 1.00, and `remapSlickSoftness` sends 1.00 to the 0.80 soft anchor. There is no compat file for the 0.575 hard anchor or the 0.725 medium anchor. Street files use 0.7, plus 0.50 and 0.65 where a slick compound is in the same file.
  - The 14 voting and GT3 NTF JBeams are in `vehicles/common/tires_amd_ntf/` in `Node-Thermal-Friction-Tires-dev` and in `Documents\Node-Thermal-Friction-Tires-private`. Not committed. The car configs stay in the AMD mods. A cleanup pass also removed side-reinf JBeams from Bolide, Muscle, Stirling, Sunstorm, TPU Superlite, and the ETK K spec mod. Those side-reinf files are not in the 2026-10-04 backup. The older supersoft and base tires for those cars were put back from that backup.
- [ ] **R-03 Public update.** The user decides. Merge to `main`, push the private repo, then update the public repo and both Repo listings together. The cross-link item in `PUBLISH_CHECKLIST.md` F2 is still open.

## Hygiene (needs the user's OK)

- [x] **H-01 Back up the AMD test fleet.** Done 2026-10-11. 42 configs and NTF tire JBeams, 428 KB, in `D:\ntf-logs\amd-fleet-2026-10-11`. Bastion, Vivace, Vivace race, Sunburst, ETK K, and the GT3. The AMD mods are still not in git.
- [ ] **H-02 Remote URL and old branches.** GitHub reports the private repo moved to `Node-Thermal-Friction-private.git`. Two old local branches remain: `cursor/code-review-hot-path` and `cursor/slip-power-corner-heat-921e`.

## Performance and robustness (agent only, low priority)

- [ ] **P-01 Seated load time.** The require list is timed, 2026-10-11. No heat change. With `tools/FRAME_TIMER` present, the seated load prints `tireWearThermals require <module> <ms>` for each submodule. The files are 167 KB in `tireWearThermalsImpl.lua` and 78 KB in `tireWearThermalsProfiles.lua`, then Classify 34 KB, NodeWear 33 KB, and Hud 31 KB. The 106.94 ms figure is still the only live total. The next time you take the seat, the console splits it. Delete `FRAME_TIMER` and reset to stop the lines.
- [x] **P-02 Pitwall digest loop.** Done 2026-10-11. A stream that arrived inside a digest was rewriting wheel arrays while `ng-repeat` walked them. `ingestStream` now waits for `$evalAsync` when `scope.$$phase` is set, temperature arrays update in place, and the wheel repeat tracks by name. Dev Pitwall only. Open the app once to confirm the console stays quiet.
- [ ] **P-03 Per-frame cost.** Timer is in, 2026-10-11. No heat change. `tools/FRAME_TIMER` is present, so the next seated minute appends mean and peak ms to `tools/output/frame-time.log` and prints `tireWearThermals frame`. Done when one seated car on Belasco has a line in that log. Delete `tools/FRAME_TIMER` and reset the car to stop it.

## Other bands (after the slick lock)

- [ ] **B-01 Utility and truck straights.** Drive. The 12 km rolling run answers truck, light truck, highway utility, steer, crawler, and paddle, the way the highway trailer locked at 16. The agent first names one test car and config per class.
- [ ] **B-02 Wet and winter.** A/B beyond the locked asphalt path.
- [ ] **B-03 Rally life and drift rate.** Provisional and non-blocking.

## Parked

- BeamMP remote cars. Reopen with a live session.
- Native °C as the grip temperature. It needs its own bypass test.
- Graining. Experimental.
