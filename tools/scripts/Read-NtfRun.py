"""Read NTF telemetry runs with one fixed set of definitions.

    python tools/scripts/Read-NtfRun.py stamp            write the code stamp before a drive
    python tools/scripts/Read-NtfRun.py list  [--file F] runs in a telemetry CSV
    python tools/scripts/Read-NtfRun.py read  [--file F] [--run ID | --last]
    python tools/scripts/Read-NtfRun.py pair  RUN_A RUN_B [--file F] [--file-b G]   noise card
    python tools/scripts/Read-NtfRun.py split [--file F] [--run ID]   one CSV per run on D:\\ntf-logs\\runs
    python tools/scripts/Read-NtfRun.py predict RUN_A RUN_B --rolling-delta 0.3
    python tools/scripts/Read-NtfRun.py predict --run ID --knob rolling|flex|soak --axle front|rear|all --scale 1.35

The settled median is the last third of moving kilometres, and it starts at or after km 1.
A straight rolling prediction uses 1.5°C per tenth, from the undriven straight at scale 2.5
and 4.2. It is not a replay of the 1 Hz thermal step.

Definitions:
- Moving: airspeed above 8 m/s. Files without airspeed use km advancing.
- Settled window: the last third of the run's moving km.
- Edge: the row's bandHi and bandLo. Older files take --window LO HI.
- Driven: the tire reads driven on more than half of its moving rows.
- Over the edge: when the run has #FLASH rows, the sum of those over-seconds for
  the tire, plus an open flash still in hotS. Otherwise, moving seconds with the
  middle above bandHi, from the gap between 1 Hz rows. Parked time after the
  finish does not count.
- A crash or spin ends the run at the last sample before a tire middle jumps
  more than 40°C in one sample, or the car slows faster than 28 m/s² (about
  2.9 g). Corner flashes and braking stay under both. --end-km cuts by hand.
- Rows on a compound other than the tire's main compound are dropped.
- Heat share: rollingJ, flexJ, soakJ, slipJ, driveJ, and workJ when those columns
  are present and their sum is above zero. Older logs use the instantaneous watt
  columns. "over" uses only the rows with the middle above bandHi.
- Driven slip: median native slip ratio of a driven tire in the first third and in the
  settled window. On a grid track, a settled median above 0.02 is not a clean straight.
- Speed thirds: median airspeed in each third of the moving km, one sample per timestamp.
  On a grid track, the settled third is not a cruise read when it is more than 5 m/s off
  the middle third. The first third includes the launch, so it is printed and not gated.
- Cold start: the first moving middle. In the v6 log the coldest tire starts near 36°C
  (median 36.4°C, n=85). The S-01 straight started at 37.7°C. Above 45°C is a warm start.
- A grid run under 12 km is a short straight.
- Pressure: the first moving psi and the median psi in the settled window.
  ntfPsi is the cavity pressure NTF computes. nativePsi is the group pressure
  BeamNG is using. throttle and brakePedal are the pedal on that same row.
- Fit: T = Tinf - A*e^(-km/L) on km 0.3 to 6, printed on a grid run only when speed is held.
  L is the best of 0.5 to 11.9 km. It screens a step. A vote still wants 12 km.
- Heat-share prediction: (scale - 1) times that knob's share of the settled heat times the
  settled rise above ambient. The band is half of that to double it. Static cooling is a
  loss, not a share, so the pair form with --rolling-delta still owns a straight rolling step.

Heat-share back-test, baseline 20261010-173736-194181-1, the lap before front 1.35 and rear 0.74.
The logged lap is 20261010-175842-196847-1. One knob at a time. Hand is the card's figure.
  flex front 1.35    +2.5 and +2.2 C     hand +2.3. Logged fronts +3.4 and +7.6, with soak moved too.
  soak front 1.35    +6.1 and +5.9 C
  flex rear 0.74     -5.4 and -5.3 C
  soak rear 0.74     -2.5 and -2.3 C     together -7.9 and -7.6, against the hand figure of about -8. Logged -3.7 and -6.2.
Soak 1.3 to 1.1 (scale 0.846) on 20261010-110311-73280-4 is -2.9 C on the RL. The hand figure was
about 2.7. The half of that band does not clear the 2.2 C floor.
Static cooling stays a hand estimate: 0.100 about 3 against 2.6 logged, 0.140 was 2.6 against 3.6,
and 0.170 was a 2.7 drop against a 1.9 rise.

An AI car with tools/FULL_HEAT_AI writes tools/output/ntf-ai-<id>.csv. Pass that path
to --file. The default file stays the driver's log.

The script reads logs. It does not edit Lua.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import hashlib
import math
import shutil
import statistics
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1].parent
OUTPUT = ROOT / "tools" / "output"
STAMP_FILE = OUTPUT / "code-stamp.txt"
ARCHIVE = Path("D:/ntf-logs")
INDEX = ARCHIVE / "index.csv"
CODE_EXTS = (".lua", ".jbeam")
MOVING_MS = 8.0
CRASH_DECEL = 28.0
CRASH_MID_JUMP = 40.0
CRASH_WINDOW_S = 1.5
DRIVEN_NM = 40.0
CLEAN_STRAIGHT_SLIP = 0.02
SPEED_HELD_MS = 5.0
STRAIGHT_MIN_KM = 12.0
# v6 coldest-tire first moving middle: median 36.4°C, 95th percentile 40.8°C, max 45.3°C, n=85.
WARM_START_C = 45.0
FIT_KM = 6.0
HEAT_COLS = (("rolling", "rollingHeat"), ("flex", "flexHeat"), ("soak", "brakeSoak"),
             ("slip", "slipHeat"), ("work", "workHystHeat"), ("drive", "driveHystHeat"))
JOULE_COLS = (("rolling", "rollingJ"), ("flex", "flexJ"), ("soak", "soakJ"),
              ("slip", "slipJ"), ("work", "workJ"), ("drive", "driveJ"))

INDEX_COLS = [
    "analyzedAt", "sourceFile", "runId", "startRow", "car", "track", "config", "wheel", "class",
    "compound", "roll", "lo", "hi", "kmMoving", "medianSpeedMs", "settledMedian", "p95", "peak",
    "finish", "overS", "longestOverS", "crashKm", "verdict", "ambientC", "trackC", "stamp",
]


# ---------------------------------------------------------------- code stamp

def code_hash(root: Path = ROOT) -> str:
    h = hashlib.sha256()
    files = sorted(
        p for p in root.rglob("*")
        if p.is_file() and p.suffix.lower() in CODE_EXTS
        and ".git" not in p.parts and "tools" not in p.relative_to(root).parts
    )
    for p in files:
        rel = p.relative_to(root).as_posix()
        h.update(rel.encode())
        h.update(b"\0")
        h.update(hashlib.sha256(p.read_bytes()).digest())
    return h.hexdigest()[:10]


def git(*args: str) -> str:
    try:
        return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True,
                              check=False).stdout
    except OSError:
        return ""


def cmd_stamp(_args: argparse.Namespace) -> int:
    head = git("rev-parse", "--short", "HEAD").strip() or "none"
    dirty = [ln for ln in git("status", "--short").splitlines() if ln.strip()]
    lua = code_hash()
    now = dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    line = f"head={head} dirty={len(dirty)} lua={lua} at={now}"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    STAMP_FILE.write_text(line + "\n", encoding="utf-8")
    print(line)
    if not Path("D:/").exists():
        print("D: is not available. Code snapshot skipped.")
        return 0
    snap = ARCHIVE / "code" / lua
    if snap.exists():
        print(f"snapshot exists: {snap}")
        return 0
    snap.mkdir(parents=True)
    (snap / "diff.patch").write_text(git("diff", "HEAD", "--binary"), encoding="utf-8")
    (snap / "stamp.txt").write_text(line + "\n", encoding="utf-8")
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    for rel in untracked:
        src = ROOT / rel
        if src.suffix.lower() in CODE_EXTS and src.is_file():
            dest = snap / "untracked" / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
    print(f"snapshot: {snap}")
    return 0


# ---------------------------------------------------------------- parsing

@dataclass
class Run:
    run_id: str
    start_row: int
    meta: dict = field(default_factory=dict)
    rows: list = field(default_factory=list)
    flashes: list = field(default_factory=list)
    raw_line: str = ""


def num(row: dict, key: str, default: float | None = None) -> float | None:
    v = row.get(key)
    if v is None or v == "":
        return default
    try:
        return float(v)
    except ValueError:
        return default


def parse_run_line(rec: list[str]) -> tuple[str, dict]:
    meta = {}
    for cell in rec[2:]:
        if "=" in cell:
            k, v = cell.split("=", 1)
            meta[k] = v
    return rec[1], meta


def load_runs(path: Path) -> tuple[list[str], list[Run]]:
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.reader(f)
        header = next(reader)
        has_run_id = "runId" in header
        runs: list[Run] = []
        pending_meta: dict[str, dict] = {}
        pending_raw: dict[str, str] = {}
        pending_flashes: dict[str, list] = {}
        by_id: dict[str, Run] = {}
        legacy: Run | None = None
        prev_wall = None
        last_km: dict[str, float] = {}
        order: dict[str, str] = {}
        idx = 0
        for rec in reader:
            if not rec:
                continue
            if rec[0].startswith("#"):
                if rec[0] == "#RUN" and len(rec) > 1:
                    rid, meta = parse_run_line(rec)
                    pending_meta[rid] = meta
                    pending_raw[rid] = ",".join(rec)
                    if rid in by_id:
                        by_id[rid].meta.update(meta)
                        by_id[rid].raw_line = pending_raw[rid]
                elif rec[0] == "#FLASH" and len(rec) >= 6:
                    def fnum(cell: str) -> float:
                        try:
                            return float(cell)
                        except ValueError:
                            return 0.0
                    flash = {
                        "run": rec[1],
                        "wheel": rec[2],
                        "over": fnum(rec[4]),
                        "hold": fnum(rec[5]),
                        "km": fnum(rec[7]) if len(rec) > 7 else 0.0,
                    }
                    owner = by_id.get(flash["run"])
                    if owner is None:
                        pending_flashes.setdefault(flash["run"], []).append(flash)
                    else:
                        owner.flashes.append(flash)
                elif rec[0] == "#RESET" and not has_run_id:
                    legacy = None
                continue
            if len(rec) < len(header):
                continue
            row = dict(zip(header, rec))
            row["_idx"] = idx
            idx += 1
            name = row.get("wheelName") or row.get("wheel", "")
            row["_name"] = name
            if has_run_id and row.get("runId"):
                rid = row["runId"]
                run = by_id.get(rid)
                if run is None:
                    run = Run(rid, row["_idx"], dict(pending_meta.get(rid, {})), raw_line=pending_raw.get(rid, ""),
                              flashes=list(pending_flashes.pop(rid, [])))
                    by_id[rid] = run
                    runs.append(run)
                run.rows.append(row)
                continue
            wall = num(row, "wall", 0.0)
            km = num(row, "stintKm", 0.0)
            cut = legacy is None
            if prev_wall is not None and wall < prev_wall - 1.0:
                cut = True
            wheel = row.get("wheel", "")
            if wheel in order and order[wheel] != name:
                cut = True
            if name in last_km and km < last_km[name] - 0.05:
                cut = True
            if cut:
                legacy = Run(f"legacy-{row['_idx']}", row["_idx"])
                runs.append(legacy)
                last_km.clear()
                order.clear()
            order[wheel] = name
            last_km[name] = km
            prev_wall = wall
            legacy.rows.append(row)
    return header, runs


# ---------------------------------------------------------------- analysis

def compound(row: dict) -> tuple[str, str]:
    p1, p2 = row.get("profile1", ""), row.get("profile2", "")
    name = p1 if p1 == p2 or not p2 else f"{p1}~{p2}"
    return (name or row.get("profile", "")), row.get("rollScale", "")


def p95(values: list[float]) -> float:
    s = sorted(values)
    return s[min(len(s) - 1, int(round(0.95 * (len(s) - 1))))]


def _share(rows: list[dict], cols: tuple) -> dict | None:
    if not rows or not any(col in rows[0] for _, col in cols):
        return None
    sums = {k: sum(max(0.0, num(r, col, 0.0) or 0.0) for r in rows) for k, col in cols}
    total = sum(sums.values())
    return {k: v / total for k, v in sums.items()} if total > 0 else None


def heat_share(rows: list[dict]) -> dict | None:
    return _share(rows, JOULE_COLS) or _share(rows, HEAT_COLS)


def slip_median(rows: list[dict]) -> float | None:
    vals = [abs(v) for v in (num(r, "slipRatio") for r in rows) if v is not None]
    return statistics.median(vals) if vals else None


def grid_track(track: str) -> bool:
    return "grid" in (track or "").lower()


def tire_axle(name: str) -> str:
    n = name.upper()
    if n.startswith("F"):
        return "front"
    if n.startswith("R"):
        return "rear"
    return ""


def moving_compound(rows: list[dict]) -> list[dict]:
    moving = [r for r in rows if r.get("_moving")]
    if len(moving) < 10:
        return []
    comp = statistics.mode(compound(r) for r in moving)
    return [r for r in moving if compound(r) == comp]


def split_thirds(moving: list[dict]) -> tuple[list[dict], list[dict], float]:
    km = [num(r, "stintKm", 0.0) or 0.0 for r in moving]
    km0, km1 = min(km), max(km)
    span = km1 - km0
    first, settled = [], []
    settled_at = max(1.0, km0 + span * 2 / 3)
    for r, k in zip(moving, km):
        if span > 0 and k < km0 + span / 3:
            first.append(r)
        if k >= settled_at:
            settled.append(r)
    return first, settled, span


def thirds_of(samples: list[tuple[float, float]]) -> list[float] | None:
    if len(samples) < 9:
        return None
    samples = sorted(samples)
    km0, km1 = samples[0][0], samples[-1][0]
    span = km1 - km0
    if span <= 0:
        return None
    buckets: list[list[float]] = [[], [], []]
    for km, value in samples:
        buckets[min(2, int((km - km0) / span * 3))].append(value)
    if any(len(b) < 3 for b in buckets):
        return None
    return [statistics.median(b) for b in buckets]


def speed_thirds(run: Run) -> list[float] | None:
    by_wall: dict[float, tuple[list[float], list[float]]] = {}
    for r in run.rows:
        if not r.get("_moving") or "airspeed" not in r:
            continue
        wall = num(r, "wall", 0.0)
        km, air = num(r, "stintKm", 0.0) or 0.0, num(r, "airspeed", 0.0) or 0.0
        slot = by_wall.setdefault(wall, ([], []))
        slot[0].append(km)
        slot[1].append(air)
    samples = [(statistics.median(km), statistics.median(air)) for km, air in by_wall.values()]
    return thirds_of(samples)


def fit_asymptote(moving: list[dict]) -> tuple[float, float] | None:
    """T = Tinf - A*exp(-km/L) on the first 6 km. Returns (Tinf, L)."""
    pts = []
    for r in moving:
        k, mid = num(r, "stintKm"), num(r, "m")
        if k is None or mid is None:
            continue
        pts.append((k, mid))
    if len(pts) < 8:
        return None
    pts.sort()
    k0 = pts[0][0]
    early = [(k - k0, mid) for k, mid in pts if 0.3 <= k - k0 <= FIT_KM]
    if len(early) < 8 or early[-1][0] < 2.0:
        return None
    best = None
    for step in range(5, 120):
        length = step / 10.0
        xs = [math.exp(-k / length) for k, _ in early]
        ys = [mid for _, mid in early]
        n = len(xs)
        mx, my = sum(xs) / n, sum(ys) / n
        sxx = sum((x - mx) ** 2 for x in xs)
        if sxx <= 0:
            continue
        slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
        tinf = my - slope * mx
        err = sum((tinf + slope * x - y) ** 2 for x, y in zip(xs, ys))
        if best is None or err < best[0]:
            best = (err, tinf, length)
    if best is None:
        return None
    return best[1], best[2]


def mark_moving(run: Run, has_air: bool) -> None:
    prev: dict[str, float] = {}
    for r in run.rows:
        km = num(r, "stintKm", 0.0)
        if has_air:
            r["_moving"] = (num(r, "airspeed", 0.0) or 0.0) > MOVING_MS
        else:
            r["_moving"] = r["_name"] in prev and km > prev[r["_name"]] + 0.001
        prev[r["_name"]] = km


def crash_cut(run: Run, has_air: bool, end_km: float | None) -> float | None:
    if end_km is not None:
        run.rows = [r for r in run.rows if num(r, "stintKm", 0.0) <= end_km]
        return end_km
    samples: dict[float, list[dict]] = {}
    for r in run.rows:
        samples.setdefault(num(r, "wall", 0.0), []).append(r)
    prev_wall = None
    prev: dict[str, tuple[float, float]] = {}
    for wall in sorted(samples):
        rows = samples[wall]
        cut = False
        for r in rows:
            mid, air = num(r, "m", 0.0), num(r, "airspeed", 0.0)
            last = prev.get(r["_name"])
            if last and prev_wall is not None and 0 < wall - prev_wall <= CRASH_WINDOW_S:
                if mid - last[0] > CRASH_MID_JUMP:
                    cut = True
                if has_air and (last[1] - air) / (wall - prev_wall) > CRASH_DECEL:
                    cut = True
            prev[r["_name"]] = (mid, air)
        if cut:
            km = max((num(r, "stintKm", 0.0) for r in samples.get(prev_wall, rows)), default=0.0)
            run.rows = [r for r in run.rows if num(r, "wall", 0.0) < wall]
            return km
        prev_wall = wall
    return None


def tire_report(rows: list[dict], window: tuple[float, float] | None,
                flashes: list | None = None) -> dict | None:
    moving = moving_compound(rows)
    if not moving:
        return None
    comp = compound(moving[0])
    rows = [r for r in rows if compound(r) == comp]
    # Last third of the moving distance, and never the first kilometre.
    # A reset can leave hot brakes that soak the tire before km 1.
    first_rows, settled_rows, span = split_thirds(moving)
    settled = [num(r, "m", 0.0) for r in settled_rows]
    if len(settled) < 3:
        return None
    mids = [num(r, "m", 0.0) for r in moving]
    hi = num(moving[-1], "bandHi") or (window[1] if window else None)
    lo = num(moving[-1], "bandLo") or (window[0] if window else None)
    if "driven" in moving[0]:
        driven_frac = sum(1 for r in moving if r.get("driven") == "1") / len(moving)
    else:
        driven_frac = sum(1 for r in moving if abs(num(r, "propNm", 0.0)) > DRIVEN_NM) / len(moving)
    over = longest = run_s = hold = 0.0
    from_flash = False
    wheel_flashes = [f for f in (flashes or []) if f.get("wheel") == rows[0].get("_name")]
    if wheel_flashes:
        from_flash = True
        over = sum(f["over"] for f in wheel_flashes)
        longest = max(f["over"] for f in wheel_flashes)
        hold = max(f["hold"] for f in wheel_flashes)
        open_hot = num(moving[-1], "hotS", 0.0) or 0.0
        if open_hot > 0.05:
            over += open_hot
            longest = max(longest, open_hot)
    else:
        prev = None
        for r in rows:
            w = num(r, "wall", 0.0)
            step = min(3.0, max(0.0, w - prev)) if prev is not None else 0.0
            prev = w
            hot = hi is not None and r["_moving"] and num(r, "m", 0.0) > hi
            if hot:
                over += step
                run_s += step
                longest = max(longest, run_s)
            else:
                run_s = 0.0
    over_rows = [r for r in moving if hi is not None and num(r, "m", 0.0) > hi]
    med = statistics.median(settled)
    psis = [p for p in (num(r, "psi") for r in settled_rows) if p is not None]
    ntf_ps = [p for p in (num(r, "ntfPsi") for r in settled_rows) if p is not None]
    nat_ps = [p for p in (num(r, "nativePsi") for r in settled_rows) if p is not None]
    verdict = "no window"
    if lo is not None and hi is not None:
        verdict = (f"cold by {lo - med:.1f}" if med < lo
                   else f"hot by {med - hi:.1f}" if med > hi else "inside")
    return {
        "class": "driven" if driven_frac > 0.5 else "undriven",
        "compound": comp[0], "roll": comp[1], "lo": lo, "hi": hi,
        "kmMoving": span, "settledMedian": med, "p95": p95(mids), "peak": max(mids),
        "finish": mids[-1], "overS": over, "longestOverS": longest, "holdS": hold,
        "fromFlash": from_flash, "verdict": verdict,
        "speed": statistics.median(num(r, "airspeed", 0.0) for r in moving) if "airspeed" in moving[0] else None,
        "share": heat_share(moving),
        "shareOver": heat_share(over_rows) if len(over_rows) >= 3 else None,
        "settledShare": heat_share(settled_rows),
        "slipFirst": slip_median(first_rows), "slipSettled": slip_median(settled_rows),
        "startMid": num(moving[0], "m", 0.0),
        "psiFirst": num(moving[0], "psi"),
        "psiSettled": statistics.median(psis) if psis else None,
        "ntfPsiSettled": statistics.median(ntf_ps) if ntf_ps else None,
        "nativePsiSettled": statistics.median(nat_ps) if nat_ps else None,
    }


def analyze(run: Run, has_air: bool, window: tuple[float, float] | None,
            end_km: float | None = None) -> dict:
    mark_moving(run, has_air)
    crash_km = crash_cut(run, has_air, end_km)
    if crash_km is not None:
        run.flashes = [f for f in run.flashes if f.get("km", 0.0) <= crash_km + 1e-6]
    names = sorted({r["_name"] for r in run.rows})
    tires = {}
    for n in names:
        rep = tire_report([r for r in run.rows if r["_name"] == n], window,
                          [f for f in run.flashes if f.get("wheel") == n])
        if rep:
            tires[n] = rep
    first = run.rows[0] if run.rows else {}
    return {
        "car": run.meta.get("car") or first.get("carName", ""),
        "track": run.meta.get("track") or first.get("trackName", ""),
        "config": run.meta.get("config", ""),
        "crashKm": crash_km, "tires": tires,
    }


def fmt(v, spec=".1f") -> str:
    return "-" if v is None else format(v, spec)


def print_checks(run: Run, res: dict) -> None:
    thirds = speed_thirds(run)
    grid = grid_track(res["track"])
    if thirds:
        print(f"  speed by third: {thirds[0]:.1f} / {thirds[1]:.1f} / {thirds[2]:.1f} m/s")
        if grid and abs(thirds[2] - thirds[1]) > SPEED_HELD_MS:
            off = abs(thirds[2] - thirds[1])
            print(f"  SPEED NOT HELD: settled third is {off:.1f} m/s off the middle third"
                  f" (limit {SPEED_HELD_MS:.0f}). The settled median is not a cruise read.")
    km = max((t["kmMoving"] for t in res["tires"].values()), default=0.0)
    if grid and km < STRAIGHT_MIN_KM:
        print(f"  SHORT STRAIGHT: {km:.2f} km moving, under {STRAIGHT_MIN_KM:.0f} km.")
    print("  start C: " + "  ".join(f"{n} {t['startMid']:.1f}" for n, t in res["tires"].items()))
    coldest = min(t["startMid"] for t in res["tires"].values())
    if coldest > WARM_START_C:
        print(f"  WARM START: coldest tire began at {coldest:.1f} C, above {WARM_START_C:.0f} C."
              " Logged cold starts sit near 36 C.")
    if any(t["psiFirst"] is not None for t in res["tires"].values()):
        print("  psi first/settled: " + "  ".join(
            f"{n} {fmt(t['psiFirst'])}/{fmt(t['psiSettled'])}" for n, t in res["tires"].items()))
    if not grid or thirds is None:
        return
    if abs(thirds[2] - thirds[1]) > SPEED_HELD_MS:
        print("  fit withheld: speed is not held, so the first 6 km is not the settled speed.")
        return
    print(f"  fit, first {FIT_KM:.0f} km. A vote still wants {STRAIGHT_MIN_KM:.0f} km.")
    capped = False
    for n in res["tires"]:
        moving = moving_compound([r for r in run.rows if r["_name"] == n])
        fit = fit_asymptote(moving)
        med = res["tires"][n]["settledMedian"]
        if not fit:
            print(f"  {n:<5} fit: fewer than 2 km inside the first {FIT_KM:.0f} km")
            continue
        tinf, length = fit
        capped = capped or length >= 11.85
        print(f"  {n:<5} Tinf {tinf:6.1f}  L {length:4.1f} km  settled {med:6.1f}  miss {tinf - med:+5.1f}")
    if capped:
        print("  FIT NOT SETTLED: L is at the 11.9 km cap, so Tinf is not a screen.")


def print_run(run: Run, res: dict, current_hash: str) -> None:
    meta = run.meta
    print(f"\nRun {run.run_id}  rows {run.start_row}+  car {res['car'] or '?'}  track {res['track'] or '?'}"
          f"  config {res['config'] or '?'}  reason {meta.get('reason', '?')}")
    stamp = meta.get("stamp", "")
    if stamp and stamp != "none":
        lua = dict(p.split("=", 1) for p in stamp.split() if "=" in p).get("lua", "")
        state = "matches current code" if lua == current_hash else "differs from current code"
        print(f"  code {stamp}  ({state})")
    else:
        print("  code: no stamp")
    if meta:
        print(f"  ambient {meta.get('ambientC', '?')} C  track {meta.get('trackC', '?')} C"
              f"  date {meta.get('date', '?')}  flexWarmGain {meta.get('flexWarmGain', '?')}"
              f"  drivePropHystExcess {meta.get('drivePropHystExcess', '?')}")
    if res["crashKm"] is not None:
        print(f"  run ends at km {res['crashKm']:.2f} (crash, spin, or --end-km). Later rows are dropped.")
    if not res["tires"]:
        print("  no tire has 10 moving rows")
        return
    any_tire = next(iter(res["tires"].values()))
    sp = any_tire["speed"]
    print(f"  moving {any_tire['kmMoving']:.2f} km" + (f", median {sp:.1f} m/s ({sp * 3.6:.0f} km/h)" if sp else ""))
    print_checks(run, res)
    print("  tire  class     compound            roll  window       settled   p95    peak   finish  overS  longest  verdict")
    for n, t in res["tires"].items():
        win = f"{fmt(t['lo'])}-{fmt(t['hi'])}"
        print(f"  {n:<5} {t['class']:<9} {t['compound']:<19} {t['roll']:<5} {win:<12} {t['settledMedian']:7.1f}"
              f" {t['p95']:6.1f} {t['peak']:6.1f} {t['finish']:7.1f} {t['overS']:6.1f} {t['longestOverS']:7.1f}   {t['verdict']}"
              + (f"  hold {t['holdS']:.1f}" if t.get("fromFlash") else ""))
    if any(t["share"] for t in res["tires"].values()):
        share_name = "joules" if any((num(r, "rollingJ") or 0) > 0 for r in run.rows) else "watts"
        print(f"  heat share ({share_name})" + "".join(f"{k:>8}" for k, _ in HEAT_COLS))
        for n, t in res["tires"].items():
            for label, share in (("run", t["share"]), ("over", t["shareOver"])):
                if share:
                    print(f"  {n:<5} {label:<10} " + "".join(f"{100 * share[k]:7.0f}%" for k, _ in HEAT_COLS))
    driven = {n: t for n, t in res["tires"].items() if t["class"] == "driven" and t["slipSettled"] is not None}
    if driven:
        print("  driven slip ratio, first third / settled: " + "  ".join(
            f"{n} {fmt(t['slipFirst'], '.3f')} / {t['slipSettled']:.3f}" for n, t in driven.items()))
        worst = max(t["slipSettled"] for t in driven.values())
        if "grid" in (res["track"] or "").lower() and worst > CLEAN_STRAIGHT_SLIP:
            print(f"  NOT A CLEAN STRAIGHT: settled driven slip {worst:.3f} is above {CLEAN_STRAIGHT_SLIP}."
                  " Wheelspin or a slip loop, not a rolling read (ROADMAP S-01).")
    sample = next((r for r in run.rows if "ntfPsi" in r or "throttle" in r), None)
    if sample and "ntfPsi" in sample:
        bits = []
        for n, t in res["tires"].items():
            if t.get("ntfPsiSettled") is not None and t.get("nativePsiSettled") is not None:
                bits.append(f"{n} {t['ntfPsiSettled']:.1f}/{t['nativePsiSettled']:.1f}")
        if bits:
            print("  settled psi NTF/native: " + "  ".join(bits))
    if sample and "throttle" in sample:
        moving_rows = [r for r in run.rows if r.get("_moving") and num(r, "throttle") is not None]
        if moving_rows:
            th = statistics.median(num(r, "throttle", 0.0) or 0.0 for r in moving_rows)
            br = statistics.median(num(r, "brakePedal", 0.0) or 0.0 for r in moving_rows)
            print(f"  pedal throttle/brake median while moving: {th:.2f} / {br:.2f}")


def append_index(src: Path, run: Run, res: dict) -> None:
    if not Path("D:/").exists():
        return
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    seen = set()
    if INDEX.exists():
        with INDEX.open(newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                seen.add((r["sourceFile"], r["runId"], r["startRow"], r["wheel"]))
    new = not INDEX.exists()
    now = dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    with INDEX.open("a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=INDEX_COLS)
        if new:
            w.writeheader()
        for n, t in res["tires"].items():
            key = (src.name, run.run_id, str(run.start_row), n)
            if key in seen:
                continue
            w.writerow({
                "analyzedAt": now, "sourceFile": src.name, "runId": run.run_id, "startRow": run.start_row,
                "car": res["car"], "track": res["track"], "config": res["config"], "wheel": n,
                "class": t["class"], "compound": t["compound"], "roll": t["roll"], "lo": fmt(t["lo"]),
                "hi": fmt(t["hi"]), "kmMoving": f"{t['kmMoving']:.2f}", "medianSpeedMs": fmt(t["speed"]),
                "settledMedian": f"{t['settledMedian']:.1f}", "p95": f"{t['p95']:.1f}",
                "peak": f"{t['peak']:.1f}", "finish": f"{t['finish']:.1f}", "overS": f"{t['overS']:.0f}",
                "longestOverS": f"{t['longestOverS']:.0f}", "crashKm": fmt(res["crashKm"], ".2f"),
                "verdict": t["verdict"], "ambientC": run.meta.get("ambientC", ""),
                "trackC": run.meta.get("trackC", ""), "stamp": run.meta.get("stamp", ""),
            })


# ---------------------------------------------------------------- commands

def newest_csv() -> Path:
    files = [p for p in OUTPUT.glob("*.csv")
             if "dev-circle" not in p.name and not p.name.startswith("ntf-ai-")]
    if not files:
        sys.exit(f"no CSV in {OUTPUT}")
    return max(files, key=lambda p: p.stat().st_mtime)


def load(args: argparse.Namespace):
    src = Path(args.file) if args.file else newest_csv()
    header, runs = load_runs(src)
    return src, header, runs


def window_arg(args: argparse.Namespace):
    return tuple(args.window) if args.window else None


def cmd_list(args: argparse.Namespace) -> int:
    src, header, runs = load(args)
    has_air = "airspeed" in header
    print(f"{src.name}: {len(runs)} runs")
    for run in runs:
        mark_moving(run, has_air)
        moving = [r for r in run.rows if r["_moving"]]
        km = [num(r, "stintKm", 0.0) for r in moving]
        comps = sorted({"@".join(compound(r)).rstrip("@") for r in moving})
        car = run.meta.get("car") or (run.rows[0].get("carName", "") if run.rows else "")
        print(f"  {run.run_id:<28} rows {run.start_row:>6}+ {len(run.rows):>6}  moving km "
              f"{(max(km) - min(km)) if km else 0:6.2f}  {car or '?':<12} {' '.join(comps)}")
    return 0


def stamp_warning(current: str) -> None:
    if not STAMP_FILE.is_file():
        print("No code-stamp.txt. Run `Read-NtfRun.py stamp` before the next drive.")
        return
    fields = dict(p.split("=", 1) for p in STAMP_FILE.read_text(encoding="utf-8").split() if "=" in p)
    if fields.get("lua") != current:
        print(f"code-stamp.txt is lua={fields.get('lua', '?')} from {fields.get('at', '?')}."
              f" The code is now lua={current}. Run `Read-NtfRun.py stamp` before the next drive.")


def cmd_read(args: argparse.Namespace) -> int:
    src, header, runs = load(args)
    has_air = "airspeed" in header
    if "bandLo" not in header and not args.window:
        print("This file has no bandLo column. Pass --window LO HI for window verdicts.")
    if not has_air:
        print("This file has no airspeed column. Moving means km advancing.")
    if "runId" not in header and "brakeSoak" in header:
        print("brakeSoak in this file is the previous wheel's value (fixed in the runId logger).")
    if args.run:
        runs = [r for r in runs if r.run_id == args.run]
        if not runs:
            sys.exit(f"run not found: {args.run}. Use the list command for run ids.")
    elif args.last:
        runs = runs[-1:]
    current = code_hash()
    stamp_warning(current)
    print(f"{src.name}")
    for run in runs:
        res = analyze(run, has_air, window_arg(args), args.end_km if args.run else None)
        if not res["tires"] and not args.run:
            continue
        print_run(run, res, current)
        if not args.no_index and res["tires"]:
            append_index(src, run, res)
    return 0


def cmd_pair(args: argparse.Namespace) -> int:
    src, header, runs = load(args)
    src_b, header_b, runs_b = (src, header, runs)
    if args.file_b:
        src_b = Path(args.file_b)
        header_b, runs_b = load_runs(src_b)
    run_a = next((r for r in runs if r.run_id == args.run_a), None)
    run_b = next((r for r in runs_b if r.run_id == args.run_b), None)
    if run_a is None or run_b is None:
        sys.exit("run not found. Use the list command for run ids.")
    a = analyze(run_a, "airspeed" in header, window_arg(args))
    b = analyze(run_b, "airspeed" in header_b, window_arg(args))
    print(f"A {src.name} {args.run_a}  vs  B {src_b.name} {args.run_b}")
    print("  tire  settled A/B (diff)      finish A/B (diff)       p95 A/B (diff)          overS A/B")
    floor = 0.0
    for n in sorted(set(a["tires"]) & set(b["tires"])):
        ta, tb = a["tires"][n], b["tires"][n]
        ds = tb["settledMedian"] - ta["settledMedian"]
        dfin = tb["finish"] - ta["finish"]
        dp = tb["p95"] - ta["p95"]
        floor = max(floor, abs(ds))
        print(f"  {n:<5} {ta['settledMedian']:5.1f}/{tb['settledMedian']:5.1f} ({ds:+5.1f})"
              f"      {ta['finish']:5.1f}/{tb['finish']:5.1f} ({dfin:+5.1f})"
              f"      {ta['p95']:5.1f}/{tb['p95']:5.1f} ({dp:+5.1f})"
              f"      {ta['overS']:4.0f}/{tb['overS']:4.0f}")
    print(f"  noise floor (largest settled-median gap): {floor:.1f} C")
    return 0


def cmd_split(args: argparse.Namespace) -> int:
    if not Path("D:/").exists():
        sys.exit("D: is not available. Per-run files were not written.")
    dest_root = ARCHIVE / "runs"
    dest_root.mkdir(parents=True, exist_ok=True)
    files = [Path(args.file)] if args.file else sorted(p for p in OUTPUT.glob("*.csv") if "dev-circle" not in p.name)
    written = 0
    for src in files:
        if not src.is_file():
            continue
        header, runs = load_runs(src)
        for run in runs:
            if not run.rows or (args.run and run.run_id != args.run):
                continue
            safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in run.run_id)
            dest = dest_root / f"{src.stem}__{safe}.csv"
            buf = io.StringIO()
            writer = csv.writer(buf, lineterminator="\n")
            writer.writerow(header)
            if run.raw_line:
                buf.write(run.raw_line + "\n")
            for row in run.rows:
                writer.writerow([row.get(col, "") for col in header])
            payload = buf.getvalue()
            if dest.exists() and dest.read_text(encoding="utf-8").count("\n") == payload.count("\n"):
                continue
            dest.write_text(payload, encoding="utf-8")
            written += 1
            print(dest.name)
    print(f"{written} run files in {dest_root}")
    return 0


# Undriven grid straight: scale 2.5 settled near 52°C, scale 4.2 near 77°C.
STRAIGHT_C_PER_TENTH = 1.5


def cmd_predict_share(args: argparse.Namespace) -> int:
    if not (args.run and args.knob and args.axle and args.scale is not None):
        sys.exit("heat-share predict needs --run, --knob, --axle, and --scale")
    if args.scale <= 0:
        sys.exit("scale is the new value over the old one, and it has to be positive")
    src, header, runs = load(args)
    run = next((r for r in runs if r.run_id == args.run), None)
    if run is None:
        sys.exit(f"run not found: {args.run}. Use the list command for run ids.")
    res = analyze(run, "airspeed" in header, window_arg(args))
    try:
        ambient = float(run.meta.get("ambientC"))
        ambient_known = True
    except (TypeError, ValueError):
        ambient, ambient_known = 21.0, False
    print(f"{src.name}  {run.run_id}  {res['car'] or '?'}  {res['track'] or '?'}")
    print(f"  knob {args.knob}  axle {args.axle}  scale {args.scale:.3f} (new/old)  ambient {ambient:.1f} C")
    if not ambient_known:
        print("  The run has no ambientC. Using 21 C.")
    print("  This scales that knob's share of the settled heat by the settled rise above ambient.")
    print("  The band runs from half the prediction to double it. The end closer to zero has to clear the floor.")
    print("  Static cooling is a loss, not a share, so it is not this command.")
    shown = 0
    for n, t in res["tires"].items():
        if args.axle != "all" and tire_axle(n) != args.axle:
            continue
        share = (t["settledShare"] or {}).get(args.knob)
        if share is None:
            print(f"  {n:<5} no settled heat for {args.knob}")
            continue
        rise = t["settledMedian"] - ambient
        delta = (args.scale - 1.0) * share * rise
        ends = sorted((0.5 * delta, 2.0 * delta))
        note = ""
        if args.floor is not None:
            note = "  clears the floor" if abs(0.5 * delta) > args.floor else "  inside the floor"
        print(f"  {n:<5} {t['class']:<9} share {100 * share:3.0f}%  rise {rise:5.1f}"
              f"  predicted {delta:+5.1f} C  band {ends[0]:+5.1f} to {ends[1]:+5.1f}{note}")
        shown += 1
    if not shown:
        print("  no tire on that axle")
    return 0


def cmd_predict(args: argparse.Namespace) -> int:
    share_bits = (args.run, args.knob, args.axle, args.scale is not None)
    pair_bits = (args.run_a, args.run_b, args.rolling_delta is not None)
    if any(share_bits) and any(pair_bits):
        sys.exit("use either --run --knob --axle --scale, or RUN_A RUN_B --rolling-delta")
    if any(share_bits):
        return cmd_predict_share(args)
    if not all(pair_bits):
        sys.exit("pair predict needs RUN_A RUN_B --rolling-delta."
                 " Heat-share predict needs --run --knob --axle --scale.")
    src, header, runs = load(args)
    src_b, header_b, runs_b = (src, header, runs)
    if args.file_b:
        src_b = Path(args.file_b)
        header_b, runs_b = load_runs(src_b)
    run_a = next((r for r in runs if r.run_id == args.run_a), None)
    run_b = next((r for r in runs_b if r.run_id == args.run_b), None)
    if run_a is None or run_b is None:
        sys.exit("run not found. Use the list command for run ids.")
    a = analyze(run_a, "airspeed" in header, window_arg(args))
    b = analyze(run_b, "airspeed" in header_b, window_arg(args))
    floor = 0.0
    for n in set(a["tires"]) & set(b["tires"]):
        floor = max(floor, abs(b["tires"][n]["settledMedian"] - a["tires"][n]["settledMedian"]))
    shift = abs(args.rolling_delta) / 0.1 * STRAIGHT_C_PER_TENTH
    print(f"pair floor {floor:.1f} C")
    print(f"straight undriven prediction for {args.rolling_delta:+.2f} rolling: {shift:.1f} C")
    print("Source: grid straight, scale 2.5 near 52 C and scale 4.2 near 77 C. About 1.5 C per tenth.")
    print("This is not a replay of the 1 Hz thermal step. Corner heat is not this number.")
    if shift > floor:
        print(f"The predicted shift is larger than this pair's floor ({floor:.1f} C).")
    else:
        print(f"The predicted shift is inside this pair's floor ({floor:.1f} C).")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    def common(p):
        p.add_argument("--file", help="telemetry CSV (default: newest in tools/output)")
        p.add_argument("--window", nargs=2, type=float, metavar=("LO", "HI"),
                       help="edge for files without bandLo/bandHi")

    sub.add_parser("stamp", help="write tools/output/code-stamp.txt and a code snapshot on D:")
    common(sub.add_parser("list", help="runs in a file"))
    p_read = sub.add_parser("read", help="report per run")
    common(p_read)
    p_read.add_argument("--run", help="one run id")
    p_read.add_argument("--last", action="store_true", help="newest run only")
    p_read.add_argument("--end-km", type=float, help="with --run: drop rows past this km")
    p_read.add_argument("--no-index", action="store_true", help="do not append to D:/ntf-logs/index.csv")
    p_pair = sub.add_parser("pair", help="compare two runs of one setup")
    common(p_pair)
    p_pair.add_argument("run_a")
    p_pair.add_argument("run_b")
    p_pair.add_argument("--file-b", help="CSV holding run B when it is not in --file")
    p_split = sub.add_parser("split", help="write one CSV per run under D:/ntf-logs/runs")
    common(p_split)
    p_split.add_argument("--run", help="one run id")
    p_predict = sub.add_parser("predict", help="predict a rolling step from a pair, or a heat-share step from one run")
    common(p_predict)
    p_predict.add_argument("run_a", nargs="?")
    p_predict.add_argument("run_b", nargs="?")
    p_predict.add_argument("--file-b", help="CSV holding run B when it is not in --file")
    p_predict.add_argument("--rolling-delta", type=float, help="pair form: proposed change in rollingHystScale")
    p_predict.add_argument("--run", help="heat-share form: the run to scale")
    p_predict.add_argument("--knob", choices=("rolling", "flex", "soak"), help="heat share to scale")
    p_predict.add_argument("--axle", choices=("front", "rear", "all"))
    p_predict.add_argument("--scale", type=float, help="new value over the old one, for example 1.35 or 0.74")
    p_predict.add_argument("--floor", type=float, help="car noise floor, in C. The half-prediction has to clear it")
    args = ap.parse_args()
    if args.cmd == "stamp":
        return cmd_stamp(args)
    if args.cmd == "list":
        return cmd_list(args)
    if args.cmd == "pair":
        return cmd_pair(args)
    if args.cmd == "split":
        return cmd_split(args)
    if args.cmd == "predict":
        return cmd_predict(args)
    if args.cmd == "read":
        return cmd_read(args)
    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
