#!/usr/bin/env python3
"""wscheck.py - static sanity check for the mod's WitcherScript sources.

There is no WitcherScript compiler here, so this does the checks that a compiler
would do first and that a slipped rename silently breaks: every ModSaveNames_*
call has a definition somewhere in the mod, braces balance, and indentation is
tabs only. It caught a real release-blocker once (a call to a function renamed
away).

Every file is checked together, because the mod is more than one file: a call in
modSaveNames.ws may be defined in modSaveNamesProfile.ws (scripts share a single
global namespace).

    python3 tools/wscheck.py content/scripts/local/*.ws

Exit code 1 on a hard problem (undefined call, unbalanced braces, mixed indentation).
"""
from __future__ import annotations

import pathlib
import re
import sys


def check(paths: list[str]) -> int:
    texts = {p: pathlib.Path(p).read_text(encoding="utf-8") for p in paths}

    defined: set[str] = set()
    called: set[str] = set()
    execs: list[str] = []

    for text in texts.values():
        defined |= set(re.findall(r"^\s*(?:exec\s+)?function\s+(\w+)\s*\(", text, re.M))
        called |= set(re.findall(r"\b(ModSaveNames_\w+)\s*\(", text))
        execs += re.findall(r"^exec function (\w+)", text, re.M)

    problems: list[str] = []
    hard = False

    for fn in sorted(called - defined):
        problems.append(f"  CALL TO UNDEFINED: {fn}()")
        hard = True
    for fn in sorted(defined - called):
        if fn.startswith("ModSaveNames_"):
            problems.append(f"  defined but never called: {fn}()")

    for path, text in texts.items():
        if text.count("{") != text.count("}"):
            problems.append(f"  {path}: unbalanced braces: {text.count('{')} '{{' vs {text.count('}')} '}}'")
            hard = True
        if "\t " in text:
            problems.append(f"  {path}: mixed tab+space indentation")
            hard = True

    print(f"{len(texts)} file(s), {len(defined)} function(s), {len(execs)} console command(s)"
          + (f" ({', '.join(execs)})" if execs else ""))
    print("\n".join(problems) if problems else "  OK - no undefined calls, braces balanced")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(check(sys.argv[1:]))
