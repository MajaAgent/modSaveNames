#!/usr/bin/env python3
"""wscheck.py - static sanity check for modSaveNames.ws (run by build-release.sh).

There is no WitcherScript compiler here, so this does the checks that a compiler
would do first and that a slipped rename silently breaks: every ModSaveNames_* call
has a definition, every definition is used, braces balance, and indentation is tabs
only. It caught a real release-blocker once (a call to a function renamed away).

    python3 tools/wscheck.py content/scripts/local/modSaveNames.ws [more files]

Exit code 1 on a hard problem (undefined call, unbalanced braces, mixed indentation).
"""
from __future__ import annotations

import pathlib
import re
import sys


def check(path: str) -> int:
    text = pathlib.Path(path).read_text(encoding="utf-8")
    defined = set(re.findall(r"^\s*(?:exec\s+)?function\s+(\w+)\s*\(", text, re.M))
    called = set(re.findall(r"\b(ModSaveNames_\w+)\s*\(", text))

    problems: list[str] = []
    hard = False
    for fn in sorted(called - defined):
        problems.append(f"  CALL TO UNDEFINED: {fn}()")
        hard = True
    for fn in sorted(defined - called):
        if fn.startswith("ModSaveNames_"):
            problems.append(f"  defined but never called: {fn}()")
    if text.count("{") != text.count("}"):
        problems.append(f"  unbalanced braces: {text.count('{')} '{{' vs {text.count('}')} '}}'")
        hard = True
    if "\t " in text:
        problems.append("  mixed tab+space indentation")
        hard = True

    execs = re.findall(r"^exec function (\w+)", text, re.M)
    print(f"{path}: {len(defined)} functions, {len(execs)} console command(s)"
          + (f" ({', '.join(execs)})" if execs else ""))
    print("\n".join(problems) if problems else "  OK - no undefined calls, braces balanced")
    return 1 if hard else 0


if __name__ == "__main__":
    rc = 0
    for arg in sys.argv[1:]:
        rc |= check(arg)
    sys.exit(rc)
