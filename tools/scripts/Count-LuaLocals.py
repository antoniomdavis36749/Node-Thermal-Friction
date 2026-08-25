#!/usr/bin/env python3
"""Count Lua 5.1/LuaJIT local registers per function/chunk (approx).

Notes:
- Counts distinct local names + params + for-loop vars in each function scope.
- Nested functions are separate scopes; the parent also pays 1 local for a
  `local function` / `local x = function` binding.
- Upvalues do NOT consume an extra register slot in the enclosing function
  beyond the local they already occupy; however active upvalues still need
  the parent local to exist.
- This is a heuristic lexer — good enough to find hotspots near the ~200 cap.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


def strip_noise(s: str) -> str:
    out: list[str] = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "-" and i + 1 < n and s[i + 1] == "-":
            if i + 3 < n and s[i + 2] == "[" and s[i + 3] == "[":
                j = s.find("]]", i + 4)
                i = n if j < 0 else j + 2
            else:
                while i < n and s[i] != "\n":
                    i += 1
            continue
        if c in "\"'":
            q = c
            i += 1
            while i < n:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == q:
                    i += 1
                    break
                i += 1
            continue
        if c == "[" and i + 1 < n and s[i + 1] == "[":
            j = s.find("]]", i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_names(part: str) -> list[str]:
    part = part.split("=")[0]
    names: list[str] = []
    for tok in part.split(","):
        tok = tok.strip()
        m = re.match(rf"^({IDENT})$", tok)
        if m:
            names.append(m.group(1))
    return names


KEYWORDS_OPEN = {"function", "if", "for", "while", "repeat", "do"}
# 'do' after for/while is part of that construct; we still count blocks via tokens.


def tokenize_line(line: str) -> list[str]:
    # Keep identifiers and structural keywords; drop other punctuation-ish.
    return re.findall(rf"{IDENT}|\.\.\.|[\(\)]", line)


def main() -> int:
    path = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else r"lua/vehicle/extensions/auto/tireWearThermals.lua"
    )
    src = path.read_text(encoding="utf-8")
    clean = strip_noise(src)
    lines = clean.splitlines()

    scopes: list[dict] = []
    root = {
        "name": "<chunk>",
        "start": 1,
        "end": len(lines),
        "locals": {},  # name -> first line
        "kind": "chunk",
        "depth": 0,  # block depth within this scope (function body starts at 0; first do/if opens)
        "pending_do": False,  # for/while expect do
    }
    stack = [root]
    scopes.append(root)

    local_func_re = re.compile(rf"^\s*local\s+function\s+({IDENT})\s*\(([^)]*)\)")
    func_re = re.compile(rf"^\s*function\s+({IDENT}(?:\.{IDENT})*)\s*\(([^)]*)\)")
    assign_func_re = re.compile(rf"^\s*(?:local\s+)?({IDENT})\s*=\s*function\s*\(([^)]*)\)")
    local_decl_re = re.compile(r"^\s*local\s+(?!function\b)(.+)$")
    for_num_re = re.compile(rf"^\s*for\s+({IDENT})\s*=")
    for_in_re = re.compile(rf"^\s*for\s+(.+?)\s+in\b")

    def add_local(scope: dict, name: str, line: int) -> None:
        if not name or name == "_":
            return
        scope["locals"].setdefault(name, line)

    def open_function(name: str, params: str, line: int, bind_local: bool) -> None:
        parent = stack[-1]
        short = name.split(".")[-1]
        if bind_local:
            add_local(parent, short, line)
        sc = {
            "name": name,
            "start": line,
            "end": None,
            "locals": {},
            "kind": "function",
            "depth": 0,
            "pending_do": False,
        }
        for p in parse_names(params.replace("...", "")):
            add_local(sc, p, line)
        scopes.append(sc)
        stack.append(sc)

    i = 0
    while i < len(lines):
        raw = lines[i]
        ln = i + 1
        line = raw

        # Function openers (prefer whole-line patterns)
        m = local_func_re.match(line)
        if m:
            open_function(m.group(1), m.group(2), ln, True)
            i += 1
            continue
        m = func_re.match(line)
        if m:
            open_function(m.group(1), m.group(2), ln, False)
            i += 1
            continue
        m = assign_func_re.match(line)
        if m:
            is_local = line.lstrip().startswith("local ")
            open_function(m.group(1), m.group(2), ln, is_local)
            i += 1
            continue

        # Anonymous function somewhere on line
        if re.search(r"\bfunction\s*\(", line) and "function " not in line.split("function")[0][-20:]:
            # Avoid double-count if already matched
            if not re.search(rf"\bfunction\s+{IDENT}", line):
                pm = re.search(r"function\s*\(([^)]*)\)", line)
                params = pm.group(1) if pm else ""
                open_function(f"<anon@{ln}>", params, ln, False)

        # Locals / for vars in current function scope
        cur = stack[-1]
        lm = local_decl_re.match(line)
        if lm:
            for name in parse_names(lm.group(1)):
                add_local(cur, name, ln)
        fm = for_num_re.match(line)
        if fm:
            add_local(cur, fm.group(1), ln)
        fim = for_in_re.match(line)
        if fim:
            for name in parse_names(fim.group(1)):
                add_local(cur, name, ln)

        # Block depth tracking via tokens (function already opened above)
        tokens = tokenize_line(line)
        # Handle 'end' / 'until' / structural keywords carefully
        # When we opened a function, its body depth starts at 0; the matching end closes it.
        j = 0
        while j < len(tokens):
            t = tokens[j]
            if t == "function" and j > 0:
                # mid-line nested function already handled roughly; skip
                pass
            elif t in ("if", "for", "while"):
                # these open a block that ends with end; for/while use 'do'
                cur = stack[-1]
                if t in ("for", "while"):
                    cur["pending_do"] = True
                else:
                    # if ... then — count as open when we see then, approximate as +1 now
                    cur["depth"] += 1
            elif t == "repeat":
                stack[-1]["depth"] += 1
            elif t == "do":
                cur = stack[-1]
                if cur["pending_do"]:
                    cur["pending_do"] = False
                    cur["depth"] += 1
                else:
                    # bare do-end block
                    cur["depth"] += 1
            elif t == "then":
                # already counted if — avoid double; if we counted if already, skip
                pass
            elif t == "until":
                cur = stack[-1]
                if cur["depth"] > 0:
                    cur["depth"] -= 1
            elif t == "end":
                cur = stack[-1]
                if cur["kind"] == "function" and cur["depth"] == 0:
                    cur["end"] = ln
                    stack.pop()
                    if not stack:
                        stack.append(root)
                else:
                    if cur["depth"] > 0:
                        cur["depth"] -= 1
                    elif cur["kind"] == "function":
                        # depth underflow — treat as function end
                        cur["end"] = ln
                        stack.pop()
                        if not stack:
                            stack.append(root)
            j += 1

        i += 1

    root["end"] = len(lines)

    # Report
    rows = []
    for sc in scopes:
        count = len(sc["locals"])
        rows.append((count, sc["start"], sc.get("end") or "?", sc["name"], sc["kind"]))
    rows.sort(reverse=True)

    print(f"File: {path}")
    print(f"Lines: {len(lines)}")
    print(f"Scopes: {len(scopes)}")
    print()
    print(f"{'locals':>6}  {'start':>6}  {'end':>6}  name")
    print("-" * 72)
    for count, start, end, name, kind in rows:
        marker = ""
        if count >= 190:
            marker = " *** OVER/CRITICAL"
        elif count >= 160:
            marker = " ** HIGH"
        elif count >= 120:
            marker = " * elevated"
        print(f"{count:6d}  {start:6d}  {str(end):>6}  {name}{marker}")

    print()
    print("Top scopes detail (locals >= 80):")
    for count, start, end, name, kind in rows:
        if count < 80:
            break
        sc = next(s for s in scopes if s["name"] == name and s["start"] == start)
        print(f"\n=== {name} @ {start}-{end} : {count} locals ===")
        items = sorted(sc["locals"].items(), key=lambda x: x[1])
        for n, ln in items:
            print(f"  L{ln}: {n}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
