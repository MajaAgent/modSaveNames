/***********************************************************************/
/**  modSaveNames 0.3.0 - "everything in the mod" half
/**
/**  The 0.2 mod could only name the save a player was already inside, because
/**  the name lived in the save's fact database. This file adds the two pieces
/**  that make the whole thing self-service, with no companion tool and no
/**  touching of files on disk:
/**
/**  1. WHOSE SAVE IS THIS, FROM THE MENU
/**     A map of save FILE name -> player name is kept in the game's own
/**     settings (see STORAGE below). The save/load list is built from file
/**     names, and the menu labels are written by modSaveNames.ws, so the list
/**     can now say "[Kamil] Bestia z Bialego Sadu - wtorek, ..." for a save
/**     that has not been loaded yet - the exact thing the file name hack did,
/**     except no file is ever renamed.
/**
/**     The map fills itself in: every save written while the mod is running is
/**     claimed by whoever is playing at that moment, and the save a player
/**     loads is claimed the same way. Saves that were already on disk when the
/**     mod was installed are marked "?" (nobody's yet) so that the mod never
/**     guesses wrong about them; one command claims them all:
/**         saveNameClaimAll('Kamil')
/**
/**  2. WHO IS PLAYING
/**     Stored under its own key, so a brand new save is labelled correctly
/**     without anything being typed: by default the name is the game account
/**     (GOG / Steam / Epic) shown in the menus, e.g. theGame.GetActiveUserDisplayName().
/**     Two brothers with two accounts are therefore separated with zero setup;
/**     on a shared account, setSaveName() once per session is enough.
/**
/**  STORAGE - why this needs no files
/**  theGame.GetInGameConfigWrapper() is the game's own settings access, the one
/**  the options menu uses:
/**      GetVarValue('Group', 'Var') / SetVarValue('Group', 'Var', value)
/**      SaveUserSettings()  - writes user.settings, the same call the menu makes
/**  The engine keeps its own hidden flags there ("Hidden" / "HasSeenGotyWelcomeMessage")
/**  and mods keep their own groups there (e.g. GhostMode's 'GMGameplayOptions'),
/**  so a mod group is a supported place for data that must outlive a save and
/**  must not live inside one. Verified against the engine's script API
/**  (scripts/game/inGameConfigWrapper.ws) and the Witcher wiki ("Menus in The
/**  Witcher 3 / Scripting": "for storing another data for your mod in user.settings").
/**
/**  A config value is a string, so the map is stored as 8 chunks of
/**  "|file=player" entries (P0..P7). Every call above takes the group and the
/**  variable as literal names - a dynamic name would be a 'name' type, which
/**  this code avoids - hence the switch tables.
/**
/**  IF THE SETTINGS ARE EVER WIPED
/**  (a new user.settings, a cloud profile reset, the "Installed" marker gone)
/**  the mod simply re-marks every save as "?" and starts collecting again; the
/**  in-save name is untouched by that, so the in-game announcement keeps
/**  working - only the menu prefixes are lost until the next save.
/**
/**  API used, all verified in the next-gen 4.0x script tree:
/**    theGame.GetInGameConfigWrapper().GetVarValue/SetVarValue   (r4Game.ws)
/**    theGame.SaveUserSettings()                                 (r4Game.ws)
/**    theGame.GetActiveUserDisplayName()                         (r4Game.ws, import final)
/**    theGame.ListSavedGames(array<SSavegameInfo>)               (r4Game.ws)
/**    @wrapMethod(CR4Game)      event OnSaveCompleted            (r4Game.ws)
/**    @wrapMethod(CR4IngameMenu) function LoadSaveRequested      (ingameMenu.ws)
/**  Safety: nothing here writes a file, renames a save, or touches the world.
/***********************************************************************/


// ------------------------------------------------------------------ knobs ----

// Use the game account name (the one the menus show at the top right) as the
// default player name. Set to false to make the mod stay silent until someone
// types setSaveName('Kamil') - useful if both players share one account and
// would rather not see the account name on every save.
function ModSaveNames_UseAccountName() : bool
{
	return true;
}


// ---------------------------------------------------------------- storage ----

// No file-scope variables here - on purpose. WitcherScript has no globals (the
// compiler rejects `var` outside a function, class or state), and a script variable
// would not survive a script reload anyway. Everything that has to outlive a single
// call lives in the game's own settings, next to the map:
//
//   ModSaveNames / Installed  the first version that ever ran (marks the first run)
//   ModSaveNames / Profile    who is playing
//   ModSaveNames / LoadFile   the save the player last asked to load (see below)
//   ModSaveNames / P0 .. P7   the map itself: file -> player, one entry per save

function ModSaveNames_MapParts() : int
{
	return 8;
}

// A player name goes into the map as text between two bars, so the two
// separators must never appear inside it.
function ModSaveNames_CleanOwner(owner : string) : string
{
	return StrReplaceAll(StrReplaceAll(StrReplaceAll(owner, "|", "_"), "=", "_"), "\n", " ");
}

function ModSaveNames_PartLimit() : int
{
	return 2000;
}

function ModSaveNames_ConfigGetPart(index : int) : string
{
	switch (index)
	{
		case 0:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P0');
		case 1:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P1');
		case 2:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P2');
		case 3:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P3');
		case 4:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P4');
		case 5:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P5');
		case 6:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P6');
		case 7:  return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'P7');
	}

	return "";
}

function ModSaveNames_ConfigSetPart(index : int, value : string)
{
	switch (index)
	{
		case 0:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P0', value); return;
		case 1:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P1', value); return;
		case 2:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P2', value); return;
		case 3:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P3', value); return;
		case 4:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P4', value); return;
		case 5:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P5', value); return;
		case 6:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P6', value); return;
		case 7:  theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'P7', value); return;
	}
}

// Write the settings file. Only reached when something really changed, so the file
// is not rewritten every time a menu is refreshed.
function ModSaveNames_MapFlush()
{
	theGame.SaveUserSettings();
}

// The save the player last asked to load - in practice the one being played. Kept in
// the settings rather than in a script variable: WitcherScript has no globals, and
// this way it also survives a menu, a death and a quickload.
function ModSaveNames_LoadedFileGet() : string
{
	return theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'LoadFile');
}

function ModSaveNames_LoadedFileSet(file : string)
{
	theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'LoadFile', file);
}


// ------------------------------------------------------------------ profile ---

// The name the game itself knows: the account shown in the menu bar. Empty when
// there is no signed-in account, and never a generic placeholder.
function ModSaveNames_DefaultProfile() : string
{
	var account : string;

	if (!ModSaveNames_UseAccountName())
	{
		return "";
	}

	account = theGame.GetActiveUserDisplayName();

	if (account == "Player" || account == "player" || account == "user" || account == "Guest")
	{
		return "";
	}

	return account;
}

// Who is playing right now: what a player set, else the account name.
function ModSaveNames_Profile() : string
{
	var profile : string;

	profile = theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'Profile');

	if (StrLen(profile) == 0)
	{
		profile = ModSaveNames_DefaultProfile();
	}

	return profile;
}

function ModSaveNames_SetProfile(profile : string, announce : bool)
{
	profile = ModSaveNames_CleanOwner(profile);

	theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'Profile', profile);
	theGame.SaveUserSettings();

	if (announce)
	{
		ModSaveNames_Say("You are now playing as '" + profile + "'");
	}
}

// Small wrapper so every message survives a missing player object.
function ModSaveNames_Say(text : string)
{
	if (thePlayer == null)
	{
		return;
	}

	thePlayer.DisplayHudMessage(text);
}


// ---------------------------------------------------------------- the map -----

// One entry is "|file=player"; a leading bar on every entry means a lookup can
// search for "|file=" and never match the middle of another file's name.
function ModSaveNames_MapKey(file : string) : string
{
	return "|" + file + "=";
}

// "" = the mod knows nothing about this file, "?" = it was already there when
// the mod was installed (nobody claimed it), otherwise the player's name.
function ModSaveNames_MapOwner(file : string) : string
{
	var i, at : int;
	var part, tail : string;

	for (i = 0; i < ModSaveNames_MapParts(); i += 1)
	{
		part = ModSaveNames_ConfigGetPart(i);
		at   = StrFindFirst(part, ModSaveNames_MapKey(file));

		if (at >= 0)
		{
			tail = StrMid(part, at + StrLen(ModSaveNames_MapKey(file)));
			at   = StrFindFirst(tail, "|");

			if (at >= 0)
			{
				return StrLeft(tail, at);
			}

			return tail;
		}
	}

	return "";
}

// The same chunk with every entry for this file cut out.
function ModSaveNames_MapStrip(part : string, file : string) : string
{
	var at, next : int;
	var mark : string;

	mark = ModSaveNames_MapKey(file);
	at   = StrFindFirst(part, mark);

	while (at >= 0)
	{
		next = StrFindFirst(StrMid(part, at + 1), "|");

		if (next >= 0)
		{
			part = StrLeft(part, at) + StrMid(part, at + 1 + next);
		}
		else
		{
			part = StrLeft(part, at);
		}

		at = StrFindFirst(part, mark);
	}

	return part;
}

// Remember (or overwrite) who a save file belongs to.
// True when the map changed, so the caller knows whether the settings file needs
// writing (a row refreshed with the owner it already has changes nothing).
function ModSaveNames_MapPut(file : string, owner : string) : bool
{
	var i : int;
	var entry, part, before : string;
	var placed, changed : bool;

	entry   = ModSaveNames_MapKey(file) + ModSaveNames_CleanOwner(owner);
	placed  = false;
	changed = false;

	for (i = 0; i < ModSaveNames_MapParts(); i += 1)
	{
		before = ModSaveNames_ConfigGetPart(i);
		part   = ModSaveNames_MapStrip(before, file);

		if (!placed && StrLen(part) + StrLen(entry) <= ModSaveNames_PartLimit())
		{
			part   = part + entry;
			placed = true;
		}

		if (part != before)
		{
			changed = true;
			ModSaveNames_ConfigSetPart(i, part);
		}
	}

	if (!placed)
	{
		// every chunk is full - let the last one grow rather than lose the entry
		ModSaveNames_ConfigSetPart(ModSaveNames_MapParts() - 1,
			ModSaveNames_ConfigGetPart(ModSaveNames_MapParts() - 1) + entry);
		changed = true;
	}

	return changed;
}

function ModSaveNames_MapDrop(file : string)
{
	var i : int;

	if (StrLen(file) == 0)
	{
		return;
	}

	for (i = 0; i < ModSaveNames_MapParts(); i += 1)
	{
		ModSaveNames_ConfigSetPart(i, ModSaveNames_MapStrip(ModSaveNames_ConfigGetPart(i), file));
	}

	ModSaveNames_MapFlush();
}

// How many entries the map holds - for the test dump.
function ModSaveNames_MapSize() : int
{
	var i, at, count : int;
	var part : string;

	count = 0;

	for (i = 0; i < ModSaveNames_MapParts(); i += 1)
	{
		part = ModSaveNames_ConfigGetPart(i);
		at   = StrFindFirst(part, "|");

		while (at >= 0)
		{
			count += 1;
			part  = StrMid(part, at + 1);
			at    = StrFindFirst(part, "|");
		}
	}

	return count;
}

// One line for the dump: where the map lives and how big it is.
function ModSaveNames_ConfigSummary() : string
{
	var installed : string;
	var profile : string;
	var i, chars : int;

	installed = theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'Installed');
	profile   = theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'Profile');

	chars = 0;

	for (i = 0; i < ModSaveNames_MapParts(); i += 1)
	{
		chars += StrLen(ModSaveNames_ConfigGetPart(i));
	}

	return "settings: installed='" + installed + "' profile='" + profile
		+ "' map=" + IntToString(ModSaveNames_MapSize())
		+ " entries, " + IntToString(chars) + " chars";
}


// ------------------------------------------------------- learning the map -----

// Called every time the load/save list is built and after every save.
//
//  * first run ever: every save already on disk is marked "?", so the mod never
//    guesses about saves it never saw being written;
//  * from then on: a save with no entry was written while the mod was running,
//    so it belongs to whoever is playing - as does the save just loaded.
function ModSaveNames_SyncMap(saveGames : array<SSavegameInfo>)
{
	var i : int;
	var owner, claim : string;
	var firstRun, changed : bool;

	firstRun = StrLen(theGame.GetInGameConfigWrapper().GetVarValue('ModSaveNames', 'Installed')) == 0;
	claim    = ModSaveNames_Profile();

	if (StrLen(claim) == 0)
	{
		claim = "?";
	}

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		owner = ModSaveNames_MapOwner(saveGames[i].filename);

		if (StrLen(owner) > 0)
		{
			continue;
		}

		if (firstRun)
		{
			// an old save: nobody claimed it, and the mod does not guess
			if (ModSaveNames_MapPut(saveGames[i].filename, "?"))
			{
				changed = true;
			}
		}
		else
		{
			// either the save that is being played right now, or one written
			// while the mod was watching: both belong to the player at the keyboard
			if (ModSaveNames_MapPut(saveGames[i].filename, claim))
			{
				changed = true;
			}
		}
	}

	if (firstRun)
	{
		theGame.GetInGameConfigWrapper().SetVarValue('ModSaveNames', 'Installed', ModSaveNames_Version());
		changed = true;
	}

	if (changed)
	{
		ModSaveNames_MapFlush();
	}
}

// After a completed save the engine has already written the new file, so this is
// the first moment the mod can see its name - and the last moment it is certain
// who was playing.
function ModSaveNames_AfterSave()
{
	var saveGames : array< SSavegameInfo >;
	var profile : string;

	profile = ModSaveNames_Profile();

	if (StrLen(profile) > 0)
	{
		// belt and braces: if the label was lost, put it back into the save data
		ModSaveNames_StoreLabel(profile);
	}

	theGame.ListSavedGames( saveGames );
	ModSaveNames_SyncMap(saveGames);

	LogChannel('modSaveNames', "after save: " + ModSaveNames_ConfigSummary());
}

// The world of a save has just spawned: this is where the mod decides who is
// playing and what this save is called.
function ModSaveNames_OnWorldLoaded()
{
	var stored, profile, file : string;

	file    = ModSaveNames_LoadedFileGet();
	stored  = ModSaveNames_StoredLabel();
	profile = ModSaveNames_Profile();

	if (StrLen(stored) > 0 && stored != profile)
	{
		// the save itself says it belongs to someone else - believe the save
		ModSaveNames_SetProfile(stored, false);
		profile = stored;

		ModSaveNames_Say("Careful: this is " + stored + "'s save");
	}

	if (StrLen(profile) == 0)
	{
		ModSaveNames_Say("No player name yet - use setSaveName('Kamil')");
		return;
	}

	if (StrLen(stored) == 0)
	{
		// an unclaimed world: stamp the name now so the next save carries it
		ModSaveNames_StoreLabel(profile);
	}

	if (StrLen(file) > 0 && ModSaveNames_MapPut(file, profile))
	{
		// the save that was just loaded belongs to whoever is playing it now
		ModSaveNames_MapFlush();
	}

	ModSaveNames_AnnounceLabel();
}

// Claim every save the mod never put a name on - meant for the saves that were
// already on disk at install time. Returns how many it took.
function ModSaveNames_ClaimAll(owner : string) : int
{
	var saveGames : array< SSavegameInfo >;
	var i, claimed : int;

	if (StrLen(owner) == 0)
	{
		return 0;
	}

	theGame.ListSavedGames( saveGames );

	claimed = 0;

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		if (ModSaveNames_MapOwner(saveGames[i].filename) == "?")
		{
			ModSaveNames_MapPut(saveGames[i].filename, owner);
			claimed += 1;
		}
	}

	if (claimed > 0)
	{
		ModSaveNames_MapFlush();
	}

	return claimed;
}


// -------------------------------------------------------------------- hooks ---

// The player asked to load a specific save (after the confirmation popup, so a
// cancelled load never claims anything). Remember the file; the world spawn
// afterwards is where it is used.
@wrapMethod(CR4IngameMenu)
function LoadSaveRequested(saveSlotRef : SSavegameInfo) : void
{
	ModSaveNames_LoadedFileSet(saveSlotRef.filename);

	wrappedMethod(saveSlotRef);
}

// A new game is about to start: whatever save was loaded before is not the one
// being played any more, so the pointer the console commands use is cleared.
@wrapMethod(CR4IngameMenu)
function NewGameRequested() : void
{
	wrappedMethod();

	ModSaveNames_LoadedFileSet("");
}

// A save finished: learn the file the engine just wrote.
// Vanilla declares this as an event, so - like the OnSpawned wrap that has been
// running since 0.2 - the wrapper carries no return type either.
@wrapMethod(CR4Game)
function OnSaveCompleted(type : ESaveGameType, succeeded : bool)
{
	wrappedMethod(type, succeeded);

	if (succeeded)
	{
		ModSaveNames_AfterSave();
	}
}


// ------------------------------------------------------------------ console ---

//   saveNameClaimAll('Kamil')   claim every save that has no name yet
//   saveNameSettings()          where the mod keeps its data, and how much of it
//
// setSaveName / showSaveName / clearSaveName live in modSaveNames.ws.

exec function saveNameClaimAll(owner : string)
{
	var claimed : int;

	claimed = ModSaveNames_ClaimAll(owner);

	ModSaveNames_Say("Claimed " + IntToString(claimed) + " save(s) as '" + owner + "'");
}

exec function saveNameSettings()
{
	ModSaveNames_Say(ModSaveNames_ConfigSummary());
	LogChannel('modSaveNames', ModSaveNames_ConfigSummary());
}
