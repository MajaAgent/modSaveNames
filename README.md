# modSaveNames

**Custom names for your save games in The Witcher 3 (next-gen / 5.0).**

A save's row in the Load-game menu shows a name the game derives from the save
(measured on 5.0: `<quest name> - <date>`, e.g. `Bestia z Białego Sadu - wtorek,
29 września 2026 22:51:58`). Three saves of the same quest therefore read the same,
and no script can set a save's own name: the `.sav`/`.json` carry no name field, and
`GetDisplayNameForSavedGame()` is a native (`import final`) function.

The one per-save text storage that exists is the **file name**, and the engine
exposes it (`SSavegameInfo.filename`). Every rename makes the engine lose its own
lookup and fall back to printing the file name — ugly, but it stays a proper save:
measured on 5.0, a renamed file kept its type (`3` = manual) and its slot, and the
game cleans up old files itself when a slot is overwritten.

So this project has two halves:

| Half | What it does | Status |
|---|---|---|
| [`content/scripts/local/modSaveNames.ws`](content/scripts/local/modSaveNames.ws) | The mod. Renders a row as `Rodrigo boss fight` when the save's file name carries `[Rodrigo boss fight]`, instead of the engine's raw fallback. Vanilla rows are untouched. | **verified in game on 5.0** — the hook takes over the menu, custom labels show without the date (`Test etykiety` confirmed in the UI) |
| [`tools/w3save_renamer.py`](tools/w3save_renamer.py) / [`tools/w3save-rename.ps1`](tools/w3save-rename.ps1) | The companion renamers: rename a save's whole family (`.sav` + `.json` + `.png` together) to carry a label. Python version has `list`/`watch`/`--dry-run`/label memory; the PowerShell one is a no-dependency one-liner. | tested ([test transcript](tools/test-output.txt)) |

```
ManualSave_8559a_7ea47000_515dab8.sav  ->  ManualSave_[Rodrigo boss fight]_8559a_7ea47000_515dab8.sav
    game shows: "ManualSave_[…]_8559a_… - date"        with the mod: "Rodrigo boss fight"
```

## Try the mod in 5 minutes (no REDkit)

The game compiles `mods/<mod name>/content/scripts/local/*.ws` itself at launch, so
a script mod is just a folder. Full walkthrough:
**[docs/TEST-WITHOUT-REDKIT.md](docs/TEST-WITHOUT-REDKIT.md)** — drop the folder in,
enable it in `mods.settings`, turn on the console, then run the built-in diagnostic:

```
modSaveNames_hello()     # one message on screen: the mod is loaded
modSaveNames_hud()       # per save: slot / type / file name / engine name / what this mod shows
modSaveNames_dump()      # the same, to the script log (needs the -debugscripts flag)
```

Nothing in the mod touches save data; deleting the folder restores vanilla.

## Naming your saves

1. Close the game (the game rewrites these files on save).
2. Give a save a name:
   ```
   python tools/w3save_renamer.py --backup list
   python tools/w3save_renamer.py --backup rename manualsave_5a6e4ad "Rodrigo boss fight"
   ```
   or with nothing installed:
   ```powershell
   .\tools\w3save-rename.ps1 -List
   .\tools\w3save-rename.ps1 -Save manualsave_5a6e4ad -Label "Rodrigo boss fight" -DryRun
   ```
3. Start the game — the row shows `Rodrigo boss fight`.

After the game overwrites that slot it writes a **new file under a name of its own**,
so the label is gone; give it again with the same command (`list` shows which saves
carry no label). Rename modes: `tag` (default — `[label]` in brackets, engine ids
kept: what the mod reads), `insert`, `keep`, `free`. Options: `--dry-run`,
`--backup`, `--state`, `--mode`, `--label-template`. The label memory in
`~/.w3save_renamer/state.json` is keyed on the engine's own name, so `watch` can
re-apply a label by itself *if* the game ever reuses a name for a slot — treat that
as a bonus, not a promise.

## Knobs in the mod (top of `modSaveNames.ws`)

* `ModSaveNames_SentenceCase()` — `true` (default): the engine reports file names in
  **lower case** (`KamilTest` → `kamiltest`), so the label gets its first letter
  back. `false` shows exactly what the engine reports.
* `ModSaveNames_ShowEngineName()` — `true` appends the engine's own name, e.g.
  `Rodrigo boss fight - Gimme Danger`.

Keep labels to letters, digits, spaces and simple punctuation: the game's font has
no emoji, and Windows forbids `<>:"/\|?*` (the tools replace those with `-`, which
the mod renders back as a space).

## Build the release archive

```
./build-release.sh 0.1.6     # -> dist/modSaveNames-0.1.6.zip, layout mods/modSaveNames/content/...
```

## Repository layout

```
content/scripts/local/modSaveNames.ws    the mod
alternatives/modSaveNames_wrapMethod.ws  wrap-instead-of-replace variant (not shipped)
variants/step1-dump-only.ws              console diagnostic only, no hook (not shipped)
docs/TEST-WITHOUT-REDKIT.md              the 5-minute test + measured 5.0 behaviour + logging
docs/REDKIT-FIRST-STEPS.md               REDkit install, reading the vanilla script, publishing
tools/w3save_renamer.py                  companion renamer (Python)
tools/w3save-rename.ps1                  companion renamer (PowerShell, no dependencies)
tools/test-w3save_renamer.sh             its real test run (synthetic saves, printed transcript)
build-release.sh                         release zip
```

## Compatibility and caveats

* The mod uses the game's own override annotations (`@replaceMethod`) and edits no
  vanilla file, so it should not need Script Merger.
* The hook is a full re-implementation of the vanilla
  `IngameMenu_PopulateSaveDataForSlotType()`; this body is faithful to the public
  **4.04** dump and works on 5.0 (verified in game). If a future patch adds a row
  member, diff REDkit's 5.0 copy of `igmUtilities.ws` and set it here too.
* Known limits: names are lower-cased by the engine, and a re-save produces a new
  file name, so a label has to be re-applied outside the game.

## Licence

MIT — see [LICENSE](LICENSE).
