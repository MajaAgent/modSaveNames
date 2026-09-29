# Changelog

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
