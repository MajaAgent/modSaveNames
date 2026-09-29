#!/usr/bin/env python3
"""test-label-packing.py - the label storage format, checked end to end.

The mod stores a save's name as ints in the game's fact database, four characters
per fact (base-100 digits) plus a length fact. WitcherScript cannot be run here, so
this mirrors the two loops (ModSaveNames_StoreLabel / ModSaveNames_StoredLabel) in
Python and round-trips real labels - including the cases that bite: Polish
characters, characters outside the alphabet, the 32-character cap and the empty
label. The alphabet is read out of the shipped .ws, so the test cannot drift from
the mod.

    python3 tools/test-label-packing.py [path/to/modSaveNames.ws]
"""
from __future__ import annotations

import pathlib
import re
import sys

DEFAULT_WS = pathlib.Path(__file__).resolve().parent.parent / "content/scripts/local/modSaveNames.ws"
SLOTS = 8
FACTORS = (1, 100, 10000, 1000000)


def alphabet_from(ws: pathlib.Path) -> str:
    text = ws.read_text(encoding="utf-8")
    body = text[text.index("function ModSaveNames_Alphabet") :]
    found = re.search(r'return "([^"]+)";', body)
    if not found:
        raise SystemExit(f"could not find the alphabet in {ws}")
    return found.group(1)


def store(label: str, alphabet: str) -> dict:
    """Mirror of ModSaveNames_StoreLabel()."""
    length = min(len(label), SLOTS * 4)
    facts = {"modSaveNames_len": length}
    for slot in range(SLOTS):
        value = 0
        for digit in range(4):
            i = slot * 4 + digit
            code = alphabet.find(label[i]) if i < length else -1
            if code < 0:
                code = 0  # anything outside the alphabet becomes 'A'
            value += code * FACTORS[digit]
        facts[f"modSaveNames_{slot}"] = value
    return facts


def load(facts: dict, alphabet: str) -> str:
    """Mirror of ModSaveNames_StoredLabel()."""
    length = facts["modSaveNames_len"]
    if length <= 0:
        return ""
    label = ""
    for slot in range(SLOTS):
        value = facts[f"modSaveNames_{slot}"]
        for digit in range(4):
            index = slot * 4 + digit
            code = value - (value // 100) * 100
            value //= 100
            if index < length:
                label += alphabet[code]
    return label


def main() -> int:
    ws = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_WS
    alphabet = alphabet_from(ws)

    print(f"alphabet from {ws.name}: {len(alphabet)} characters")
    if len(alphabet) >= 100:
        print("  FAIL - must stay below 100 for base-100 packing")
        return 1
    if len(set(alphabet)) != len(alphabet):
        print("  FAIL - duplicate characters, decoding would be ambiguous")
        return 1

    cases = [
        "Kamil",
        "Kamil i brat",
        "Zapis brata - boss fight",
        "Wiedźmin ąęćłńóśźż ŻÓŁĆ",
        "Nr 1 № 2 (emoji 🐺 dropped)",
        "A" * 32,
        "B" * 40,
        " ",
        "",
    ]

    failed = 0
    for case in cases:
        expected = "".join(ch if ch in alphabet else "A" for ch in case[:32])
        got = load(store(case, alphabet), alphabet)
        ok = got == expected
        failed += 0 if ok else 1
        print(f"  {'OK  ' if ok else 'FAIL'} in={case!r:34} out={got!r}")

    biggest = max(store("Ż" * 32, alphabet).values())
    print(f"largest packed fact: {biggest} (fits an int32)")
    print("PASS - the label survives the round trip" if not failed else f"{failed} case(s) FAILED")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
