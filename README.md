# Node-Thermal Friction

> **`0.2.2` (Beta)** — public source on `main`. V2 node wear + per-tire thermals. See
> `tools/V2_FRICTION_CONTRACT.md` and `tools/V2_NODE_WEAR_SPIKE.md`.
> Friction **A1**: node μ owns contact feel; soft scalar ×0.15 ages Cond; flatspot
> removed; lock is native. Soft life A3b + Soft→Med→Hard Belasco ladder locked.
> Round-2 fleet heat dial-back is **tester-owned** (no further rate edits unless they
> report a clear miss). **Pitwall Heavy** is **dev/testers-only** (git / `-dev`; not in
> release zip). Classic / Crew are the player-facing HUDs.
>
> Where to read: `tools/DOCUMENTATION.md`. The open test is `tools/VERIFICATION.md`.
> The copy loaded for this stretch is `mods/unpacked/Node-Thermal-Friction-work`.

A variation / continuation of earlier open-source BeamNG.drive tire thermals/wear mods.
Upstream authors are listed under **Credits** below.

## Two mods (one sentence each)

| Package | What it is |
| --- | --- |
| **Core** (this repo) | Thermals, wear, friction, ducts, Classic/Crew HUDs. No `vehicles/`. |
| **Compat Tires** (`Node-Thermal-Friction-Tires`) | Optional `*_NTF` JBeam clones + Scintilla GT3 configs. Needs core. |

Install core alone for any car’s stock tires. Add Compat only when you want NTF-named parts / Scintilla GT3 NTF configs. Never merge both into one zip — BeamNG hides UI/Lua if `vehicles/` is present.

## Credits

This project builds on the work of:

| Author | Role |
| --- | --- |
| **[lucky4luuk](https://www.beamng.com/members/lucky4luuk.53119/)** | Original mod author (open source; cite authorship) — [Luuk's Tyre Thermals and Wear](https://www.beamng.com/resources/luuks-tyre-thermals-and-wear-mod.26947/) |
| **[Zesty_Maple98](https://www.beamng.com/members/zesty-maple98.393895/)** | Expanded / reworked the original — [Tyre Wear and Thermals Redux](https://www.beamng.com/resources/tyre-wear-and-thermals-redux.29934/) (permission received for Node-Thermal Friction) |

Source lineage remains AGPL-3.0 (see `license`). Thank you to both authors for releasing their work as open source.

### Related links

- **BeamNG Repo (core):** https://www.beamng.com/resources/tire-wear-and-thermals-respin.39082/
- **BeamNG Repo (Compat Tires):** https://www.beamng.com/resources/tire-wear-and-thermals-respin-%E2%80%94-compat-tires.39083/
- Node-Thermal Friction discussion: https://www.beamng.com/threads/tire-wear-and-thermals-respin-%E2%80%94-discussion-feedback-compat.111238/
- Redux / upstream discussion: https://www.beamng.com/threads/tyre-wear-and-thermals-mod-discussion.97035/
- Redux source (upstream): https://github.com/ample-samples/tyre-thermals-and-wear

## Layout

BeamNG requires the runtime folders below; do not rename them.

| Path | Role |
| --- | --- |
| `lua/vehicle/extensions/auto/` | Main vehicle physics extension (auto-loaded) |
| `lua/vehicle/extensions/` | Helpers + short-name shim |
| `lua/ge/extensions/` | Game-engine extensions (ducts, HUD bridge, lap harness) |
| `lua/common/extensions/` | Shared utilities |
| `scripts/tireWearThermals/` | Mod entry (`modscript.lua`) |
| `ui/modules/apps/` | In-game tire HUD apps (Classic / Crew = player; **Pitwall Heavy = dev/testers only**) |
| `mod_info/TWTRS_NTF/` | Core Node-Thermal Friction resource metadata |
| `tools/` | Dev soft-sims, WC lap triggers, fixtures — not required to play |
| `.vscode/settings.json` | Editor Lua language-server config only |

See `tools/DOCUMENTATION.md` for which file owns each claim, then `tools/README.md` for soft-sim / telemetry workflow.  
Optional vehicle parts (JBeam clones / extra configs): **Node-Thermal-Friction-Tires** — not shipped in this repo. See **`COMPAT_TIRES.md`**.

## Local dev install (unpacked)

Use **`-dev`** folder names under `mods/unpacked/` so Repo release zips never collide with git-synced copies:

| Repo | Unpacked folder |
| --- | --- |
| Core (this repo) | `Node-Thermal-Friction-dev` |
| Node-Thermal Friction Tires (`Node-Thermal-Friction-Tires`) | `Node-Thermal-Friction-Tires-dev` |

This stretch is loaded from `Node-Thermal-Friction-work`. Packing still uses the `-dev` folder name so a Repo zip does not overwrite that working copy.

Enable **only one** core thermals unpack at a time (disable original/Redux). **Testers stay on `-dev` files** — disable the BeamNG Repo copies of Node-Thermal Friction (core **39082** / Compat **39083**) while git-unpacked mods are enabled, so Repo zips cannot overwrite local work. Public listing is for other players; tester feedback should come from `-dev`.

## Publishing

BeamNG Repo prep: polish on `testing/main`, merge to `main` for the public source link. See **`PUBLISH_CHECKLIST.md`**.

Build release zips (excludes `tools/` and the WC lap harness). This repo is **core only** — no `vehicles/`. Companion tires pack from **Node-Thermal Friction Tires** (`Node-Thermal-Friction-Tires`):

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'NodeThermalFriction_YourName.zip'
```

Repo listing copy-paste (core): **`LISTING.md`**.  
Companion tires: **`COMPAT_TIRES.md`**.

## Brake coupling (non-goals)

Node-Thermal Friction reads native brake surface/core temps and soaks the tire rim/carcass only. It does **not** replace native brake thermals, write `brakeTypeSurfaceCoolingCoef` for duct boost (restore-only), own torque fade / pad μ / ABS, or use arcade brake-bite grip hacks. Ducts affect tire/rim air cooling and brake→rim soak — not native rotors.
