# Node-Thermal Friction — tester build checklist (one page)

Use this **before every build** you hand to testers (Discord, forum, `-dev` sync, or zip).  
Full Repo publish steps stay in `PUBLISH_CHECKLIST.md` — this is the **“does it work?”** list.

**Current version (update when you ship):** `0.2.1` · **Build date:** 2026-09-19 · **Git branch:** `testing/main`

**Status:** Private tester (Beta) — public Repo publish still paused (see README + `tools/V2_FRICTION_CONTRACT.md`).

---

## 1. What changed (5 bullets max — paste to testers)

1. **Round-2 fleet heat** dial-back (spread slip/work/util/weight-shift; rolling held) — **testers own validation**
2. **numRays 16** baseline locked (18/20/24 broke modded cars; natives often OK)
3. **A2** scalar Cond→grip fade floor **0.70 LOCKED**; A1 node μ unchanged
4. Non-feel polish: Classic/Crew clarity, duct copy, Compat README/inventory, spectra status labels
5. **Pitwall Heavy** = DEV only (`-dev` / git); zip = Classic + Crew only

**Calibration touched?** ☑ Yes — heat round-2 (tester-owned); feel wear locks held; polish campaign on product surfaces

---

## 2. Before you drive (2 minutes)

| Step | Done |
|------|:----:|
| Only **one** thermals mod enabled (disable Redux / Luuk / old Node-Thermal Friction Repo copy) | ☐ |
| Core: `Node-Thermal-Friction-dev` **or** test zip — not both | ☐ |
| Compat tires (if testing Scintilla Node-Thermal Friction): `Node-Thermal-Friction-Tires-dev` enabled | ☐ |
| After **any** Lua/UI change: **respawn vehicle** (reload map is not enough) | ☐ |
| Re-add HUD apps if stream is blank: Classic / Crew (Pitwall = dev only) | ☐ |

### Minimal mod profile (recommended for smoke + GT3 testing)

Load **only** what you need so other mods don’t mask bugs or change grip/temps.

**Enable**
- Node-Thermal Friction core: `Node-Thermal-Friction-dev` **or** test zip — **not both**
- Compat tires (Scintilla Node-Thermal Friction only): `Node-Thermal-Friction-Tires-dev`
- The **GT3 / car under test** (e.g. Scintilla GT3 NTF) and any JBeam pack it **requires**
- Node-Thermal Friction HUD apps if checking temps/PSI (**Pitwall = dev/testers only**; Classic or Crew for normal play)

**Disable**
- Other tire / thermal / grip mods (Redux, Luuk, duplicate Node-Thermal Friction Repo zips, `-dev` leftovers)
- Extra car packs, gameplay mods, and UI you’re not using this session
- A second copy of the same Node-Thermal Friction folder (zip + unpack, or two `-dev` paths)

**Rule:** one tire-physics mod family at a time during calibration and bug reports.

---

## 3. Smoke test (you or lead tester — ~10 minutes)

Spawn **one car you know well** (e.g. Scintilla GT3 NTF Soft). Console open (`~`) — **no red Lua errors** on spawn.

| Check | Pass |
|-------|:----:|
| HUD shows temps / grip / pressure on all four corners | ☐ |
| Pitwall (if used) shows **profile + purpose** per wheel (not all “Standard”) | ☐ |
| Drive 1 lap — temps move, not stuck at ambient | ☐ |
| Pit stop / respawn — values reset sensibly, no `-1` / NaN pressure | ☐ |
| Optional CSV telemetry: disarmed by default; enabling doesn’t spam errors | ☐ |

**Node spike (Pitwall dev only):** hard lock ~10 s → peak in teens %; parked after lock shows **`ON · idle`**, **0% / peak% / n≥1**, lock fade **0%**. Quirks table: `tools/V2_NODE_WEAR_SPIKE.md` § *Minor Pitwall quirks*.

### Architecture smoke (after Lua/structure changes — respawn required)

| Check | Pass |
|-------|:----:|
| Console prints `tireWearThermals vehicle extension onInit` on spawn/respawn | ☐ |
| Pitwall **Dynamic Grip ≠ 10.00%** on all corners (10% = empty `wheelCache` / ice fallback) | ☐ |
| PSI ok on four corners — not NaN, not `-1`, not stuck at 0 while inflated | ☐ |
| Temps/wear advance after a short drive; no new red Lua errors | ☐ |

**If anything fails:** note car, map, weather, and **exact console line** in section 6.

---

## 4. Regression spot-check (when physics or grip changed)

Only run the rows that match **what you changed**. Skip the rest.

| Scenario | Pass | Notes |
|----------|:----:|-------|
| Highway cruise 2 min — Sport/Sport Plus **not** overheating on straight | ☐ | Street heat + round-2 — cruise should stay flat |
| Mid-speed turns — outside tire heat (low-camber native/mod) | ☐ | **Phase-2 heat — tester-owned**; compare vs pre-round-2 |
| Hard track lap — Soft/Med/Hard band still plausible | ☐ | GT3 is ideal platform; also try a flatter setup car |
| Spinout / lockup — **Leak** only (flatspot removed); node peak teens on hard lock | ☐ | |
| Wet asphalt — grip drops, no ice-like behavior | ☐ | **LOCKED** 2026-08-30 — no nudge |
| FWD/AWD Soft front — no runaway Cold PSI fill at highway speed | ☐ | |
| Brake duct sliders save in `.pc` and affect Pitwall duct % | ☐ | Tire/rim cooling only — not rotor fade |

---

## 5. Packaging (only if sending a **zip**, not just `-dev` sync)

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'NodeThermalFriction_0.2.1.zip'
```

| Check | Done |
|-------|:----:|
| Zip contains `lua/`, `ui/`, `scripts/`, `mod_info/TWTRS_NTF/` at **root** (no extra parent folder) | ☐ |
| Zip does **not** contain `tools/`, `.git/`, `.vscode/` | ☐ |
| Zip does **not** contain `ui/modules/apps/tireWearThermalsHeavy/` (dev Pitwall) | ☐ |
| `mod_info/TWTRS_NTF/info.json` **version_string** matches section 1 (`0.2.1`) | ☐ |
| Clean install: enable zip only → apps appear in Apps menu | ☐ |

Compat tires zip (if changed): `.\tools\scripts\Pack-Compat-Release.ps1` (or pack from tires unpack).

---

## 6. Copy-paste for testers (Discord / forum)

```
NTF private tester — v0.2.1 · 2026-09-19 (Beta)

CHANGES:
• Round-2 fleet heat dial-back (testers own mid-corner / low-camber validation)
• numRays 16 locked (higher rays OK on some natives, broke modded cars)
• A2 floor 0.70 LOCKED; Classic/Crew + duct copy polish; Compat README/inventory
• Spectra honesty: truck/utility/AT placeholders labeled provisional

INSTALL:
• Disable other tire-thermals mods and the public Node-Thermal Friction Repo copies (39082/39083) if you use -dev.
• Minimal load: Node-Thermal Friction core + compat tires (if Scintilla Node-Thermal Friction) + test car only — disable unrelated mods.
• Core: Node-Thermal-Friction-dev (or attached NodeThermalFriction_0.2.1.zip).
• Compat (Scintilla NTF tires only): Node-Thermal-Friction-Tires-dev.
• After install: spawn car, add Node-Thermal Friction Classic or Crew.

IMPORTANT: Respawn vehicle after every Lua update.
PHASE-2 HEAT: prefer a low-camber native/mod street car for mid-speed turns, not only Scintilla GT3.

REPORT BUGS WITH:
Car + config | Map | Weather | What you did | What happened | Console error (screenshot)
Build: v0.2.1 · testing/main · 2026-09-19
```

---

## 7. Known issues (remind testers — don’t re-open as “new” unless worse)

- **Respawn required** after Lua/UI updates (cached apps / old stream name).
- **Only one** thermals mod at a time.
- **Pitwall** is dense and **dev-only**; Classic or Crew is enough for casual driving.
- **Beta:** feel stack is ahead of product polish; public Repo still paused.
- **A2:** fade starts `sc` &lt; 70%; floor **0.70 LOCKED** (2026-09-06).
- **AWD Soft:** one front can spike under heavy brake soak — harsh-drive ceiling, not always a bug.
- Cond % can be **node-led** on race camber; soft scalar life is the slow stint clock (A1).
- **Drift** (Sport + sustained spin): node arm + camber mute on; rate **0.017** provisional.
  Feel feedback welcome — **not a release blocker** if quiet before next drop.
- Truck / utility / AT / vintage scalar life: **provisional fallback** (see `tools/SPECTRA_STATUS.md`).

---

## 8. Sign-off

| Role | Name | Date |
|------|------|------|
| Built / synced by | Auto | 2026-09-19 |
| Smoke test by | | |
| OK to send to testers | ☑ Yes · ☐ No — blocker: _________________ |

---

*Keep `PUBLISH_CHECKLIST.md` for BeamNG Repo uploads. Use this file for every internal tester drop.*
