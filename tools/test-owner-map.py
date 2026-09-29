#!/usr/bin/env python3
"""test-owner-map.py - runs the mod's save->player map rules in Python.

The map lives in the game's settings as 8 chunks of "|file=player" entries and is
read/written by ModSaveNames_MapOwner / MapPut / MapStrip in
content/scripts/local/modSaveNamesProfile.ws. There is no WitcherScript compiler
here, so the string rules are mirrored below and the constants are read out of the
.ws file - if the mod changes the entry format or the chunk count, this fails
instead of shipping a map that cannot find its own entries.

    python3 tools/test-owner-map.py content/scripts/local/*.ws

Run by build-release.sh. Exit code 1 on any mismatch.
"""
from __future__ import annotations

import pathlib
import re
import sys

LIMIT_DEFAULT = 2000


def read_constants(paths: list[str]) -> tuple[int, int]:
    # every .ws the build passes in: the map may sit in any of them (scripts share
    # one global namespace, so the search is over the joined sources)
    text = "\n".join(pathlib.Path(p).read_text(encoding="utf-8") for p in paths)

    if '"|" + file + "="' not in text:
        raise SystemExit("entry format changed: expected the key to be \"|\" + file + \"=\"")

    parts = re.search(r"function ModSaveNames_MapParts\(\) : int\s*\{\s*return (\d+);", text)
    limit = re.search(r"function ModSaveNames_PartLimit\(\) : int\s*\{\s*return (\d+);", text)
    if not parts or not limit:
        raise SystemExit("could not read ModSaveNames_MapParts/PartLimit out of the .ws")

    for needed in ("ModSaveNames_MapOwner", "ModSaveNames_MapPut", "ModSaveNames_MapStrip",
                   "saveNameClaimAll", "ModSaveNames_CleanOwner"):
        if needed not in text:
            raise SystemExit(f"{needed} is missing from the .ws")

    return int(parts.group(1)), int(limit.group(1))


# --- the mirror of the WitcherScript ---------------------------------------

PARTS = 8
LIMIT = LIMIT_DEFAULT


def key(file: str) -> str:
    return "|" + file + "="


def clean_owner(owner: str) -> str:
    return owner.replace("|", "_").replace("=", "_").replace("\n", " ")


def owner(parts: list[str], file: str) -> str:
    for part in parts:
        at = part.find(key(file))
        if at >= 0:
            tail = part[at + len(key(file)):]
            stop = tail.find("|")
            return tail if stop < 0 else tail[:stop]
    return ""


def strip(parts: list[str], index: int, file: str) -> list[str]:
    part = parts[index]
    at = part.find(key(file))
    while at >= 0:
        nxt = part.find("|", at + 1)
        part = part[:at] + part[nxt:] if nxt >= 0 else part[:at]
        at = part.find(key(file))
    parts[index] = part
    return parts


def put(parts: list[str], file: str, who: str) -> list[str]:
    entry = key(file) + clean_owner(who)
    placed = False
    for i in range(len(parts)):
        strip(parts, i, file)
        if not placed and len(parts[i]) + len(entry) <= LIMIT:
            parts[i] += entry
            placed = True
    if not placed:
        parts[-1] += entry
    return parts


def count(parts: list[str]) -> int:
    return sum(p.count("|") for p in parts)


def logical(parts: list[str]) -> dict[str, str]:
    """The map as it is actually read: file -> player, whichever chunk holds it."""
    out: dict[str, str] = {}
    for part in parts:
        for chunk in part.split("|")[1:]:
            f, _, who = chunk.partition("=")
            out[f] = who
    return out


# --- the cases --------------------------------------------------------------

def main() -> int:
    global PARTS, LIMIT
    paths = sys.argv[1:] or ["content/scripts/local/modSaveNamesProfile.ws"]
    PARTS, LIMIT = read_constants(paths)
    print(f"map: {PARTS} chunks, {LIMIT} chars each (read from {len(paths)} file(s): {', '.join(paths)})")

    checks = 0
    fails: list[str] = []

    def check(label: str, got, want) -> None:
        nonlocal checks
        checks += 1
        if got != want:
            fails.append(f"  {label}: got {got!r}, wanted {want!r}")
            print(f"  FAIL {label}: {got!r} != {want!r}")
        else:
            print(f"  ok   {label}")

    parts = ["" for _ in range(PARTS)]

    check("unknown file has no owner", owner(parts, "manualsave_a"), "")

    put(parts, "manualsave_a", "Kamil")
    check("after put", owner(parts, "manualsave_a"), "Kamil")
    check("one entry", count(parts), 1)

    # a file whose name is a prefix of another must never be confused
    put(parts, "manualsave_ab", "Brat")
    check("prefix file a", owner(parts, "manualsave_a"), "Kamil")
    check("prefix file ab", owner(parts, "manualsave_ab"), "Brat")

    # overwriting keeps exactly one entry
    put(parts, "manualsave_a", "Brat")
    check("overwrite wins", owner(parts, "manualsave_a"), "Brat")
    check("still one entry for that file", count(parts), 2)

    # "?" (unclaimed, from before the mod) round-trips
    put(parts, "checkpoint_1", "?")
    check("unclaimed marker", owner(parts, "checkpoint_1"), "?")

    # separators in a player name cannot break the format
    put(parts, "quicksave_9", "Ka|mi=l")
    check("separators cleaned", owner(parts, "quicksave_9"), "Ka_mi_l")

    # a chunk boundary: fill until the entries spill into the next chunk
    long_name = "manualsave_" + "f" * 40
    for i in range(60):
        put(parts, f"{long_name}_{i}", "Kamil")
    check("all 60 found", all(owner(parts, f"{long_name}_{i}") == "Kamil" for i in range(60)), True)
    check("spilled past the first chunk", sum(1 for p in parts if p) > 1, True)

    # re-putting a file must not duplicate it, and must not disturb the others.
    # (the entry itself may move to another chunk - that is how the appender works,
    # which is why the comparison is on the map's logical content, not on the chunks)
    before = logical(parts)
    put(parts, "checkpoint_1", "?")
    check("no duplicate after re-put", count(parts), 64)
    check("entry count matches the map", count(parts), len(logical(parts)))
    check("nothing else moved", logical(parts) == before, True)

    # an overwrite of a file in a later chunk keeps every other file intact
    before = logical(parts)
    put(parts, f"{long_name}_59", "Brat")
    after = logical(parts)
    check("overwrite touches one entry", len(after), len(before))
    check("overwrite changed only that file",
          all(after[k] == v for k, v in before.items() if k != f"{long_name}_59"), True)
    check("overwrite landed", after[f"{long_name}_59"], "Brat")

    # a file that was never in the map cannot be removed by accident
    snapshot = [p for p in parts]
    for i in range(PARTS):
        strip(parts, i, "manualsave_does_not_exist")
    check("stripping an unknown file changes nothing", parts == snapshot, True)

    print(f"\n{checks - len(fails)}/{checks} checks passed")
    if fails:
        print("\n".join(fails))
        return 1
    print("PASS - the map's string rules hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
