#!/usr/bin/env bash
# Verification run for w3save_renamer.py against synthetic save data.
# Usage: bash poc-test.sh <workdir>   (default /tmp/w3test)
set -u
WORK="${1:-/tmp/w3test}"
GS="$WORK/gamesaves"
TOOL="$(cd "$(dirname "$0")" && pwd)/w3save_renamer.py"
PY="python3"
ST="--state $WORK/state.json"

echo "### 0. fixtures"
rm -rf "$WORK"; mkdir -p "$GS"
printf 'SAV' > "$GS/ManualSave_4711_9f2a11.sav"; printf 'META' > "$GS/ManualSave_4711_9f2a11.json"; printf 'PNG' > "$GS/ManualSave_4711_9f2a11.png"
printf 'SAV' > "$GS/QuickSave_119500_7ea3e400_3a63a96.sav"; printf 'PNG' > "$GS/QuickSave_119500_7ea3e400_3a63a96.png"
mkdir -p "$GS/ManualSave-1234"
printf '{"name":"ManualSave-1234"}' > "$GS/ManualSave-1234/metadata.1234.json"
printf 'SAV' > "$GS/ManualSave-1234/save.sav"
ls -1 "$GS"

echo; echo "### 1. list"
$PY "$TOOL" --dir "$GS" $ST list

echo; echo "### 2. dry-run rename, label with Windows-illegal chars"
$PY "$TOOL" --dir "$GS" $ST --dry-run rename ManualSave_4711 'Rodrigo: boss fight?'

echo; echo "### 3. real rename with backup (mode=tag, the default / mod-aware convention)"
$PY "$TOOL" --dir "$GS" $ST --backup rename ManualSave_4711 'Rodrigo: boss fight?'
ls -1 "$GS" "$GS/_backup"

echo; echo "### 4. quicksave, mode=keep (label right after the type prefix, no id)"
$PY "$TOOL" --dir "$GS" $ST rename QuickSave 'Before the Wild Hunt' --mode keep
ls -1 "$GS"

echo; echo "### 5. old-gen save folder, mode=free"
$PY "$TOOL" --dir "$GS" $ST rename ManualSave-1234 'Geralt start' --mode free
ls -1 "$GS"

echo; echo "### 6. collision guard (target already exists)"
printf 'SAV' > "$GS/ManualSave_4711_9f2a11.sav"
$PY "$TOOL" --dir "$GS" $ST rename ManualSave_4711 'Rodrigo: boss fight?'

echo; echo "### 7. watch: picks up a save created after it starts"
$PY -u "$TOOL" --dir "$GS" $ST watch --interval 0.3 > "$WORK/watch.log" 2>&1 &
WPID=$!
sleep 1
printf 'SAV' > "$GS/AutoSave_77_abc.sav"; printf 'PNG' > "$GS/AutoSave_77_abc.png"
sleep 1
kill $WPID 2>/dev/null; wait $WPID 2>/dev/null
cat "$WORK/watch.log"

echo; echo "### 8. watch with an auto-label template"
$PY -u "$TOOL" --dir "$GS" $ST watch --interval 0.3 --label-template 'Session-{date}-{time}' > "$WORK/watch2.log" 2>&1 &
WPID=$!
sleep 1
printf 'SAV' > "$GS/CheckPoint_88_def.sav"; printf 'PNG' > "$GS/CheckPoint_88_def.png"
sleep 1.5
kill $WPID 2>/dev/null; wait $WPID 2>/dev/null
cat "$WORK/watch2.log"
ls -1 "$GS"

echo; echo "### 9. next-gen .sav without its .png twin"
printf 'SAV' > "$GS/ManualSave_99_c0ffee.sav"
$PY "$TOOL" --dir "$GS" $ST rename ManualSave_99 'Lonely save'

echo; echo "### 10. mode=insert (plain label, no markers)"
printf 'SAV' > "$GS/ManualSave_55_beef.sav"; printf 'PNG' > "$GS/ManualSave_55_beef.png"
$PY "$TOOL" --dir "$GS" $ST rename ManualSave_55 'Plain insert' --mode insert
ls -1 "$GS"

echo; echo "### 11. label memory: the game overwrites the save and reverts the file name"
printf 'SAV' > "$GS/ManualSave_77_abc.sav"; printf 'PNG' > "$GS/ManualSave_77_abc.png"
$PY "$TOOL" --dir "$GS" $ST rename ManualSave_77 'Boss fight'
echo "--- memory file ---"; cat "$WORK/state.json"
echo "--- the game overwrites: it deletes/renames to its own generated name ---"
rm -f "$GS/ManualSave_[Boss fight]_77_abc.sav" "$GS/ManualSave_[Boss fight]_77_abc.png"
$PY -u "$TOOL" --dir "$GS" $ST watch --interval 0.3 > "$WORK/watch3.log" 2>&1 &
WPID=$!
sleep 1
printf 'SAV' > "$GS/ManualSave_77_abc.sav"; printf 'PNG' > "$GS/ManualSave_77_abc.png"
sleep 1.5
kill $WPID 2>/dev/null; wait $WPID 2>/dev/null
cat "$WORK/watch3.log"
echo "--- folder after the overwrite ---"; ls -1 "$GS"

echo; echo "### 12. list, with the label memory in play"
$PY "$TOOL" --dir "$GS" $ST list

echo; echo "### 13. 5.0 save (.sav + .json + .png), mode=keep, and label memory in that mode"
printf 'SAV' > "$GS/ManualSave_1234_abcd.sav"; printf 'META' > "$GS/ManualSave_1234_abcd.json"; printf 'PNG' > "$GS/ManualSave_1234_abcd.png"
$PY "$TOOL" --dir "$GS" $ST rename ManualSave_1234 'Kamil IKE run' --mode keep
ls -1 "$GS" | grep 1234
echo "--- the game overwrites: its own generated name comes back ---"
rm -f "$GS/ManualSave_Kamil IKE run.sav" "$GS/ManualSave_Kamil IKE run.json" "$GS/ManualSave_Kamil IKE run.png"
$PY -u "$TOOL" --dir "$GS" $ST watch --interval 0.3 > "$WORK/watch4.log" 2>&1 &
WPID=$!
sleep 1
printf 'SAV' > "$GS/ManualSave_1234_abcd.sav"; printf 'META' > "$GS/ManualSave_1234_abcd.json"; printf 'PNG' > "$GS/ManualSave_1234_abcd.png"
sleep 1.5
kill $WPID 2>/dev/null; wait $WPID 2>/dev/null
cat "$WORK/watch4.log"
echo "--- folder (the re-applied pair) ---"; ls -1 "$GS" | grep -i "kamil"
echo "--- memory file now stores the mode too ---"; cat "$WORK/state.json"
echo; echo "### done (extended)"
