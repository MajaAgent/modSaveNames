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
saveNameSettings()       # where the mod keeps its data and how much of it it has
```

Nothing in the mod touches save data; deleting the folder restores vanilla.

## Whose save is this

In game, in the console (`~` — see [the test doc](docs/TEST-WITHOUT-REDKIT.md)):

```
setSaveName('Kamil')     # this player + the save being played
saveNameClaimAll('Kamil')# take the saves that say no name yet
```

`setSaveName()` sets **who is playing** and stamps the name into the save; **then save
the game** — that is what writes it into the save file. From then on every world load
prints `Save: Kamil` on screen, so you always know whose save you are in, and a save
that carries someone else's name says so and switches the mod to that player.

Usually there is nothing to type at all: the default player name is the **game account**
the menus show (`theGame.GetActiveUserDisplayName()`), so two players with two accounts
are separated with zero setup, and on a shared account one command per session is
enough. `showSaveName()` prints the player, what this save says and its list entry;
`clearSaveName()` drops the name from this save.

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

Nothing to do — the mod labels the rows itself, before a save is ever loaded:

```
[Kamil] Bestia z Bialego Sadu - wtorek, 29 wrzesnia 2026 22:51:58
[?]     Bestia z Bialego Sadu - ...        <- from before the mod: not claimed yet
```

* the map of *save file → player* is kept in the game's own settings
  (`theGame.GetInGameConfigWrapper()` + `SaveUserSettings()`, the wrapper the options
  menu itself uses; the engine keeps its hidden flags there and mods keep their own
  groups there), so no save file is renamed and nothing is written beside them;
* it fills itself in: a save written while the mod runs is claimed by whoever is
  playing at that moment, and the save a player loads is claimed the same way;
* saves that were already on disk when the mod was installed are marked `[?]` so the mod
  never guesses about them — claim them all with one command:
  ```
  saveNameClaimAll('Kamil')
  ```
* `saveNameSettings()` shows where the mod keeps this and how much of it it has;
  `modSaveNames_hud()` / `modSaveNames_dump()` show the owner of every save.

If the settings file is ever wiped (new profile, cloud reset), the mod simply marks
everything `[?]` again and starts collecting: the name stored *inside* a save and the
`Save: X` message are unaffected.

### The optional renamer (writes into the file name)

Still there for anyone who wants names that survive with the mod uninstalled.

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

### Putting the name on the picture

The thumbnail beside a save is an ordinary `.png` next to the `.sav` (the engine finds
it by base name and scales whatever is there), and that picture is visible in the load
list **before** the save is loaded. The mod cannot touch it - the frame is captured by
the engine, and everything scripts get (`theGame.RequestScreenshotData()` and friends)
is `import final` - but the renamer can:

```
python3 tools/w3save_renamer.py card --labelled                      # every labelled save gets its name drawn in
python3 tools/w3save_renamer.py card ManualSave_[KAMIL]_8559a_7ea47000_515dab8 --text "KAMIL" --sub "brat: BARTEK"
```

* the card keeps the size of the picture it replaces (so the list looks unchanged);
  `--size WxH` overrides it, `--dry-run` shows what would happen, `--keep` stashes the
  replaced picture as `<name>.png.orig`;
* drawing needs no image library at all: `tools/card_png.py` writes a plain PNG and
  carries a 5x7 bitmap font, so a bare Python is enough;
* **the game redraws that picture the next time the slot is saved**, so run `card`
  again afterwards - the same dance as with the file name.

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

So the engine's own name for a save (`<quest name> - <date>`) and the save's thumbnail
cannot be changed from a script — the mod does the only thing that is left, and it turns
out to be enough: it keeps its **own** map of file → player and writes the rows of the
list itself, which is the text the player actually reads. The name inside the save
(above) covers everything after the load. Both halves are in the mod now; the renamer is
only for names that must survive without it.

## Knobs in the mod (top of `modSaveNames.ws`)

* `ModSaveNames_SentenceCase()` — `true` (default): the engine reports file names in
  **lower case** (`KamilTest` → `kamiltest`), so the label gets its first letter
  back. `false` shows exactly what the engine reports.
* `ModSaveNames_ShowEngineName()` — `true` appends the engine's own name, e.g.
  `Rodrigo boss fight - Gimme Danger`.
* `ModSaveNames_UseAccountName()` — `true` (default, in `modSaveNamesProfile.ws`) takes
  the player's name from the game account the menus show. `false` keeps the mod silent
  until someone types `setSaveName('Kamil')`.

The account name is never used when the game reports a generic one (`Player`, `user`,
`Guest`) — then the mod waits for `setSaveName()`.

Keep labels to letters, digits, spaces and simple punctuation: the game's font has
no emoji, and Windows forbids `<>:"/\|?*` — both renamers write those as a space and
the mod collapses the runs, while a dash you typed stays a dash.

## Build the release archive

```
./build-release.sh 0.2.0     # -> dist/modSaveNames-0.2.0.zip, layout mods/modSaveNames/content/...
```

## Repository layout

```
content/scripts/local/modSaveNames.ws    the mod: list rows + the in-save name
content/scripts/local/modSaveNamesProfile.ws  the mod: player, the file->player map, its hooks
alternatives/modSaveNames_wrapMethod.ws  wrap-instead-of-replace variant (not shipped)
variants/step1-dump-only.ws              same mod with every override stripped (not shipped)
docs/TEST-WITHOUT-REDKIT.md              the 5-minute test + measured 5.0 behaviour + logging
docs/REDKIT-FIRST-STEPS.md               REDkit install, reading the vanilla script, publishing
tools/w3save_renamer.py                  companion renamer (Python)
tools/w3save-rename.ps1                  companion renamer (PowerShell, no dependencies)
tools/test-w3save_renamer.sh             its real test run (synthetic saves, printed transcript)
tools/wscheck.py                         static check (undefined calls, braces) run by the build
tools/audit-ws.py                        WitcherScript traps (engine type names, file-scope var)
tools/test-owner-map.py                  runs the map's string rules in Python (run by the build)
tools/card_png.py                        PNG writer + 5x7 bitmap font for thumbnails (no dependencies)
tools/test-w3save-card.sh                its test run (right file, right size, --dry-run writes nothing)
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
* Four more overrides, all `@wrapMethod` and therefore merge-free: `CR4Player::OnSpawned`
  (the `Save: X` message and the player switch), `CR4IngameMenu::LoadSaveRequested` (which
  save is being loaded), `CR4Game::OnSaveCompleted` (the file the engine has just written)
  and `CR4IngameMenu::NewGameRequested` (forget the previously loaded save). If a build
  reports a compilation error on one of them, delete that one function — the rest keeps
  working — in this order: `NewGameRequested`, `OnSaveCompleted`, `LoadSaveRequested`;
  `OnSpawned` is the 0.2 feature and should stay.
* WitcherScript has **no globals**: `var` outside a function, class or state is a syntax
  error, and scripts are reloaded without warning. Every value that has to outlive a
  single call therefore lives in the settings group (`Installed`, `Profile`, `LoadFile`
  and the map chunks) — which is also why they survive a quickload, a death and a menu.
* Known limits: the map's entries live in `user.settings`, so a player who wipes that
  file starts collecting again (everything is marked `[?]`); `showSaveName()` /
  `clearSaveName()` refer to the last save that was loaded or requested, and starting a
  new game clears that pointer; the engine's own row name — quest plus date — is still
  whatever the game wrote, and the thumbnail is still the engine's picture. The in-save
  name (feature 2) is unaffected by all of this.

## Licence

MIT — see [LICENSE](LICENSE).
