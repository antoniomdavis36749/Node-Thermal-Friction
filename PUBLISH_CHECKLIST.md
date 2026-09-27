# BeamNG Repo publish checklist

> **Public source:** `main` on Node-Thermal-Friction is the 0.2.2 tree. The BeamNG
> resource zip is a separate upload of `NodeThermalFriction.zip` from `Pack-Release.ps1`.

Branches: **`testing/main`** (active polish) → merge to **`main`** (GitHub default / Repo source link)  
Working folder: `Node-Thermal-Friction-dev` (local git sync under `mods/unpacked/`)  
Official packing docs: https://documentation.beamng.com/modding/mod-support/mod_packing/  
Guidelines: https://www.beamng.com/game/support/policies/modding-guidelines/

`beamng-repo-publish` is retired (stale ancestor; do not use).

## Status legend

- `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` deferred / N/A

---

## Calibration band (0.2.0 Beta / private tester) — locked where noted; flatspot removed

Street Sport heat and Sport Plus heat+wear locked on the same Belasco Track ~15°C / ~22 km protocol. Race slick band from 0.1.1 still held.

| Lock | Notes |
| --- | --- |
| Sport heat | HEAT v7 — cruise cooler than opt; do not chase 66°C on the highway |
| Sport Plus heat + wear | HEAT #8 / wear 0.0028 — no FL blister on a ~22 km stint |
| Track Day heat | Locked for now (between Plus and Hard) |

- [x] Listing / `info.json` refreshed for 0.1.2 (everyday wording)

## Calibration band (0.1.1) — locked

Live Belasco / WCU Track ~15°C protocol (~4 laps / ~22 km). Soft compound knobs stay locked; layout damps are topology-only.

| Lock | Notes |
| --- | --- |
| Soft C4 heat + wear | `vel×0.85`, rolling **70**, settle ~62/73/80/90 vs opt 82 |
| Medium C3 heat + wear | `vel×0.60`, rolling **42/48**, Soft-like colder settle vs opt 84 |
| Hard C2 heat + wear | `vel×0.50`, rolling **50/55**, ~62/74/79/86 vs opt 90 |
| FWD Soft front damp | `0.58/0.48` — fronts ~97 top of usable |
| AWD Soft front damp | `0.45/0.38` — FR ~96; FL harsh/brake ceiling |

- [x] Soft / Medium / Hard NTF slick band locked
- [x] FWD Soft-like topology locked
- [x] AWD Soft-like front damp locked
- [x] Pitwall Heavy kept in git for dev/testers (`-dev` unpack); **excluded from public zip** (see packer)
- [x] Listing / `info.json` refreshed for 0.1.1 (kept; 0.1.2 supersedes public copy)

---

## A. Legal & credits (required)

- [x] Keep AGPL-3.0 (`license`)
- [x] Credit **lucky4luuk** (original, open source — cite authorship) and **Zesty_Maple98** (Redux) — `CREDITS.md`, `NOTICE`, README Credits, listing Credits only (not app author / file headers)
- [x] lucky4luuk: open-source release; authorship citation required (stated in Credits)
- [x] Zesty_Maple98 official permission received (stated in Credits)
- [x] Scintilla GT3 listing photo-mode stills — courtesy permission obtained (stated in `CREDITS.md` / `LISTING.md`)
- [x] Confirm BeamNG forum username on the Repo upload form (do not store the handle in this tree)
- [x] Link **your** GitHub source on the listing (`LISTING.md` / `info.json`)

## B. What ships vs what stays private

Player zip should contain only runtime content. Dev tooling must not ship.

| Include in **core** zip | Include in **compat** zip (tires repo) | Exclude from both |
| --- | --- | --- |
| `lua/` (no lap harness) | `vehicles/` (`*_NTF` JBeams + public Scintilla `.pc`) | `tools/`, `.vscode/`, `.git/` |
| `ui/`, `scripts/` | `mod_info/TWTRS_COMPAT/` | Companion car meshes/textures |
| `mod_info/TWTRS_NTF/` | tires-repo `COMPAT_TIRES.md`, `license`, `NOTICE`, `CREDITS.md` | `tools/output/`, soft-sim dumps |
| docs + `COMPAT_TIRES.md` pointer | — | Old Redux `resource_id` leftovers; **`ui/modules/apps/tireWearThermalsHeavy/`** (dev Pitwall) |

**Why two zips / two git repos:** a package that contains `vehicles/` is mounted as vehicle-only — core UI/Lua never load. Core testers clone this repo; vehicle parts come from **Node-Thermal-Friction-Tires**.

- [x] Document exclude list (this file + packer)
- [x] Stop loading `tireWestCoastLapTest` for players
- [x] Ship **Classic / Crew** UI apps in public zip (Driver removed)
- [-] **Pitwall Heavy** — dev/testers only; lives in git + `-dev` unpack, **not** in public zip
- [x] Optional: omit `tireWestCoastLapTest.lua` from release zip (packer excludes it; file remains in git for tools)
- [x] Document compatibility tires (`COMPAT_TIRES.md` pointer); companion lives in the tires repo
- [x] Clean-zip smoke: core Apps visible when `vehicles/` is **not** in the core package
- [x] Smoke-test NTF Soft/Med/Hard on Scintilla GT3 (WCU Track 15°C) — band locked
- [ ] Smoke-test Pigniteon ETKC NTF parts before advertising that companion specifically (optional; Scintilla path confirmed)

## C. Identity & metadata (new Repo resource)

Do **not** reuse Redux’s resource identity. This is a new listing derived from open source.

- [x] New title: `Node-Thermal Friction`
- [x] Polished tagline + BBCode description (`LISTING.md`, `mod_info/TWTRS_NTF/info.json`)
- [x] Version string `0.1.2` (no version in zip filename; 0.1.1 was the first listed drop)
- [x] Zip name draft: `NodeThermalFriction.zip` (add `_YourBeamNGUser` before upload if needed)
- [x] Removed Redux `resource_id` / `MXFQY32S5` / foreign owner fields / stale hashes
- [x] Local placeholder tagid `TWTRS_NTF` (Repo will assign official tag on upload)
- [x] BeamNG forum username confirmed on the Repo upload form (handle not stored in this tree)
- [x] Icon / preview images — locked heroes + four-UI gallery + ducts
- [ ] Category confirmed on upload form
- [x] Prefix: Beta (private tester); street/truck/wet still open; race slicks + Sport / Sport Plus heat locked


## D. Technical readiness

- [x] Game version: verify on current BeamNG (0.39+) clean profile / current install
- [x] No Lua load errors (`main function has more than 200 local variables`, missing modules) — local-cap work landed earlier
- [x] Vehicle spawn + thermals/wear/grip behave (RWD Soft/Med/Hard + FWD/AWD Soft edge cases)
- [x] UI apps appear and stream data (Pitwall stint/odo + heat knobs verified live)
- [x] Brake duct sliders appear and save in `.pc` (user tech check 2026-08-14)
- [x] No dependency on companion draft mod (user tech check 2026-08-14)
- [x] Only **one** copy of this mod enabled (user tech check 2026-08-14)
- [x] Hardcoded VFS paths: reviewed / no-op for packaged installs (user tech check 2026-08-14)

## E. Packing (zips)

Correct zip root = top-level game folders, **not** a parent `Node-Thermal-Friction-main/` folder. Forward-slash zip paths required (packer uses Python zipfile).

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'NodeThermalFriction.zip'
```

- [x] Use `tools/scripts/Pack-Release.ps1` (POSIX paths; core only — no `vehicles/`)
- [x] Core zip roots: `lua/`, `ui/`, `scripts/`, `mod_info/TWTRS_NTF/` — **no** `vehicles/`
- [x] Compat zip: pack from Node-Thermal-Friction-Tires (`vehicles/`, `mod_info/TWTRS_COMPAT/`)
- [x] Install **core + compat** → Apps still appear; NTF tires selectable (Scintilla confirmed 2026-08-14)
- [x] No missing meshes on NTF tire swap; HUD classifies Soft/Med/Hard correctly
- [x] Confirm compat zip has **no** third-party meshes — only `vehicles/common/*_NTF*.jbeam` plus `vehicles/scintilla/gt3_ntf_*.pc`
- [x] Tag / commit both artifacts from the same git revision before Repo upload (packed from 7735a6e / main merge)
- [ ] Optional: Pigniteon ETKC NTF parts smoke before advertising that companion specifically

## F. Repo submission (two resources)

Upload **both** as **new** resources (not updates to Redux 29934). Core zip from this repo; Compat zip from the tires repo.

### F1. Core — Node-Thermal Friction

- [x] Upload `NodeThermalFriction.zip`
- [x] Paste core BBCode from `LISTING.md`; gallery: hero → `ui_four_apps` → `ducts`
- [x] Category confirmed on form
- [x] Approved / listed: https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/ (keep zip filename stable)

### F2. Compat Tires — second listing

- [x] Decision: Compat is a **second Repo resource** (not bundled / not “later only”)
- [x] Upload `NodeThermalFriction_CompatTires.zip`
- [x] Paste Compat BBCode from the tires repo `LISTING.md`; gallery: Compat hero
- [x] Category confirmed on form (Vehicles/Parts likely)
- [x] Approved / listed: https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/
- [ ] Cross-link core ↔ Compat in both descriptions (BBCode in `LISTING.md`)
- [ ] Optional: Pigniteon ETKC smoke before advertising that companion in Compat listing

## G. Post-publish maintenance

- [ ] Keep `main` for ongoing development; merge publish polish selectively
- [ ] Updates: bump version on **both** resources when JBeams or thermals change together (core repo + tires repo)
- [ ] When changing physics: re-test clean zip install before each update

---

## Quick start (this branch)

1. Finish sections A–D locally and in-game.  
2. Run `tools/scripts/Pack-Release.ps1` (emits core + Compat zips).  
3. Verify both zip layouts.  
4. Submit **two** new BeamNG Repo resources (core, then Compat).
