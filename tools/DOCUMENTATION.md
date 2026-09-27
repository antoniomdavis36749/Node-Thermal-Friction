# Documentation

Use this index to find the record. One file owns each claim. When two files disagree, the owner wins, and the other file gets corrected in the same edit.

## Read in this order

1. `tools/VERIFICATION.md` — the open test. Read it before a drive or a retune.
2. `tools/V2_FRICTION_CONTRACT.md` — who writes grip, the Phase 1 lock, and Phase 2 status.
3. `tools/SPECTRA_STATUS.md` — which compound bands are locked, provisional, or a fallback.
4. `tools/V2_NODE_WEAR_SPIKE.md` — node-wear flags and the retest notes for those flags.
5. `README.md` — what the mod is, credits, and install. The copy BeamNG is loading for this stretch is `mods/unpacked/Node-Thermal-Friction-work`.
6. `tools/history/CHANGELOG.md` — what landed. `LOCKS.md` for decisions that stay. `FAILURES.md` for attempts that must not return.
7. `PUBLISH_CHECKLIST.md` — packing. The public Repo update is paused.

## Who may say what

| File | Owns | Does not own |
| --- | --- | --- |
| `VERIFICATION.md` | The open card and what that card is allowed to change | Compound numbers, grip policy |
| `V2_FRICTION_CONTRACT.md` | Policy A, the Phase 1 lock, Phase 2 status | The live A/B steps |
| `SPECTRA_STATUS.md` | Band maturity: locked, provisional, fallback | The open drive |
| `V2_NODE_WEAR_SPIKE.md` | Node-wear flags and their retests | Thermal grip bands |
| `README.md` | Install, credits, package split | Today's test result |
| `REFACTOR_SPLITS.md` | Architecture stages and the in-load check | Heat numbers, the open drive |
| `history/LOCKS.md` | Dated locks | Today's open drive |
| `history/FAILURES.md` | Rejected attempts and defects that must not return | A new theory that has not been driven |
| `history/CHANGELOG.md` | What landed: loads, smokes, logs, code | A lock. Copy a landed row into `LOCKS.md` only when the protocol locks it |
| Code comments | A rule the next edit has to see | Dates, rounds, and LOCKED claims. Those live in `tools/history/` |

## Current record (26 Sep 2026)

- Phase 1 native API is locked. The evidence is a smoke on the Scintilla GT3 and a street car.
- Phase 2 is coded. The GT3 smoke passed, the FWD exit with damps on was a smoke, and street heat is the 26.8 km Corse log. Phase 2 is not committed.
- Stick flex fade is logged and locked: zero above slip ratio 0.30. Layout damp stays on. Drag `longGripMult` 1.18 stayed through two Burnside launches. Locked-band outputs are in `tools/golden/locked-bands.txt`. NodeProbe stays in the working copy and is omitted from the release zip. Player wear is stored in `settings/ntf-player-wear/`. Public source is `main` at 0.2.2. The steps are in `VERIFICATION.md`.
- Native rubber temperature is a logged thermometer. Node-Thermal Friction still writes grip.
- The gate scripts follow the live per-tire gates. `Test-ReplayRecordedThermal.ps1` runs the real module outside the game. A script PASS is still not a drive verdict.

## Off track

- A locked number is edited from a comment, and the protocol in the contract or `SPECTRA_STATUS.md` was not the one that missed.
- The README `-dev` folder is treated as the copy BeamNG is running. This stretch loads `Node-Thermal-Friction-work`.
- A new status file is started. Update the owner in the table above.
