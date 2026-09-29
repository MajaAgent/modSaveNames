#!/usr/bin/env bash
# Test run for `card`: what it draws, into which file, at what size, and when it
# refuses to touch anything. Real saves are never involved - everything happens in a
# throwaway gamesaves folder with the same layout 5.0 uses (.sav + .json + .png).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$(command -v python3 || command -v python)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SAVES="$TMP/gamesaves"
mkdir -p "$SAVES"

md5sums() { (cd "$SAVES" && md5sum *.png | sort); }

echo "== synthetic saves (each thumbnail a different size, as on disk) =="
"$PY" - "$SAVES" "$ROOT/tools" <<'PYEOF'
import pathlib, sys
saves, tools = pathlib.Path(sys.argv[1]), sys.argv[2]
sys.path.insert(0, tools)
import card_png

for stem, size in (
    ("ManualSave_[KAMIL]_8559a_7ea47000_515dab8", (512, 288)),
    ("CheckPoint_[BRAT]_53db9_7ea47000_5c25ee8", (320, 180)),
    ("AutoSave_77_abc", (256, 144)),
):
    (saves / f"{stem}.sav").write_bytes(b"SNFHFZLC" + bytes(64))
    (saves / f"{stem}.json").write_text('{"saveMetadata": {"gameVersion": 29}}')
    (saves / f"{stem}.png").write_bytes(card_png.render(size[0], size[1], "OLD"))
    print(f"   {stem}: .sav + .json + .png {size[0]}x{size[1]}")
PYEOF

md5sums > "$TMP/before.txt"

run() {
    echo
    echo "\$ w3save_renamer.py $*"
    "$PY" "$ROOT/tools/w3save_renamer.py" --dir "$SAVES" --no-memory "$@"
}

run card --labelled
md5sums > "$TMP/after-labelled.txt"
echo
echo "== changed by 'card --labelled' =="
diff "$TMP/before.txt" "$TMP/after-labelled.txt" | grep '^>' | sed 's/^> /   /' || true

run --dry-run card "AutoSave" --text "wspolny"
md5sums > "$TMP/after-dry.txt"
echo
echo "== changed by a --dry-run (must be nothing) =="
diff "$TMP/after-labelled.txt" "$TMP/after-dry.txt" | grep '^>' | sed 's/^> /   /' || echo "   nothing, as it should be"

run card "AutoSave" --text "wspolny" --sub "shared save"
run card "ManualSave" --size 100x40 --text "za male"

echo
echo "== verdict =="
"$PY" - "$SAVES" "$ROOT/tools" "$TMP" <<'PYEOF'
import pathlib, sys
saves, tools, tmp = pathlib.Path(sys.argv[1]), str(sys.argv[2]), pathlib.Path(sys.argv[3])
sys.path.insert(0, tools)
import card_png

expected = {
    "ManualSave_[KAMIL]_8559a_7ea47000_515dab8": (100, 40),   # --size wins, with a note
    "CheckPoint_[BRAT]_53db9_7ea47000_5c25ee8": (320, 180),   # kept the game's own size
    "AutoSave_77_abc": (256, 144),
}
before = dict(l.split()[::-1] for l in (tmp / "before.txt").read_text().splitlines())
after_labelled = dict(l.split()[::-1] for l in (tmp / "after-labelled.txt").read_text().splitlines())
after_dry = dict(l.split()[::-1] for l in (tmp / "after-dry.txt").read_text().splitlines())

ok = True
hashes_now = {}
for png in sorted(saves.glob("*.png")):
    stem = png.name[:-4]
    size = card_png.png_size(png)
    hashes_now[png.name] = __import__("hashlib").md5(png.read_bytes()).hexdigest()
    good = size == expected[stem]
    ok = ok and good
    print(f"   {'OK  ' if good else 'FAIL'} {png.name}: {size[0]}x{size[1]} "
          f"(expected {expected[stem][0]}x{expected[stem][1]}), {png.stat().st_size} B")

# --dry-run must not have written anything, and --labelled must have touched exactly 2
dry_diffs = [n for n in after_labelled if after_labelled[n] != after_dry[n]]
labelled_diffs = [n.replace(".png", "") for n in before if before[n] != after_labelled[n]]
print(f"   {'OK  ' if not dry_diffs else 'FAIL'} --dry-run wrote nothing ({len(dry_diffs)} file(s) changed)")
print(f"   {'OK  ' if len(labelled_diffs) == 2 else 'FAIL'} --labelled restamped exactly the two labelled saves: {sorted(labelled_diffs)}")
newly = sorted(n.split(".")[0] for n in hashes_now if hashes_now[n] != after_labelled[n])
print(f"   OK   redrawn afterwards: {newly}")

ok = ok and not dry_diffs and len(labelled_diffs) == 2
print("PASS - cards land in the right files, at the right size" if ok else "FAILED")
sys.exit(0 if ok else 1)
PYEOF
