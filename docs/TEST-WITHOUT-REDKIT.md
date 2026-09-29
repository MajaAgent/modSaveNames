# Testing the mod in 5 minutes (no REDkit needed)
A script mod is not cooked or compiled by REDkit before use: the game compiles
`mods/<mod name>/content/scripts/local/*.ws` itself, at launch. That means the mod
can be tried out with nothing but the game installed — this is exactly the flow the
official REDkit wiki tutorial describes for a first script mod.

## 1. Drop the mod in

In your game installation folder (the one with `bin\`, `content\`, `mods\`):

```
mods\
└── modSaveNames\
    └── content\
        └── scripts\
            └── local\
                └── modSaveNames.ws      <- the file from content/scripts/local/ in this repo
```

## 2. Switch it on

Create (or edit) `Documents\The Witcher 3\mods.settings` and add:

```ini
[modSaveNames]
Enabled=1
Priority=10
```

## 3. Turn the developer console on

Edit `<game>\bin\config\base\general.ini`, find `[General]` and set:

```ini
DBGConsoleOn=true
```

If the console refuses to open with `~`, any "Debug Console Enabler" style mod does
the same thing.

## 4. Launch and run the diagnostic

Start the game and load any save (loading once is what makes the game list saves).
Press `~`, paste, press Enter (Ctrl+V works in the console):

```
modSaveNames_hello()      # one HUD message -> the mod is loaded
modSaveNames_hud()        # the dump, printed ON SCREEN (no launch flags needed)
modSaveNames_dump()       # same data, written to the script log (see below)
```

Each `modSaveNames_hud()` message shows, for one save:

* `file=` the file name on disk — the only place a custom name can live
* `engine=` `GetDisplayNameForSavedGame(...)` — what vanilla would show
* `shows=` the label this mod would display

HUD messages queue up, a few seconds each. This single command tells us whether the
mod's whole API surface works on this game version, without touching the menu.

## What the dump already told us (5.0, in-game, 14 saves)

```
[0] slotType=5 file=checkpoint_53db9_7ea47000_5b3e83f | engine='Bestia z Białego Sadu - wtorek, 29 września 2026 22:51:58' | shows=...
[2] slotType=3 file=manualsave_53db9_7ea47000_5a6e4ad | engine='Bestia z Białego Sadu - wtorek, 29 września 2026 22:38:57' | shows=...
[4] slotType=1 file=autosave_53db9_7ea47000_565809a   | engine='Bestia z Białego Sadu - wtorek, 29 września 2026 21:37:32' | shows=...
[6] slotType=3 file=kamil                               | engine='kamil - wtorek, 29 września 2026 20:38:57'                 | shows='kamil'
[7] slotType=2 file=quicksave_119500_7e920c00_4992ed0  | engine='Poszukiwania: arcymistrzowski rynsztunek Mantikory - niedziela, 4 maja 2025 18:25:11'
```

* A normal save's display name is **`<quest name> - <date>`** (`Bestia z Białego
  Sadu`, `Zlecenie: Zaginiony brat`, `Gwint: Talia Skellige`, ...). Different saves
  of the same quest share a name — which is exactly why custom names are wanted.
* `save.filename` has **no extension** and is reported **in lower case**
  (`manualsave_...`) although the files on disk are `ManualSave_...`. Compare file
  names case-insensitively — a case-sensitive prefix test made every vanilla save
  look hand-renamed (0.1.4 fixed that).
* A hand-renamed file (`kamil.sav`) loses the quest lookup and the engine falls back
  to `<file name> + " - " + localized date`. Its `slotType` is still `3` (manual),
  so the type lives inside the save and the file stays in the right tab.
* `ESaveGameType` values read off the dump: `1` autosave, `2` quicksave, `3` manual,
  `5` checkpoint.
* File names are **lower-cased** in everything the engine reports (`KamilTest` →
  `kamiltest`, also in `GetDisplayNameForSavedGame`), hence the
  `ModSaveNames_SentenceCase()` knob.
* The date in the engine's name is the **file's timestamp**, not something inside the
  save: a byte-identical copy of a save showed the copy's time
  (`kamiltest` 21:02:49 vs `kamil` 20:38:57). Renaming a file does not change its
  timestamp, so a renamed save keeps its original date — copying one does not.
* Overwriting a slot writes a **new file under the game's own name**
  (`ManualSave_53db9_7ea47000_5c98d32.sav`, capitals on disk, reported lower case),
  so the custom text in the old file name is gone and the row goes back to
  `<quest name> - <date>`.
* `shows` is what this mod puts in the row; everything else in the row is vanilla.

## Where does the log go?

The console does **not** echo `LogChannel` output — that is why a log-only dump looks
like it did nothing. Script logs are written to:

```
%USERPROFILE%\Documents\The Witcher 3\scriptlog.txt
```

and only when the game is started with the `-debugscripts` flag (the wiki also lists
`-net`, which additionally lets Script Studio connect). Steam: game → Properties →
Launch Options → `-debugscripts`. Shortcut: append the flag to the Target field:

```
"...\bin\x64\witcher3.exe" -net -debugscripts
```

Then watch the file live (PowerShell `Get-Content "$env:USERPROFILE\Documents\The Witcher 3\scriptlog.txt" -Wait`,
Notepad++ with "tail", or SnakeTail) and grep for the `modSaveNames` channel. The
vanilla scripts are chatty, so filter by channel.

If the file stays empty: delete/rename the `.redscripts` files in
`<game>\content\content0\` and launch again with the flag — the game then regenerates
compiled scripts with logging (community advice from the pre-REDkit era; unverified on
5.0, so try it only if the log really stays empty).

## 5. Then check the menu

1. Close the game.
2. Label a save, e.g. with [w3save_renamer.py](../tools/w3save_renamer.py):
   `python w3save_renamer.py rename ManualSave_<ids> "Rodrigo boss fight"`
   (or just rename the `.sav` + `.json` + `.png` by hand to
   `ManualSave_[Rodrigo boss fight]_<ids>.*`).
3. Start the game again → **Load game**: the row should read `Rodrigo boss fight`.

Without the mod the row shows the whole file name; with it, only the label.

## 6. Whose save is this (0.2.0)

In game, in the console:

```
setSaveName('Kamil')     # then SAVE THE GAME - saving is what writes it into the save
showSaveName()           # what this save carries right now
```

Quit, relaunch, load that save: the HUD says `Save: Kamil`. A save that carries no name
says so and prints the command. `modSaveNames_hud()` also prints
`this save's label: '...'`, so you can check without reloading.

If the name is gone after loading, the game most likely never saved after
`setSaveName` (the fact DB is part of the save, so nothing is written before that).

## When it does not work

* **A "Script Compilation Errors" message at startup.** Good news: it prints the
  file and line. Send that text over — it is the only compiler we have.
* **If the full mod does not compile: use the step-1 file.** Replace
  `content/scripts/local/modSaveNames.ws` with
  [`variants/step1-dump-only.ws`](../variants/step1-dump-only.ws) (same file name).
  It has no override annotation at all — only the console diagnostic — so it cannot
  fail on the hook, and its output still tells us how the menu name is built.
* **The console command does not exist.** The script was not loaded: check the
  folder path (`content/scripts/local/`), the `.ws` extension and `mods.settings`.
* **Nothing changes in the menu, but the console command works.** Then the game
  version moved the code this mod hooks into — send the output of
  `modSaveNames_dump()` and we adjust the hook.
* **Saves still load fine with the mod on** — it only changes what text a row
  displays, never the save data. Removing the mod folder restores vanilla behaviour.

## Annotation gotcha (already handled here)

To replace a **global** function the annotation is written **without parentheses**:

```ws
@replaceMethod            // correct
function SomeGlobalFunction() { ... }

@replaceMethod()          // syntax error: unexpected ')', expecting TOKEN_IDENT
function SomeGlobalFunction() { ... }
```

`@replaceMethod(ClassName)` is for *methods* and needs the class name inside.
