#!/usr/bin/env bash
# Builds the release archive in the layout Vortex (and a manual install) expects
# for a Witcher 3 script mod: mods/<modName>/content/... at the archive root.
# Run from the repo root:  ./build-release.sh [version]
#
# Zipping goes through Python rather than the zip(1) binary, which Git Bash on
# Windows does not ship. Timestamps are fixed so identical content gives an
# identical archive. Note: alternatives/ is deliberately NOT shipped - it holds
# a second implementation of the same hook and must never go into the archive.
set -euo pipefail

MOD_NAME="modSaveNames"
VERSION="${1:-0.1.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
ARCHIVE="$DIST/$MOD_NAME-$VERSION.zip"

PY="$(command -v python3 || command -v python)"

# A shipped script must not reference a function that does not exist: there is no
# WitcherScript compiler here, and a slipped rename only shows up as a red
# "Script compilation errors" box in the game.
"$PY" "$ROOT/tools/wscheck.py" "$ROOT"/content/scripts/local/*.ws

# WitcherScript traps a normal linter misses: engine type names cannot be used as
# identifiers, `var` is illegal at file scope. The game's own scripts make the call
# check complete - W3_CORPUS=/path/to/Witcher3/scripts ./build-release.sh
AUDIT_CORPUS=""
if [ -n "$W3_CORPUS" ] && [ -d "$W3_CORPUS" ]; then
	AUDIT_CORPUS="--corpus $W3_CORPUS"
fi
# shellcheck disable=SC2086
"$PY" "$ROOT/tools/audit-ws.py" "$ROOT"/content/scripts/local/*.ws $AUDIT_CORPUS

# The save->player map is 8 chunks of "|file=player": the string rules are mirrored
# in Python, and the chunk count/format are read out of the .ws, so a format change
# fails here instead of shipping a map that cannot find its own entries.
"$PY" "$ROOT/tools/test-owner-map.py" "$ROOT/content/scripts/local/$MOD_NAME.ws" "$ROOT/content/scripts/local/modSaveNamesProfile.ws"

# The label format (4 characters per int fact, base 100) is mirrored in Python
# because WitcherScript cannot run here: a mismatch would silently mangle names.
"$PY" "$ROOT/tools/test-label-packing.py" "$ROOT/content/scripts/local/$MOD_NAME.ws"

rm -rf "$STAGE"
rm -f "$ARCHIVE"
mkdir -p "$STAGE/mods/$MOD_NAME"

cp -r "$ROOT/content" "$STAGE/mods/$MOD_NAME/content"

# Docs ride inside the mod folder, never at the archive root: Vortex deploys
# root-level files straight into the game directory.
cp "$ROOT/README.md"   "$STAGE/mods/$MOD_NAME/README.md"
cp "$ROOT/CHANGELOG.md" "$STAGE/mods/$MOD_NAME/CHANGELOG.md"
[ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$STAGE/mods/$MOD_NAME/LICENSE"

"$PY" - "$STAGE" "$ARCHIVE" <<'PYEOF'
import os, sys, zipfile
stage, archive = sys.argv[1], sys.argv[2]
names = []
for root, dirs, files in os.walk(stage):
    dirs.sort()
    for f in sorted(files):
        full = os.path.join(root, f)
        names.append((os.path.relpath(full, stage).replace(os.sep, "/"), full))
names.sort()
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    for arcname, full in names:
        info = zipfile.ZipInfo(arcname, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(full, "rb") as fh:
            z.writestr(info, fh.read())
print(f"built {archive}")
for arcname, _ in names:
    print("   ", arcname)
PYEOF

rm -rf "$STAGE"
