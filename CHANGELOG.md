# Changelog

## 0.1.5 — the dump reports the save slot

`modSaveNames_hud()` now prints `slot=` (`SSavegameInfo.slotIndex`) next to `type=`.
The slot number, not the file name, is the only stable key a label memory can key
on after an overwrite: the engine names every new save file with a fresh id, so a
mapping keyed on the file name would not survive it.

## 0.1.4 — case-insensitive: vanilla saves show their quest names again

Regression from 0.1.3, found in the first 14-save dump: the engine reports save
file names **in lower case** (`manualsave_53db9_7ea47000_5a6e4ad`) even though the
files on disk are `ManualSave_...`, and `StrBeginsWith` is case-sensitive. Every
vanilla save was therefore treated as hand-renamed and the load menu printed raw
file names (`checkpoint_53db9_...`) instead of quest names. Fixed by lower-casing
before the prefix test, and the prefix list now matches what 5.0 really writes.

What that same dump proved:

* the display name of a normal save is `<quest name> - <date>`, e.g.
  `Bestia z Białego Sadu - wtorek, 29 września 2026 22:51:58`; renaming a file
  makes the engine lose that lookup and fall back to `<file name> - <date>`
* `ESaveGameType` values read off the dump: `1` autosave, `2` quicksave,
  `3` manual, `5` checkpoint — and a hand-renamed `kamil` still reports `3`,
  so the type lives inside the save, not in the file name
* the `@replaceMethod` hook really does take over the menu (the rows changed)

## 0.1.3 — a hand-renamed save shows its own name

* Measured in-game: for a file renamed to `kamil.sav` the engine reports
  `kamil - wtorek, 29 września 2026 20:38:57` — i.e. when it cannot classify a
  file it falls back to `<file name> + date`. `save.filename` carries no
  extension (`kamil`), `slotType` was 3.
* New: a file whose name the engine would not have generated is taken as the
  custom name as-is (`kamil` shows as `kamil`, no date glued on). The `[label]`
  tag mode still wins when present, and `Prettify` now only rewrites dashes
  inside brackets, so a hand-typed name keeps its characters.
* Nothing changed for saves the game named itself — they show the vanilla text.

## 0.1.2 — output you can actually see

* The console never echoed `LogChannel` output (script logs only appear in
  `Documents\The Witcher 3\scriptlog.txt`, and only with the `-debugscripts` launch
  flag), so the diagnostic looked like it did nothing. Added:
  * `modSaveNames_hello()` — one HUD message: proof the script is loaded.
  * `modSaveNames_hud()` — the same dump, printed on screen via
    `GetWitcherPlayer().DisplayHudMessage()` (no launch flags needed).
  * `modSaveNames_dump()` — stays log-only, for the `scriptlog.txt` route.
* Docs: where the log lives, how to launch with `-debugscripts`, how to watch the file.

## 0.1.1 — first compile error fixed

* **`@replaceMethod()` → `@replaceMethod`.** The empty parentheses are a syntax
  error for a global function (`unexpected ')', expecting TOKEN_IDENT`); the REDkit
  wiki documents the bare annotation form. Same fix in the wrap variant
  (`@wrapMethod`) — for a global function the bare form is the guess, since only
  `@replaceMethod` is documented for globals.
* Added [`variants/step1-dump-only.ws`](variants/step1-dump-only.ws): the console
  diagnostic alone, with no override annotation, for when the hook refuses to
  compile.

## 0.1.0 — first public build (not yet compiled on a real install)

* The mod: replaces the global `IngameMenu_PopulateSaveDataForSlotType` (and the W2
  import list) so a save whose file name carries a `[custom label]` shows just that
  label; otherwise vanilla's own name is kept. Ships with `modSaveNames_dump()`, an
  `exec function` that prints file name / engine name / mod label for every save.
* An alternative wrap-instead-of-replace implementation under `alternatives/`.
* The companion `tools/w3save_renamer.py`: `list` / `rename` / `watch` with four
  rename modes, dry-run, backup, name sanitising, and a label memory keyed on the
  engine's own save name so a label survives the game overwriting the save.
* The renamer moves **all** files of one save together — `.sav` + `.json` + `.png`
  (measured 5.0 layout) — and backs all of them up.
* Docs for the 5-minute drop-in test and for a first-ever REDkit session.
* The hook body comes from the public next-gen 4.0 script dump.

### Known unknowns

* Whether 5.0's `igmUtilities.ws` changed the row members or the function
  signature (diff before compiling).
* Whether an override annotation can replace a *global* function in 5.0 — if not,
  switch to `alternatives/modSaveNames_wrapMethod.ws`.
* The mod only renders names; keeping a name across an in-game overwrite is the
  companion renamer's job (label memory).
