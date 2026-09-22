# BeamNG Repo listing (copy-paste)

**Two GitHub repos / two Repo resources** (required — `vehicles/` cannot live in core):

| Resource | GitHub | BeamNG Repo | Zip | Tag id (local) |
| --- | --- | --- | --- | --- |
| **Core** — thermals + UI | Node-Thermal-Friction (display: **Node-Thermal Friction**) | [39082](https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/) | `NodeThermalFriction.zip` | `TWTRS_NTF` |
| **Compat Tires** — second listing | Node-Thermal-Friction-Tires | [39083](https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/) | `NodeThermalFriction_CompatTires.zip` | `TWTRS_COMPAT` |

Keep each zip filename stable across updates. **Listed 2026-08-18.** Cross-link both Repo URLs in each resource description (paste blocks below).

---

## Core resource

| Field | Value |
| --- | --- |
| **Title** | Node-Thermal Friction |
| **Tagline** | Private tester — V2 node wear + thermals (friction A1). Public Repo paused. |
| **Version** | 0.2.1 |
| **Zip filename** | `NodeThermalFriction.zip` (stable Repo id; display title is Node-Thermal Friction) |
| **Prefix** | Beta |

| **Category** | Utility / Gameplay (confirm on upload form) |

---

## Description (BBCode)

```bbcode
[B]Node-Thermal Friction[/B]
Open-source tire temperature, wear, and grip simulation for BeamNG.drive.

This is a [B]new[/B] resource (not an update to Redux). It continues the AGPL lineage of earlier open-source tire thermals/wear mods (formerly listed as Node-Thermal Friction), with further thermals/wear tuning and BeamNG 0.39 compatibility work. Upstream authors are listed under Credits.

[B]Per-tire profiles — not a universal config[/B]
Node-Thermal Friction does [B]not[/B] apply one tire setup to the whole car. Each fitted tire is classified independently from its JBeam (name, [I]treadCoef[/I], [I]softnessCoef[/I], purpose/duty) and receives its own thermals, wear, and grip profile. A Sport front and a Race rear do not share knobs. Classic / Crew show live tread, grip, and temps per corner.

[HR][/HR]
[B]Credits[/B]
• [USER=53119]@lucky4luuk[/USER] — original [I]Tyre Thermals and Wear[/I] (open source; authorship cited)
• [USER=393895]@Zesty_Maple98[/USER] — [I]Tyre Wear and Thermals Redux[/I] expansion (permission received)

Full attribution is also in CREDITS.md / NOTICE inside the package.

[B]Listing images[/B]
Hero / gallery stills show the [I]Civetta Scintilla GT3[/I] from [B]Scintilla GT3 Racing Parts[/B] (Exchy / Turbo49 / Cyborella et al.). Used with [B]courtesy permission[/B] from the pack authors. Node-Thermal Friction does not ship that pack’s meshes, textures, or sounds.
Vehicle mod: [URL]https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/[/URL]

[HR][/HR]
[B]Features[/B]
• Per-tire profiles (classification → dedicated heat/wear/grip pack). Not a car-wide universal tire config
• Tire thermals driven by slip, load, camber, brakes, and surface
• V2 friction: thermal wheel μ + clean-room node contact wear (Policy A / coherence A1). Soft scalar ages Cond; node μ owns contact feel
• Compound-aware behaviour (street → sport → race / slick spectrum)

• Locked NTF slick ladder (Hard C2 / Medium C3 / Soft C4) with Soft > Medium > Hard wear rates
• Locked street Sport heat and Sport Plus heat+wear (live Belasco / Track ~15°C, ~22 km protocol)
• 20" Sport compounds classify as Sport (name + tread routing; not utility)
• Track Day heat locked for now (between Sport Plus and Hard C2)
• Layout-aware Soft drive heat (FWD / AWD fronts) — keeps Hot under abuse without rewriting compound knobs
• Pressure, load, and surface effects on grip
• Brake cooling duct sliders (Tuning → Brakes; saved in .pc configs)
• UI apps: Classic / Crew (player HUDs). **Dev Pitwall** (testers): dense engineer telemetry — not in public zip
• Dev Pitwall (`-dev` / git): stint/odo distance, heat-knob chips, node-spike debug (testers only)
• Multiplayer-compatible vehicle extension
• BeamNG 0.39-aware pack-air / draft coexistence (no dependency on extra draft mods)
• Optional [B]NTF[/B] selectable tire clones + four matched Scintilla GT3 race configs (second resource — meshes stay in those mods)

[HR][/HR]
[B]How to use[/B]
1. Install / enable the mod (disable any older thermals-and-wear unpack if present).
2. Spawn a vehicle.
3. Apps menu → add [B]Node-Thermal Friction[/B] (Classic or Crew). **Dev Pitwall** is for testers/engineering only — not shipped in the public zip.
4. Optional: Tuning → Brakes → Front/Rear duct opening (1% = closed, 100% = fully open).
5. Optional (compatibility tires): install [B]Node-Thermal Friction — Compat Tires[/B] ([URL]https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/[/URL]), plus [I]Scintilla GT3[/I] or [I]Pigniteon ETK Racing[/I] for meshes. Scintilla: pick a [B]GT3 NTF[/B] config (Endurance Hard/Medium/Soft or Qualify Supersoft), or Parts → tires → [B]NTF[/B]. Author configs still default to upstream tires.

[HR][/HR]
[B]Requirements[/B]
• Current BeamNG.drive (developed/tested with 0.39-era builds)
• No required companion mods for core thermals/wear
• Optional [B]Compat Tires[/B] is a [B]second Repo resource[/B] ([URL]https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/[/URL]) — cannot ship inside this zip or the UI apps vanish
• Compatibility tires also need the matching car mod for meshes only (Scintilla GT3 Racing Parts / Pigniteon ETK Racing). Node-Thermal Friction does not redistribute those meshes.

[B]Known limitations (Beta — street/wet still open)[/B]
• Street / utility / wet compounds still need broader surface A/B. Locked from live Track ~15°C stints: race Soft/Med/Hard, street Sport heat, Sport Plus heat+wear. Track Day heat locked for now.
• Graining is experimental (cold out-lap); not a locked band
• UI layout can be imperfect on vehicles with more than four wheels
• Dev Pitwall (testers): dense diagnostics + node-spike debug — not a public player feature
• Some third-party race tires use unconventional friction; use the optional NTF clones or wait for upstream fixes
• AWD Soft can still spike one front under heavy brake soak — treated as a harsh-drive ceiling, not a compound miss
• Scalar flatspot removed — lock/camber damage is node-sector wear, not a separate flat % bar
• Wear that feeds grip: node contact μ (events) + thermal curve; soft scalar ages Cond for HUD / leak clocks (coherence A1)


[HR][/HR]
[B]Links[/B]
This resource: [URL]https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/[/URL]
Compat Tires (optional parts): [URL]https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/[/URL]
Source: GitHub: [I]Node-Thermal-Friction[/I]
Discussion (Node-Thermal Friction): [URL]https://www.beamng.com/threads/tire-wear-and-thermals-respin-%E2%80%94-discussion-feedback-compat.111238/[/URL]
Discussion (upstream Redux thread): [URL]https://www.beamng.com/threads/tyre-wear-and-thermals-mod-discussion.97035/[/URL]
Original: [URL]https://www.beamng.com/resources/luuks-tyre-thermals-and-wear-mod.26947/[/URL]
Redux: [URL]https://www.beamng.com/resources/tyre-wear-and-thermals-redux.29934/[/URL]
Scintilla GT3 Racing Parts (listing vehicle / optional compat meshes): [URL]https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/[/URL]

[B]License[/B]
GNU Affero General Public License v3 — see the [I]license[/I] file in the package. Source must remain available for network-use derivatives under AGPL.
```

---

## Compat Tires resource (second listing)

Pack, inventory, and listing BBCode live in the Compat unpack / tires repo (`README.md`,
`INVENTORY.md`, `LISTING.md` under `Node-Thermal-Friction-Tires-dev`). Do not put
`vehicles/` in this core tree.

**Live listing:** https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/

**Core ↔ Compat cross-links (paste on both Repo pages):**

```bbcode
[B]Requires[/B] the core heat/wear/apps mod: [URL]https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/[/URL]
```

```bbcode
Optional parts: [B]Compat Tires[/B] [URL]https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/[/URL]
```

Pack Compat zip from core tools: `.\tools\scripts\Pack-Compat-Release.ps1`

Gallery for that listing: tires unpack `mod_info/TWTRS_COMPAT/images/listing_hero.jpg` (icon: `icon.jpg`). Core still keeps the compat hero master under `tools/listing/locked/ntf-compat-hero.jpg`.

---

## Changelog (0.2.1)

- Private-beta polish: Classic/Crew blank-stream + Cond labeling; duct Tuning copy; Compat README/inventory/pack script
- Spectra honesty: truck/utility/AT/vintage labeled provisional (`tools/SPECTRA_STATUS.md`)
- Round-2 fleet heat dial-back (tester-owned); numRays 16 baseline locked
- Public Repo update still paused

## Changelog (0.1.2)

- Street Sport heat locked from live Belasco stints
- Sport Plus heat and wear locked (no more cooked-front blister on a ~22 km stint)
- 20" Sport tires now show up as Sport, not utility
- Graining is more likely on a cold out-lap (still experimental)
- Track Day heat locked for now

## Changelog (0.1.1)

- Race slicks (Soft / Medium / Hard) heat and wear locked from live Track ~15°C stints
- Front-drive and all-wheel Soft cars keep driven fronts from cooking as easily
- Pitwall shows stint distance and extra debug numbers
- Extra NTF GT3 Hard / Medium / Soft / Supersoft tires plus public Scintilla configs (Compat Tires pack)

---

## Screenshot / gallery plan (Repo page)

Yes — BeamNG Repo listings support **multiple images** with **captions/descriptions** on the resource page (upload gallery + optional notes in the description BBCode).

### Locked heroes (use these)

| Image | Resource | Caption / description (paste on upload) |
| --- | --- | --- |
| `mod_info/TWTRS_NTF/images/listing_hero.jpg` (icon: `icon.jpg`) | **Core** Node-Thermal Friction | **Node-Thermal Friction** — Tires heat up, wear down, and lose grip. Vehicle: Scintilla GT3 Racing Parts (listing stills used with author permission) — https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/ |
| `mod_info/TWTRS_NTF/images/ui_four_apps.jpg` | **Core** Node-Thermal Friction | **Apps in one shot** — Pitwall (dev engineer), Crew (carcass + stint fade), and Classic (compact inner / center / outer temps). Driver HUD removed. |
| `mod_info/TWTRS_NTF/images/ducts.jpg` | **Core** Node-Thermal Friction | **Brake cooling ducts** — Tuning → Brakes → Front/Rear Cooling Ducts (1% = closed, 100% = open). Saved with the car. |
| `tools/listing/locked/ntf-compat-hero.jpg` | **Compat Tires** companion (shipped from the tires repo) | **Node-Thermal Friction Tires** — Optional extra `*_NTF` GT3 tire parts (3D models stay in the car mods). Install beside core Node-Thermal Friction. |
| `mod_info/TWTRS_NTF/images/tire_thermal_map.jpg` (draft) | **Core** Node-Thermal Friction (optional 4th gallery) | **Tire thermal map** — Inner / center / outer tread in Pitwall colors (cyan-teal cooler, green usable, amber hotter) plus surface, carcass, and rim-soak callouts. |

Masters (do not restyle without unlock): `tools/listing/locked/ntf-core-hero.jpg`, `ntf-compat-hero.jpg`, `ntf-ui-four-apps.jpg`, `ntf-ducts.jpg`. Draft (not locked): `tools/listing/drafts/ntf-tire-thermal-map.jpg`.

### Gallery captions — the apps (from `ui_four_apps.jpg`)

Use as one image with this description, or split into bullets in the listing body:

1. **Pitwall** (left) — Dev engineer view: weather, per-tire tread / grip / PSI, surface vs carcass heat, brakes / rim soak, extra test numbers (not in public zip).
2. **Crew** — Four-corner crew view with tread, O|M|I zones, grip, PSI, temp state, and surface heat maps.
3. **Classic** — Compact inner / center / outer temperature blocks per axle with tread condition.

Exposure on the source capture was pulled down for listing readability; UI panels were kept intact.

Gallery order tip: hero → `ui_four_apps` → `ducts`.

---

## Thumbnail / icon

Locked poster icons replace the older tire/pit thumbnail:

- Core: `mod_info/TWTRS_NTF/icon.jpg`
- Compat: tires repo `mod_info/TWTRS_COMPAT/icon.jpg` (master: `tools/listing/locked/ntf-compat-hero.jpg`)

`icon-redux-reference.jpg` (if present locally) is archive-only — do not ship.

## Credits note

- **lucky4luuk** — original work released as open source; cite authorship.
- **Zesty_Maple98** — Redux expansion; permission received for this Node-Thermal Friction.
- **Scintilla GT3 Racing Parts** (Exchy / Turbo49 / Cyborella et al.) — courtesy permission for listing photo-mode stills that show that vehicle. Models stay in their pack: https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/

## Compatibility tires (optional companions — not Node-Thermal Friction authors)

Mention on the listing when advertising the stop-gap parts; pointer: `COMPAT_TIRES.md`. Full inventory is in the tires repo.

- Scintilla GT3 Racing Parts — https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/
- Pigniteon ETK Racing — credit the pack author as on that Repo listing

Do not ship their models/textures inside either Node-Thermal Friction zip. Compat tires are a **second GitHub repo and BeamNG Repo resource**: Node-Thermal-Friction-Tires
