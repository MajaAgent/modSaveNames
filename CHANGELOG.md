# Changelog

## 0.3.4 - NULL cannot be compared (guard removed)

`if (thePlayer == NULL)` does not compile: **`NULL` is a void literal**, so
`Unable to find suitable operator 'OperatorEqual' for given types (handle:CR4Player, void)`.
The game's own scripts say the same thing by example: `NULL` appears **484** times, every
one of them an assignment or a pass (`buff = NULL;`, `effectManager.SetCurrentlyAnimatedCS(NULL)`,
`EntityHandleSet(usedVehicleHandle, NULL)`), and **zero** comparisons.

So the guard is gone rather than rewritten. Vanilla calls `thePlayer.DisplayHudMessage(text)`
with no guard either (`fastTravelEntity.ws`, `locationArea.ws`), every caller of
`ModSaveNames_Say` has a live player (the console commands and the save/load hooks), and
`ModSaveNames_AnnounceLabel` runs from the player's own `OnSpawned`. The 0.1.7 build that
was verified in game had no guard in this path either.

* `tools/audit-ws.py` now fails on any `== NULL` / `!= NULL`, so this cannot come back.

## 0.3.3 — `null` does not exist in WitcherScript (and a name check that would have said so)

* Both files guarded a message with `if (thePlayer == null)`. **`null` is not a
  WitcherScript literal** — the compiler answers `I dont know any 'null'` — the literal is
  **`NULL`**, in capitals (the parser's own type table: `Type::Null => "NULL"`). Fixed in
  both files.
* The build's name check is new and would have caught it: every word used as a name must
  be declared in the mod, exist in the game's scripts, or be an engine/loader global
  (`theGame`, `thePlayer`, `wrapMethod`, `NULL`, …). A word that is none of those is
  reported, which is exactly the class the compiler answers with `I dont know any 'X'`.
* `tools/audit-ws.py` also masks source with a character scanner instead of a regex: an
  apostrophe inside a `"..."` string — legal, and the game itself writes `npc + "'s dust
  attack"` — made a regex swallow half the file and invent unknown names.
* New `--builtins <dir>` (or `W3_BUILTINS`) for the engine's builtin declarations shipped
  with the parser crate. Some enums exist only there (`ESaveGameType`, `SCO_Uploading`,
  `SCO_Local`), so without it the name check calls them unknown. With corpus + builtins +
  the real parser, 0.3.3's two files pass all three checks.

## 0.3.2 — one reserved word, and a real parser in the build

* `ModSaveNames_MapPut()` used a local variable called `entry`; **`entry` is a reserved
  word** in WitcherScript (TOKEN_ENTRY — it belongs to the state-machine grammar, like
  `cleanup`, `quest`, `reward`, `storyscene`, `single`), so 0.3.1 stopped there:
  `syntax error, unexpected TOKEN_ENTRY, expecting TOKEN_IDENT, near 'entry'`. Renamed to
  `mapEntry`.
* `tools/audit-ws.py` now knows the language's reserved words (taken from the keyword
  table of the third-party parser below) and checks function and class names too, not only
  variables and parameters.
* The build can now run **`witcherscript-check`** — a real WitcherScript parser
  (MIT, tree-sitter based, `cargo install --git
  https://github.com/webspam/witcherscript-language witcherscript-check`). It is the only
  check here that actually parses the language: with it on `PATH` the build also catches
  rules no regex can see, e.g. a local `var` declared after an executable statement
  (`late_local_var_decl`). Tested against a file carrying all three traps of 0.3.0/0.3.1:
  it reports them. **Both mod files parse clean with it**, and the archive is only built
  when every check passes.

## 0.3.1 — 0.3.0 did not compile (two WitcherScript traps)

* `setSaveName(owner : string)`: the parameter was called `name`, and `name` is an engine
  **type** in WitcherScript (`exec function acticon( contentToActivate : name )` in the
  game's own `scripts/engine/game.ws`). The lexer returns TOKEN_TYPE_NAME for it and the
  parser refuses it as a parameter name.
* **No file-scope variables.** WitcherScript has no globals — the compiler rejects `var`
  outside a function, class or state — so both script variables are gone: the save the
  player last asked to load now lives in the same settings group as the map
  (`ModSaveNames / LoadFile`, which also survives a death or a quickload), and the
  "dirty" flag was replaced by `MapPut()` returning whether it changed anything, so the
  settings file is written only when something really changed.
* Starting a new game clears that pointer (`CR4IngameMenu::NewGameRequested`, another
  merge-free `@wrapMethod`), so `showSaveName()` in a new game does not talk about the
  save played before it.
* `tools/audit-ws.py` checks exactly these traps (engine type names as identifiers,
  file-scope `var`, unknown calls, bracket balance) and runs in the build. Point it at the
  game's own scripts for the complete check:
  `W3_CORPUS=/path/to/Witcher3/scripts ./build-release.sh`.

## 0.3.0 — everything in the mod (no companion tool, nothing on disk touched)

* **The save/load list is labelled by the mod itself.** Those rows already come from
  `IngameMenu_PopulateSaveDataForSlotType()`, which the mod owns, so it now writes
  `[Kamil] Bestia z Bialego Sadu - wtorek, ...` for a save that has never been loaded —
  the thing the file-name tool used to do, except no save file is renamed.
* **The map fills itself in.** *save file → player* is kept in the game's own settings
  (`theGame.GetInGameConfigWrapper()` + `SaveUserSettings()`, the wrapper the options menu
  uses — the engine keeps its hidden flags there, mods keep their own groups there). A
  save written while the mod runs is claimed by whoever is playing at that moment, and the
  save a player loads is claimed the same way. Saves that were already on disk when the
  mod was installed are marked `[?]` and taken by one command: `saveNameClaimAll('Kamil')`.
* **Nothing to type in the normal case**: the default player is the game account the menus
  show (`theGame.GetActiveUserDisplayName()`), so two players with two accounts are
  separated with zero setup; on a shared account one `setSaveName('Kamil')` per session
  does it. `setSaveName()` now sets the player *and* the save.
* **A save that says it belongs to someone else says so**, and the mod switches to that
  player — the save is the authority.
* New hooks, both `@wrapMethod` (merge-free): `CR4IngameMenu::LoadSaveRequested` and
  `CR4Game::OnSaveCompleted`. If the settings file is wiped, the mod falls back to exactly
  the 0.2 behaviour.
* `saveNameSettings()` prints where the mod keeps its data; `modSaveNames_hud()`/`_dump()`
  show the player, the map size and the owner of every save.
* Tooling: `tools/wscheck.py` now checks every `.ws` file together, and
  `tools/test-owner-map.py` mirrors the map's string rules in Python — the build refuses
  to ship if the entry format or the chunk count changed.
* The renamer and the thumbnail tool stay as an optional extra, for names that must
  survive with the mod uninstalled.

## 0.2.1 - the picture tells too (companion tool; the mod itself is unchanged)

* `tools/w3save_renamer.py card` draws a name into a save's **thumbnail** - the picture
  the load list shows *before* a save is loaded, which is the only place a name can
  appear that early. `card --labelled` restamps every save that already carries a
  `[label]` with that label; `--text`, `--sub`, `--size`, `--fg`, `--bg`, `--dry-run`
  and `--keep` round it out.
* `tools/card_png.py` - a dependency-free PNG writer plus a 5x7 bitmap font, so the tool
  still runs on a bare Python. Checked by `tools/test-w3save-card.sh` (right file, right
  size, `--dry-run` writes nothing).
* Why the mod cannot do this itself: the frame is captured by the engine, and the API
  scripts get (`theGame.RequestScreenshotData()`, `IsScreenshotDataReady()`,
  `FreeScreenshotData()`, all `import final`) only reads it. The `.png` beside the save
  is the one part of that picture that is just a file.

## 0.2.0 — whose save is it

* **A name stored inside the save.** `setSaveName('X')` writes it into the save you are
  playing (the game's fact database — the vanilla place for script data that belongs to
  a save), and every world load now prints `Save: X` on screen. That is what makes two
  players' saves tellable apart with no file handling at all. `showSaveName()` /
  `clearSaveName()` round it out.
* For that message the mod wraps the player's own `OnSpawned` event
  (`@wrapMethod(CR4Player)`) — the merge-free bootstrap pattern. The list labels from
  0.1.x are unchanged.
* Deliberately facts and not `@addField(CR4Player) + saved var`: a field once written
  into a save may never be removed from the mod again, while facts leave the mod
  safely uninstallable.

## 0.1.7 — label characters, settled

Characters Windows forbids (`<>:"/\|?*`) are now written into the file name as a
**space** instead of a dash, and the mod collapses runs of spaces (`ModSaveNames_Tidy`)
instead of turning every dash into a space. Result: punctuation in a label shows as a
clean single space (`Bez i agrest: finał` -> `Bez i agrest finał`) and a dash the
player typed stays a dash. Both renamers follow the same rule.

## 0.1.6 — labels get their capital letter back

Measured: a file named `KamilTest` is reported by the engine as `kamiltest` — save
file names are lower-cased, so a custom name showed up all lower case in the menu.
The label now gets its first letter back (ASCII only on purpose: slicing a multibyte
Polish character by one byte would corrupt it). New knob
`ModSaveNames_SentenceCase()` — set it to `false` to show exactly what the engine
reports. Only custom labels are touched; vanilla names are untouched.

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
