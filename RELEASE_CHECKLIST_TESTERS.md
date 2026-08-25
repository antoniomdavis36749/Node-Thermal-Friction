# ReSpin — tester build checklist (one page)

Use this **before every build** you hand to testers (Discord, forum, `-dev` sync, or zip).  
Full Repo publish steps stay in `PUBLISH_CHECKLIST.md` — this is the **“does it work?”** list.

**Current version (update when you ship):** `0.2.0-exp` · **Build date:** ___________ · **Git branch:** ___________

**Status:** Experimental / private — public Repo publish paused (see README + `tools/V2_FRICTION_CONTRACT.md`).

---

## 1. What changed (5 bullets max — paste to testers)

1. Flatspot removed (no accumulation / μ tax / UI)
2. Marked experimental 0.2.0-exp; V2 friction contract in tools/
3. Brake lock fade disabled — native lock only (Lock fade stays 0%)
4. Thermal-first: scalar tread wear off; node-wear spike on (Pitwall **NODE SPIKE** block — dev UI only)
5. Pitwall Heavy labeled **DEV / TESTING** — not shipping in public builds; use Classic/Crew for normal play

**Calibration touched?** ☐ No (default) · ☐ Yes — list locks: _______________________

---

## 2. Before you drive (2 minutes)

| Step | Done |
|------|:----:|
| Only **one** thermals mod enabled (disable Redux / Luuk / old ReSpin Repo copy) | ☐ |
| Core: `Tire-Wear-and-Thermals-ReSpin-dev` **or** test zip — not both | ☐ |
| Compat tires (if testing Scintilla ReSpin): `Tire-Wear-and-Thermals-ReSpin-Tires-dev` enabled | ☐ |
| After **any** Lua/UI change: **respawn vehicle** (reload map is not enough) | ☐ |
| Re-add HUD apps if stream is blank: Classic / Crew (Pitwall = dev only) | ☐ |

### Minimal mod profile (recommended for smoke + GT3 testing)

Load **only** what you need so other mods don’t mask bugs or change grip/temps.

**Enable**
- ReSpin core: `Tire-Wear-and-Thermals-ReSpin-dev` **or** test zip — **not both**
- Compat tires (Scintilla ReSpin only): `Tire-Wear-and-Thermals-ReSpin-Tires-dev`
- The **GT3 / car under test** (e.g. Scintilla GT3 ReSpin) and any JBeam pack it **requires**
- ReSpin HUD apps if checking temps/PSI (**Pitwall = dev/testers only**; Classic or Crew for normal play)

**Disable**
- Other tire / thermal / grip mods (Redux, Luuk, duplicate ReSpin Repo zips, `-dev` leftovers)
- Extra car packs, gameplay mods, and UI you’re not using this session
- A second copy of the same ReSpin folder (zip + unpack, or two `-dev` paths)

**Rule:** one tire-physics mod family at a time during calibration and bug reports.

---

## 3. Smoke test (you or lead tester — ~10 minutes)

Spawn **one car you know well** (e.g. Scintilla GT3 ReSpin Soft). Console open (`~`) — **no red Lua errors** on spawn.

| Check | Pass |
|-------|:----:|
| HUD shows temps / grip / pressure on all four corners | ☐ |
| Pitwall shows **profile + purpose** per wheel (not all “Standard”) | ☐ |
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
| Highway cruise 2 min — Sport/Sport Plus **not** overheating on straight | ☐ | |
| Hard track lap — Soft/Med/Hard band still plausible | ☐ | |
| Spinout / lockup — **Leak** only (flatspot removed); no instant blowout at speed | ☐ | |
| Wet asphalt — grip drops, no ice-like behavior | ☐ | |
| FWD/AWD Soft front — no runaway Cold PSI fill at highway speed | ☐ | |
| Brake duct sliders save in `.pc` and affect Pitwall duct % | ☐ | |

---

## 5. Packaging (only if sending a **zip**, not just `-dev` sync)

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'TireWearThermalsReSpin.zip'
```

| Check | Done |
|-------|:----:|
| Zip contains `lua/`, `ui/`, `scripts/`, `mod_info/TWTRS_RESPIN/` at **root** (no extra parent folder) | ☐ |
| Zip does **not** contain `tools/`, `.git/`, `.vscode/` | ☐ |
| Zip does **not** contain `ui/modules/apps/tireWearThermalsHeavy/` (dev Pitwall) | ☐ |
| `mod_info/TWTRS_RESPIN/info.json` **version_string** matches section 1 | ☐ |
| Clean install: enable zip only → apps appear in Apps menu | ☐ |

Compat tires zip (if changed): pack from **ReSpin Tires** repo separately.

---

## 6. Copy-paste for testers (Discord / forum)

```
ReSpin test build — v________ · ________ (date)

CHANGES:
• 
• 

INSTALL:
• Disable other tire-thermals mods and the public ReSpin Repo copies (39082/39083) if you use -dev.
• Minimal load: ReSpin core + compat tires (if Scintilla ReSpin) + test car only — disable unrelated mods.
• Core: Tire-Wear-and-Thermals-ReSpin-dev (or attached zip).
• Compat (Scintilla ReSpin tires only): Tire-Wear-and-Thermals-ReSpin-Tires-dev.
• After install: spawn car, add Tire Wear Thermals ReSpin apps (Pitwall recommended).

IMPORTANT: Respawn vehicle after every Lua update.

REPORT BUGS WITH:
Car + config | Map | Weather | What you did | What happened | Console error (screenshot)
Build: v________ · branch/commit if known
```

---

## 7. Known issues (remind testers — don’t re-open as “new” unless worse)

- **Respawn required** after Lua/UI updates (cached apps / old stream name).
- **Only one** thermals mod at a time.
- **Pitwall** is dense; Classic or Crew is enough for casual driving.
- **Alpha:** street / wet / truck bands still open; locked bands listed in listing.
- **AWD Soft:** one front can spike under heavy brake soak — harsh-drive ceiling, not always a bug.

---

## 8. Sign-off

| Role | Name | Date |
|------|------|------|
| Built / synced by | | |
| Smoke test by | | |
| OK to send to testers | ☐ Yes · ☐ No — blocker: _________________ |

---

*Keep `PUBLISH_CHECKLIST.md` for BeamNG Repo uploads. Use this file for every internal tester drop.*
