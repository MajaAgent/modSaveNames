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
modSaveNames_dump()
```

It prints, for every save the game knows about:

* `file:` the file name on disk — the only place a custom name can live
* `engine:` `GetDisplayNameForSavedGame(...)` — what vanilla would show
* `modSaveNames:` the label the mod would display

Look for the log lines (channel `modSaveNames`). This single command tells us
whether the mod's whole API surface works on this game version, without touching
the menu.

## 5. Then check the menu

1. Close the game.
2. Label a save, e.g. with [w3save_renamer.py](../tools/w3save_renamer.py):
   `python w3save_renamer.py rename ManualSave_<ids> "Rodrigo boss fight"`
   (or just rename the `.sav` + `.json` + `.png` by hand to
   `ManualSave_[Rodrigo boss fight]_<ids>.*`).
3. Start the game again → **Load game**: the row should read `Rodrigo boss fight`.

Without the mod the row shows the whole file name; with it, only the label.

## When it does not work

* **A "Script Compilation Errors" message at startup.** Good news: it prints the
  file and line. Send that text over — it is the only compiler we have.
* **The console command does not exist.** The script was not loaded: check the
  folder path (`content/scripts/local/`), the `.ws` extension and `mods.settings`.
* **Nothing changes in the menu, but the console command works.** Then the game
  version moved the code this mod hooks into — send the output of
  `modSaveNames_dump()` and we adjust the hook.
* **Saves still load fine with the mod on** — it only changes what text a row
  displays, never the save data. Removing the mod folder restores vanilla behaviour.
