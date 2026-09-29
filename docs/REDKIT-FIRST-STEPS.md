# REDkit: first steps (for someone who has never opened it)

REDkit is **not required to run this mod** — see
[TEST-WITHOUT-REDKIT.md](TEST-WITHOUT-REDKIT.md). It is needed for two things:

1. reading the game's own (vanilla) script that this mod hooks, so the hook can be
   made exact for your game version, and
2. publishing the mod properly (a project + `/publish` folder, then Workshop/Nexus).

## Install and first launch

*(from CDPR's official "Starting the Editor" page)*

1. REDkit is a **separate free product** on the same PC stores as the game: Steam
   (app `2684660`, "The Witcher 3 REDkit"), GOG, and Epic. It needs the PC game
   installed — you have that.
2. Launch it from the storefront. If nothing happens, the manual way is
   `bin\x64_RedKit\editor.exe` inside the REDkit install.
3. First launch sets up an **uncook**: it wants a valid **game path**
   (e.g. `C:\Games\GOG\The Witcher 3\`) and a **depot path** (e.g. `C:\REDkit\depot\`,
   an empty-ish folder where the unpacked game files go). Choose both and press
   **Generate**.
4. Wait for the progress bar and until the status says **Depot is valid** → **Continue**.
   This is the long, one-time step (tens of GB).
5. **Create a new project**: give it a name and a location; the project then holds
   `\workspace` (the assets you edit) and `\publish` (the finished mod, ready for
   Steam/Nexus). Next launches offer it under *Recent projects*.

## Reading the script this mod hooks

The point is to see the real 5.0 version of
`game/gui/main_menu/ingamemenu/igmUtilities.ws`.

1. In REDkit, open the asset/content browser (the left-hand browser panel).
2. Type `igmUtilities` into its filter/search box — it searches asset paths, so a
   filename is enough.
3. Double-click `game/gui/main_menu/ingamemenu/igmUtilities.ws`. It opens in the
   script editor with the vanilla source.
4. Find `IngameMenu_PopulateSaveDataForSlotType` (Ctrl+F for `PopulateSaveData`)
   and copy that whole function out — that is the single thing needed to make
   `content/scripts/local/modSaveNames.ws` exact instead of "4.04-faithful".
   The version pinned in this repo came from a public 4.04 script dump; the 5.0
   release may or may not have touched it, and only the real file settles that.

Wording of the UI panels differs a little between REDkit versions — the search box
is what matters: it takes a plain filename.

## If you want the mod visible in REDkit as a project

1. Create (or open) a project, then in the asset browser create the folder chain
   `content\scripts\local\` inside the mod's content and add `modSaveNames.ws` there
   (that is the same layout the game loads from `mods\<name>\`).
2. Use **Script Studio** (the scripting workspace) to compile and to debug with
   breakpoints and hot reload; the official wiki has a 14-part video course,
   including *11. Working with scripts* and *12. UI modding*.
3. `Publish` tab → *Save and publish mod project*: name, version, description,
   thumbnail; it cooks the mod into `\packed` and can either publish to the Steam
   Workshop or export a zip for Nexus Mods.

## What is not needed

* No REDkit for the drop-in test, no REDkit to keep the mod installed.
* No uncook/depot is required just to use the game with mods in `mods\`.
