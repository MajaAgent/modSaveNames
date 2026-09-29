# modSaveNames

**Know whose save you just loaded — and give saves your own names.**
The Witcher 3 (next-gen / 5.0).

Two people share one PC and their saves look identical: the game names every save
`<quest name> - <date>` (measured on 5.0: `Bestia z Białego Sadu - wtorek,
29 września 2026 22:51:58`), which says nothing about who is playing. And the name the
engine derives cannot be set: `.sav`/`.json` carry no name field, and
`GetDisplayNameForSavedGame()` is native (`import final`).

This project solves it in the two places where a name *can* live:

**1. Inside the save — no tool, no file handling.** `setSaveName('Kamil')` writes a
name into the save you are playing, and every world load answers the question on
screen: `Save: Kamil` → [Whose save is this](#whose-save-is-this).

**2. In the save/load list — before that save is loaded.** The list is built from save
**file names**, and scripts have no file access, so the label has to be written into
the file name from outside the game (a companion renamer); the mod then strips the
engine noise and shows only the label → [Naming saves in the list](#naming-saves-in-the-list).

Every rename makes the engine lose its own lookup and fall back to the raw file name —
ugly, but the save stays a proper save: measured on 5.0 a renamed file kept its type
(`3` = manual) and its slot, and the game deletes the old files itself when a slot is
overwritten.

```
ManualSave_8559a_7ea47000_515dab8.sav  ->  ManualSave_[Rodrigo boss fight]_8559a_7ea47000_515dab8.sav
    list shows: "ManualSave_[…]_8559a_… - date"     with the mod: "Rodrigo boss fight"
```

| Part | What it does | Status |
|---|---|---|
| [`content/scripts/local/modSaveNames.ws`](content/scripts/local/modSaveNames.ws) | The mod: in-save names (`setSaveName`), the `Save: X` message on load, and clean labels in the save/load list. | **verified in game on 5.0** — the list hook renders custom labels without the date (`Test etykiety` confirmed in the UI) |
| [`tools/w3save_renamer.py`](tools/w3save_renamer.py) / [`tools/w3save-rename.ps1`](tools/w3save-rename.ps1) | Companion renamers for the list: rename a save's whole family (`.sav` + `.json` + `.png`) so its row carries your label. Python: `list`/`watch`/`--dry-run`; PowerShell: no dependencies. | tested ([transcript](tools/test-output.txt)) |

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

## Whose save is this

In game, in the console (`~` — see [the test doc](docs/TEST-WITHOUT-REDKIT.md)):

```
setSaveName('Kamil')     # name the save you are playing ...
```

**then save the game** — that is what writes the name into the save file. From then on
every world load prints `Save: Kamil` on screen, so you always know whose save you are
in. `showSaveName()` prints what the current save carries; `clearSaveName()` drops it.

* Stored where? In the game's **fact database** — the vanilla mechanism for script data
  that belongs to a save (`scripts/game/facts.ws`). A fact holds one int, so the label
  travels packed four characters per fact: letters, digits, space and common
  punctuation, Polish included, up to 32 characters.
* Why not `@addField(CR4Player) + saved var`, the other way mods persist data? It
  persists just as well, but a field once written into a save may never be removed
  from the mod again — a save whose stored field no longer exists in the code fails to
  load. Facts carry no such coupling, so this mod stays safely uninstallable.
* The message text is English; it is one line in `ModSaveNames_AnnounceLabel()` if you
  want another language.

## Naming saves in the list

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

After the game overwrites that slot it writes a **new file under a name of its own**
and deletes the old one, so the label is gone; give it again with the same command
(`list` shows which saves carry no label). Rename modes: `tag` (default — `[label]` in
brackets, engine ids kept: what the mod reads), `insert`, `keep`, `free`. Options:
`--dry-run`, `--backup`, `--state`, `--mode`, `--label-template`. The label memory in
`~/.w3save_renamer/state.json` is keyed on the engine's own name — and the name the
game writes contains the save's **time**, so it differs on every save and the memory
cannot match it; `watch` still reports new saves as they appear, but re-labelling is a
command, not an automatic.

## Why the mod cannot name the save itself

Checked in the engine's own code and in the full next-gen script source, because it is
the obvious question:

* the file name is composed in C++ — `String::Printf("%ls_%lx_%lx_%lx", prefix,
  displayNameIndex, dateRaw, timeRaw)`, so `ManualSave_53db9_7ea47000_5c98d32` is
  *prefix + the quest name's localization string id + date + time* — and the engine
  parses that name back to recover the save's type and slot;
* the menu text is that **localization string** (`GetDisplayName()`), falling back to
  the raw file name as soon as the name no longer parses — which is exactly what a
  custom label looks like;
* `theGame.SaveGame(type, slot)` takes no name, `GetDisplayNameForSavedGame` is
  `import final`, and the whole save API exposed to scripts (`LoadGameInit`,
  `ListSavedGames`, `DeleteSavedGame`, `RequestAutoSave`, …) can read, load and delete
  saves but **never name one**;
* scripts have no file access, so the mod cannot rename a file after the fact either.

The **list** can therefore only be labelled through the file name, written from
outside the game, while everything after a load — including the name stored *in* the
save — is the mod's job. Both halves exist because neither can do the other's part.

## Knobs in the mod (top of `modSaveNames.ws`)

* `ModSaveNames_SentenceCase()` — `true` (default): the engine reports file names in
  **lower case** (`KamilTest` → `kamiltest`), so the label gets its first letter
  back. `false` shows exactly what the engine reports.
* `ModSaveNames_ShowEngineName()` — `true` appends the engine's own name, e.g.
  `Rodrigo boss fight - Gimme Danger`.

Keep labels to letters, digits, spaces and simple punctuation: the game's font has
no emoji, and Windows forbids `<>:"/\|?*` — both renamers write those as a space and
the mod collapses the runs, while a dash you typed stays a dash.

## Build the release archive

```
./build-release.sh 0.2.0     # -> dist/modSaveNames-0.2.0.zip, layout mods/modSaveNames/content/...
```

## Repository layout

```
content/scripts/local/modSaveNames.ws    the mod
alternatives/modSaveNames_wrapMethod.ws  wrap-instead-of-replace variant (not shipped)
variants/step1-dump-only.ws              same mod with every override stripped (not shipped)
docs/TEST-WITHOUT-REDKIT.md              the 5-minute test + measured 5.0 behaviour + logging
docs/REDKIT-FIRST-STEPS.md               REDkit install, reading the vanilla script, publishing
tools/w3save_renamer.py                  companion renamer (Python)
tools/w3save-rename.ps1                  companion renamer (PowerShell, no dependencies)
tools/test-w3save_renamer.sh             its real test run (synthetic saves, printed transcript)
tools/wscheck.py                         static check (undefined calls, braces) run by the build
build-release.sh                         release zip
```

## Compatibility and caveats

* The mod uses the game's own override annotations (`@replaceMethod`) and edits no
  vanilla file, so it should not need Script Merger.
* The hook is a full re-implementation of the vanilla
  `IngameMenu_PopulateSaveDataForSlotType()`; this body is faithful to the public
  **4.04** dump and works on 5.0 (verified in game). If a future patch adds a row
  member, diff REDkit's 5.0 copy of `igmUtilities.ws` and set it here too.
* The `Save: X` message wraps the player's own `OnSpawned` event
  (`@wrapMethod(CR4Player)`, the merge-free bootstrap other mods use). If a build ever
  reports a compilation error on that line, drop in `variants/step1-dump-only.ws`:
  the same mod with no override at all, so `setSaveName()`/`showSaveName()` and the
  in-save label keep working — only the automatic message and the list labels are gone.
* Known limits: the list name is lower-cased by the engine on the way out, and a
  re-save produces a new file name, so a list label has to be re-applied outside the
  game. The in-save name (feature 1) is unaffected by either.

## Licence

MIT — see [LICENSE](LICENSE).
