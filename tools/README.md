# Dev tools

Helpers for soft-sims, West Coast lap telemetry, and profile transforms.

| Path | Purpose |
| --- | --- |
| `scripts/` | PowerShell / Python helpers |
| `fixtures/` | Race track / Belasco path inputs |
| `output/` | Generated CSV, status JSON, soft-sim dumps (gitignored) |
| `V2_FRICTION_CONTRACT.md` | Experimental V2: thermal vs node-wear friction ownership |
| `V2_NODE_WEAR_SPIKE.md` | Clean-room node wear spike flags + retest |
| `REFACTOR_SPLITS.md` | Module split / Lua locals process |

## West Coast lap / telemetry

Triggers live in `tools/` (VFS: `mods/unpacked/Node-Thermal-Friction-dev/tools`):

- `RUN_WC_MANUAL_TEL` — manual drive + CSV telemetry
- `RUN_WC_GT4_TEST` — auto AI Belasco test
- `STOP_WC_TEST` — abort
- `TELEMETRY_CSV_ARMED` — written by the vehicle extension when CSV is armed

Outputs go to `tools/output/` (`wc-*-lap-*.csv/json/txt`).

Vehicle CSV (armed only via `setTelemetryCsv` / West Coast runners; off by default) keeps the
legacy `wall..film` columns, then appends UI-stream fields: `profile,profile1,profile2,purpose,classifyReason,patchFrac,patchHeatScale,aeroLoadN,totalDownforceN,aeroFracPct,dutyMods,driveHeatGate,streetSlipScale,utilNudge,aeroDragN,aeroFrontN,aeroRearN,copPct`.
`aeroLoadN` / `totalDownforceN` / `aeroFracPct` are **native triangle aero** (`calcTotalAeroForces` / CoP axle split), not the old speed×48% estimate. Suffix `aeroDragN,aeroFrontN,aeroRearN,copPct` are extra native channels. `dutyMods` / profile strings are CSV-quoted when they contain commas. Parsers that only use
legacy indices (e.g. `Summarize-WcTelemetry.ps1` cols 0–13) stay compatible.

Example runners: `scripts/Run-WestCoastManualTelemetry.ps1`, `Run-WestCoastGt4Laps.ps1`, etc.

## High-speed (HS) slip test protocol (Belasco / straight)

Use this procedure when you want a *compound ranking* based on **steady high-speed longitudinal slip**, not on “extra slip-energy from accelerating” and not from “cold/unwarmed tires”.

### Required

- Same car model + same vehicle setup
- Same tire compound ladder (e.g. Sport → Sport Plus → Track Day)
- Same Belasco straight segment (use your usual marker / lane)
- Pitwall / Tire Telemetry overlay visible so you can read:
  - wheel speeds (FL/FR/RL/RR)
  - slip channels (`Slip E / long / side`) if shown
- Record for each run:
  - target speed (mph or km/h)
  - `FL/FR/RL/RR wheel speeds`
  - Pitwall slip channels (or computed HS slip%)

### Common 3 errors (what to avoid)

1. **Grip-map screenshots only**
   - Early tests used “grip map” screenshots; those don’t give the wheel-speed and slip channels you need for HS slip comparison.
   - Always use Pitwall / Tire Telemetry capture at the sampling moment.
2. **Full acceleration instead of cruise**
   - HS slip must be sampled during **steady cruise / held condition**.
   - Testing while torque is ramping mixes warm-up effects into the slip measurement.
3. **Cold tires**
   - If Pitwall temps are far below opt, the slip result is not representative for the compound.
   - If you must record cold, label it `COLD` and do not compare it against `NEAR-OPT` runs.

### Step-by-step

1. **Warm-up**
   - Run your normal warm-up laps for the tire set until temperatures are “near opt” for the compound(s).
2. **Reach target HS speed**
   - Accelerate normally on the Belasco straight up to your target speed band (example: ~134 mph).
3. **Switch to steady-state**
   - Hold constant input (cruise / steady throttle) for ~10–20 seconds.
   - Avoid big steering changes during the sampling window.
4. **Capture the data**
   - At the sampling moment, record:
     - `FL/FR/RL/RR wheel speeds`
     - `Slip E / long / side` for each wheel (if available)
5. **Compute HS slip% from wheel speeds (wheel-speed differential)**
   - `avgFront = (FL + FR) / 2`
   - `avgRear  = (RL + RR) / 2`
   - `slip% ≈ (avgRear - avgFront) / avgFront * 100`
6. **Repeat for each compound**
   - Keep everything else identical: straight, speed band, input style, and sampling duration.

### Notes

- If longitudinal slip channels are ~0 across the sample window, the compound is very tight at that speed/input.
- When comparing compounds, rank using `NEAR-OPT` runs first; keep `COLD` only for debugging.

### Run template (copy per compound)

Fill one block per compound. Keep car, straight, and target speed identical across the ladder.

```
HS SLIP — Belasco straight
Date: __________   Car: __________   Compound: __________
Tire part (F/R): __________ / __________   Pitwall: sport_name ✓ / other: __________

PRE-FLIGHT
[ ] Pitwall / Tire Telemetry open (NOT grip map)
[ ] Same Belasco straight + lane/marker as prior runs
[ ] Target speed band: _____ mph (e.g. ~134)

WARM-UP
[ ] Laps until avg temp near opt (Sport ~66°C / Plus ~76°C / Track Day ~76°C)
[ ] Label run: NEAR-OPT  or  COLD (if still below window — do not ladder-compare)

SAMPLE (steady cruise only — NOT full accel)
[ ] Reach target speed on straight
[ ] Hold steady throttle ~10–20 s (minimal steering)
[ ] Screenshot or note at sample moment:

    Speed (HUD): _____ mph
    FL _____  FR _____  RL _____  RR _____  (wheel mph)
    Slip E:  FL ___ FR ___ RL ___ RR ___
    Avg temp vs opt: FL ___/___  FR ___/___  RL ___/___  RR ___/___

CALC
    avgFront = (FL+FR)/2 = _____
    avgRear  = (RL+RR)/2 = _____
    HS slip% = (avgRear - avgFront) / avgFront × 100 = _____ %

LADDER (same session setup)
    Sport       HS slip%: _____   temp label: _____
    Sport Plus  HS slip%: _____   temp label: _____
    Track Day   HS slip%: _____   temp label: _____

INVALID IF: grip-map only | sampled under full accel | COLD compared to NEAR-OPT
```

## 22 km stint protocol (Belasco / heat · wear · grip tuning)

Use this for **full-lap compound tuning** — thermal settle shape, wear rate, blister/graining, stint fade — over a real driving distance. This is **separate from** the HS slip straight test above; do not mix the two in one judgment pass.

### Purpose

- Answer: “After ~22 km of race pace on Belasco, does this compound heat, wear, and grip correctly?”
- Standard distance: **~22 km** on Pitwall **Stint km** (resets on vehicle respawn/reload).
- Typical session: **~4 laps** on West Coast / Belasco racetrack ≈ 22 km (varies slightly with line).

### Required

- **Belasco Motorsports Park** (`west_coast_usa` racetrack layout) — same line each compare
- **Pitwall / Tire Telemetry** (Heavy app preferred: **Stint km**, **Odo km**, per-wheel **Heat knobs**)
- **Vehicle respawn** after any profile/knob change (confirm live stamps in Heat knobs row)
- Record **Track °C** and **Env °C** from Pitwall header (baseline compare: Track **~15°C**, Env **~21°C** when possible)
- Consistent pace: race pace you can repeat lap to lap (not one-lap quali vs cruise)

### Common errors (what to avoid)

1. **Grip-map screenshots only** — need Pitwall temps, wear %, Stint km, heat knobs.
2. **No respawn after tuning** — stale profile; Stint km and Heat knobs won’t match your edit.
3. **Stopping short of ~22 km** — wear and stint-fade judgments are calibrated to **~22 km**, not “felt fine at lap 2.”
4. **Using the HS slip straight test for heat tuning** — straights diagnose longitudinal slip; stints need **corners + braking + lap distance**.
5. **Chasing RL ≫ RR on RWD Belasco** — WCU right-turn load often makes **RL** hotter than **RR** (~8–12°C); treat as **track asymmetry**, not a compound bug.
6. **Different track/env temp between A/B** — note Track/Env on every run; don’t compare 15°C vs 25°C stints.

### Step-by-step

1. **Respawn** vehicle (fresh Stint km = 0, profile re-init).
2. **Pre-flight** — Pitwall open; note compound label (`sport_name`, `sport_plus_name`, etc.); confirm Heat knobs match expected profile after respawn.
3. **Drive ~4 laps / ~22 km** at repeatable race pace on Belasco.
4. **Capture three moments** (screenshot or CSV):
   - **Settle** (~lap 2–3): straight-line avg temp **FL / FR / RL / RR** vs each wheel’s **opt**
   - **Loaded corner** (e.g. Turn 1): peak loaded-axle temps (fronts on brake, rears on power for RWD)
   - **End of stint** (Stint km **≥ 21.5 km**): tread **Cond %**, **Stint Fade %**, blister/graining if any
5. **Judge** (see below) before changing knobs; one change per respawn cycle.

### What to judge

| Area | Look for |
| --- | --- |
| **Heat shape (RWD)** | Rears warm toward opt; fronts cooler (undriven + brake). **F ≪ R** on high-DF RWD is normal — do not force all four to opt. |
| **Heat shape (FWD)** | Opposite: **F ≳ R** expected; Soft-like slicks may need topology damp — don’t retune compound off one FWD car. |
| **Harsh-drive ceiling** | RL (or FL on FWD) may spike **Hot** under abuse — OK if cruise settle is sane. |
| **Wear @ ~22 km** | Tread **Cond %** drop; compare compound ladder (e.g. slicks: Soft ~4% → Medium ~2–3% → Hard ~1–1.5% band). |
| **Stint fade / blister** | Stint Fade rising late stint; blister only after sustained over-temp + scrub (not on clean 22 km street sport). |
| **Grip feel** | Cold mid-corner loose vs peak logged μ; note if temps never reached window (separate warm-up issue). |

### Street sport ladder (Scintilla GTS Corse reference)

Same car/tires, respawn between compounds:

| Compound | Opt (°C) | Stint focus |
| --- | --- | --- |
| Sport | ~66 | **HEAT+WEAR LOCKED.** Heat v7 + tiny bump 9.68/5.61. Wear **0.0026** (22 km ~0.6–0.9% / target ~0.8%; under Plus 0.0028) |
| Sport Plus | ~76 | **HEAT+WEAR LOCKED (#8).** velCool 0.50, slip/work 16.6/10.2, wear 0.0028 |
| Track Day | ~76 | **HEAT+WEAR LOCKED.** Heat v3 10.9/6.20. Wear **0.0033** (first-cut above Plus 0.0028 / ~1.5%; was immortal 0.00073) |

Judge **shape and wear trend**, not “all four wheels at opt” on street rubber.

### Optional telemetry

- Manual CSV: `scripts/Run-WestCoastScintillaManualTelemetry.ps1` (Scintilla / sport_plus, 4 laps)
- Kingsnake sport: `scripts/Run-WestCoastKingsnakeManualTelemetry.ps1`
- Outputs: `tools/output/wc-*-lap-telemetry.csv`

### Run template (copy per stint)

```
22 KM STINT — Belasco full lap
Date: __________   Car: __________   Compound: __________
Tire F/R: __________ / __________   Classify: __________
Track ___°C   Env ___°C   Stint km at end: _____

PRE-FLIGHT
[ ] Respawned (Stint km = 0)
[ ] Pitwall open (NOT grip map only)
[ ] Heat knobs row matches expected profile after respawn
[ ] Pace plan: repeatable race laps (not HS straight-only)

DRIVE
[ ] ~4 laps / target Stint km ≥ 21.5
[ ] Same line as prior compound tests

CAPTURE — SETTLE (lap 2–3, straight)
    FL ___/opt___  FR ___/opt___  RL ___/opt___  RR ___/opt___
    Notes: F≪R? RL≫RR? (track bias OK)

CAPTURE — LOADED (e.g. Turn 1)
    Hot axle temps: __________
    Dynamic grip %: __________

CAPTURE — END (~22 km)
    Cond %: FL ___ FR ___ RL ___ RR ___
    Stint Fade %: __________   Blister/Grain: __________
    Peak carcass (any wheel): __________

VERDICT
    Heat shape OK?  Y / N   Wear OK?  Y / N   Lock / nudge / reject?
    Next single knob change (if any): __________

INVALID IF: no respawn | < ~20 km | grip-map only | mixed with HS slip sample
```

### WCU Soft C4 mute-removal notes (live)

- **Sport WEAR LOCKED / HEAT REOPENED (2026-09-10):** workHeatRate **5.61→4.94** (~−12%);
  slip **9.68** / rolling held. Cornering/load overshoot dial-back. Wear **0.0026** held.
- **Sport Plus WEAR LOCKED / HEAT REOPENED (2026-09-10):** workHeatRate **10.2→9.0**;
  slip **16.6** / velCool **0.50** held. Wear **0.0028** held.
- **Aero heat = mechanical (realism):** native Pitwall/CSV stay. `aeroHeatScale` **1.0** — aero newtons in `downForce` heat like weight. The 0.55 mute and speed×48% fake are off. If a GT3 cooks on a straight, chase RR / high-V cool, not an aero fudge. Locked Sport/Plus/slick heat was already on 1.0.
- **Track Day WEAR LOCKED / HEAT REOPENED (2026-09-10):** workHeatRate **6.20→5.45**;
  slip **10.9** held. Wear **0.0033** held.
- **Graining #1:** Global thresh **0.10→0.045**, window decay **0.012→0.0035**, rolling cap **0.008→0.003**. Sport/Plus `grainTempRatio` **0.88** (Sport &lt;~58°C, Plus &lt;~67°C), `grainRate` ×2. Soft/slick packs unchanged. **Respawn**; look for grain on a cold out-lap, not at 22 km hot.
- **Compound for A/B:** NTF Soft Slick (C4) F+R — hold fixed across each mute family.
- **Phase 1 (done):** `drivePropSlickScale` / `drivePropSlickCarcassScale` → 1.0. Rears warm into/near opt 82; fronts lag (undriven + brake).
- **FWD Soft-like topology LOCKED:** Before damp FR/FL ~**106 / ~120** Hot vs opt **82**. After: FR ~**97** Normal (top of usable ~**95–105**); F≫R kept; Hot still possible under abuse. Scales: `drivePropFwdSoftScale` **0.58** / carcass **0.48** / softnessMin **0.72**. Soft compound knobs untouched. RWD Soft Phase1 unmute stays. Duty: `fwd_soft_drive_damp`. **Do not nudge.**
- **WCU right-turn bias:** Belasco / West Coast has many right turns in heavy-accel zones. On RWD that spikes **RL** skin/carcass vs **RR** (~+8–12°C typical). Treat RL≫RR as **track/load asymmetry**, not a Soft C4 bug — do not chase with global cool.
- **Phase 2 (cruise mutes):** `cruiseRrScaleFull` / `cruiseRrScalePartial` / `cruiseDriveChokeMin` → 1.0 (was 0.48 / 0.72 / 0.15). Soft C4 live A/B; watch Belasco highway straights for cook.
- **Soft C4 wear locked:** rollingWearCoef **70** (4-lap ~95.7–96.6% / ~3.5–4% drop; path live). airCool **0.014**. Protocol: **4 laps**.
- **Soft C4 WEAR+scalar LOCKED / HEAT REOPENED (2026-09-10):** workHeatRate **9.8→8.62**;
  slip **17.5** / rolling / velCool **0.85** held. Prior settle ~**62 / 73 / 80 / 90** vs opt **82**
  was the aggressive-overshoot baseline — reconfirm loaded Turn 1 Hot ceiling milder.
- **Medium C3 WEAR LOCKED / HEAT REOPENED:** work **8.6→7.57** (mid **8.9→7.83**); slip held.
- **Hard C2 WEAR LOCKED / HEAT REOPENED:** work **7.8→6.86** (mid **8.1→7.13**); slip held.
- **C5 HEAT REOPENED:** work **10.7→9.42**; slip **19.5** / scalar **4.7** held.
- **Wear ladder (locked):** Soft **70** ≈4% → Medium **42/48** → Hard **50/55**.
- **Pitwall reload proof:** Heavy app header shows **Stint km** (mod trip, resets on vehicle reload) + **Odo km** (vehicle electrics when available). Per-wheel **Heat knobs** row: air / vel× / g0 / slip/work / trk — confirms live profile after respawn (Hard → vel×**0.50**, Medium → **0.60**, Soft → **0.85**). Re-add Pitwall app after UI edits.
- **AWD Soft edge case (baseline):** Soft `vel×0.85` + duty `awd_prop_gate`. Settle FR/FL ~**101 / ~115** Hot vs opt **82**; RR/RL ~**81 / ~96**. Rears OK; fronts like pre-damp FWD Soft (FWD Soft damp does not run on `awd` layout). Soft compound lock stands.
- **AWD Soft-like front damp #1 (partial):** FR ~**88** Normal; FL ~**112** Hot (barely moved). Scales **0.58/0.48**.
- **AWD Soft-like front damp LOCKED (#2):** FR ~**96** Normal (top of usable); FL ~**109** Hot (brake soak ~620°C + harsh ceiling — do not chase). Scales: `drivePropAwdSoftScale` **0.45** / carcass **0.38**. Soft/FWD Soft/compound locks untouched. Duty: `awd_soft_front_damp`. **Do not nudge.**
- **Path A6 (heat pin — failed live):** Soft C4 4-lap still ~**58/69/72/76** vs opt **82** after `patchFracRef` 0.043 / heat floor 0.70 / `patchFracHeatMin` 0.026. Path A not the live pin (or already ≥0.70). Keep A6 values; do not stack more Path A for Soft.
- **Skin retention #1 (too mild):** `trackConductivityMult` **1.15→0.88**, `skinCoreConductance` **0.116→0.130**. Clean Track **15°C** short stint still ~**58/70/74/83** vs opt **82**; FR pegged ×0.70. Path A6 live; do not stack more Path A.
- **Skin retention #2 (failed live):** `trackConductivityMult` **0.88→0.75**. Clean Track ~15°C still FR **~58**; FL/RR/RL shape unchanged. Track conduction is not the front-window lever here.
- **Static cool cut (failed live):** `staticCoolingRate` **0.076→0.060**. FR still ~55–60 @ Track 15°C — static is `×0.04` vs on-track **velCool**.
- **Skin velCool 0.70 (live):** Track 15°C ~**64/76/83/94** vs opt **82**. RR in window; **RL cook** (avg 94 / carcass ~102) — keep that as a harsh-drive ceiling, not the cruise settle. FR still Cold; wear ~96–99%.
- **Middle ground + turn-in:** `skinVelCoolScale` **0.85**. Soft `workHeatG0` **0.10** was still a trickle (work ∝ g−G0, then ×0.70 patch). Next: `workHeatG0` **0.10→0.04**. Held: velCool 0.85, airCool **0.014**, wear **70**. **Respawn**. Judge FR/FL on a sweeper; RL still allowed to cook if abused.
