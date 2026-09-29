# modSaveNames

**Custom names for your save games in The Witcher 3 (next-gen / 5.0).**

A save's displayed name in the Load-game menu is the engine's own derivation from
the save data; when it can't derive one, it falls back to the **file name**. That
fallback is the entire naming surface — no script can set a save's name, and the
`.sav`/`.json` contain no name field at all (verified against a real 5.0 save:
`<name>.sav` + `<name>.json` + `<name>.png`, where the `.json` is metadata and the
`.png` thumbnail is looked up by base name).

So this project has two halves:

| Half | What it does | Status |
|---|---|---|
| [`content/scripts/local/modSaveNames.ws`](content/scripts/local/modSaveNames.ws) | The mod. Renders a save's row as `Rodrigo boss fight` when its file name carries the label `[Rodrigo boss fight]`, instead of printing the whole file name. | written, not yet compiled on a real 5.0 install |
| [`tools/w3save_renamer.py`](tools/w3save_renamer.py) | The companion. Renames saves (all `.sav` + `.json` + `.png` together) and with `watch` re-applies your label after the game overwrites it (the engine regenerates the name on every save — and it comes back *the same* name, which is what makes the label memory work). | working, tested ([test script](tools/test-w3save_renamer.sh)) |

```
ManualSave_8559a_7ea47000_515dab8.sav  ->  ManualSave_[Rodrigo boss fight]_8559a_7ea47000_515dab8.sav
    game shows: the whole file name             with the mod the menu shows: Rodrigo boss fight
```

## Try the mod in 5 minutes (no REDkit)

The game compiles `mods/<mod name>/content/scripts/local/*.ws` itself at launch, so
a script mod is just a folder. Full walkthrough:
**[docs/TEST-WITHOUT-REDKIT.md](docs/TEST-WITHOUT-REDKIT.md)** — drop the folder in,
enable it in `mods.settings`, turn on the console, then run the built-in diagnostic:

```
modSaveNames_hello()     # one message on screen: the mod is loaded
modSaveNames_hud()       # per save: file name / engine name / label this mod shows
```

Nothing in the mod touches save data; deleting the folder restores vanilla.

## The companion renamer

```
python tools/w3save_renamer.py list                      # saves + which label is showing
python tools/w3save_renamer.py rename ManualSave_8559a "Rodrigo boss fight"
python tools/w3save_renamer.py rename ManualSave_8559a "Rodrigo boss fight" --mode keep
python tools/w3save_renamer.py watch                     # re-applies labels after the game overwrites them
```

Rename modes: `tag` (default — label in brackets, engine ids kept: what the mod
reads), `insert`, `keep`, `free`. Options: `--dry-run`, `--backup`, `--state`,
`--mode`, `--label-template`. The label memory lives in
`~/.w3save_renamer/state.json`, is keyed on the *engine's* name and stores the mode,
so labels survive overwrites in every mode.

## Build the release archive

```
./build-release.sh 0.1.0     # -> dist/modSaveNames-0.1.0.zip, layout mods/modSaveNames/content/...
```

## Repository layout

```
content/scripts/local/modSaveNames.ws    the mod
alternatives/modSaveNames_wrapMethod.ws  wrap-instead-of-replace variant (not shipped)
variants/step1-dump-only.ws              console diagnostic only, no hook (not shipped)
docs/TEST-WITHOUT-REDKIT.md              the 5-minute test + the annotation gotcha
docs/REDKIT-FIRST-STEPS.md               REDkit install, reading the vanilla script, publishing
tools/w3save_renamer.py                  companion renamer
tools/test-w3save_renamer.sh             its real test run (synthetic saves, printed transcript)
build-release.sh                         release zip
```

## Compatibility and caveats

* The mod uses the game's own override annotations (`@replaceMethod`) and edits no
  vanilla file, so it should not need Script Merger.
* The hook body here is faithful to the public **4.04** script dump. The 5.0 copy of
  `igmUtilities.ws` is not public — REDkit's asset browser is where to check it, and
  a moved row member there is a small fix.
* Two checks only a real game can answer: the label must show in **Load game**, and
  saving must stay untouched. If the console command works but the menu does not
  change, send the output of `modSaveNames_dump()`.

## Licence

MIT — see [LICENSE](LICENSE).
