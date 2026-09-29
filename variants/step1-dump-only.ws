/***********************************************************************/
/**  modSaveNames - every override stripped out (variant, not shipped).
/**
/**  Same mod as content/scripts/local/modSaveNames.ws minus the two annotations
/**  and the wrappedMethod() call, i.e. nothing in the game is hooked:
/**    * setSaveName('X') / showSaveName() / clearSaveName() still work, and the
/**      name is still stored inside the save (facts) - it just cannot announce
/**      itself on load;
/**    * the save/load list shows vanilla names;
/**    * the console diagnostics (modSaveNames_hello / _hud / _dump) still work.
/**  Use it if a game build refuses to compile an override, and report the exact
/**  compiler error.
/**
/**  Generated from the full file - edit that one and regenerate this copy.
/***********************************************************************/
// ------------------------------------------------------------------ knobs ----

// Show the engine's own name after your label, e.g.
// "Rodrigo boss fight - Gimme Danger". Set the return value to true to enable.
function ModSaveNames_ShowEngineName() : bool
{
	return false;
}

// The engine reports save file names in LOWER CASE (a file named "KamilTest"
// comes back as "kamiltest"), so a custom name would show up all lower case.
// This knob puts the first letter of the label back in upper case. Turn it off
// to display exactly what the engine reports.
function ModSaveNames_SentenceCase() : bool
{
	return true;
}


// -------------------------------------------------------------- utilities ----

// "ManualSave_[Rodrigo boss fight]_4711_9f2a11" -> "Rodrigo boss fight"
// "ManualSave_8559a_7ea47000_515dab8"          -> ""   (engine name, no label)
// "kamil"                                      -> ""   (handled elsewhere)
function ModSaveNames_ExtractLabel(filename : string) : string
{
	var openMark  : string;
	var closeMark : string;
	var afterOpen : string;

	openMark  = "[";
	closeMark = "]";

	if ( !StrContains(filename, openMark) )
	{
		return "";
	}

	afterOpen = StrAfterFirst(filename, openMark);

	if ( !StrContains(afterOpen, closeMark) )
	{
		return "";
	}

	return StrBeforeFirst(afterOpen, closeMark);
}


// Save labels live inside file names, so the tools replace the characters Windows
// refuses (<>:"/\|?*) with a SPACE. A label therefore arrives with runs of spaces
// where that punctuation was; collapse them for the player. Dashes are left alone.
function ModSaveNames_Tidy(label : string) : string
{
	var previous : string;
	var i : int;

	previous = "";

	for (i = 0; i < 10; i += 1)
	{
		if (StrLen(label) != StrLen(previous))
		{
			previous = label;
			label = StrReplaceAll(label, "  ", " ");
		}
	}

	return label;
}


// The game names its own saves "<type>_<id>_<id>_<id>" - and it reports them in
// LOWER CASE ("manualsave_53db9_7ea47000_5a6e4ad"), even though the files on disk
// are "ManualSave_...". The comparison must therefore be case-insensitive: a
// case-sensitive version of this function made every vanilla save look
// hand-renamed and the menu printed raw file names.
// Measured types on 5.0: autosave / quicksave / manualsave / checkpoint.
//
// Anything else in the folder was renamed by a human - which is how a
// hand-renamed save ends up in the menu at all: measured on 5.0 with a file
// renamed to kamil.sav, the engine reported
//     name = "kamil - wtorek, 29 września 2026 20:38:57"
// i.e. it could not classify the file, so it fell back to <file name> + date.
// We treat such a file as "the whole name is the custom name".
function ModSaveNames_IsEngineName(filename : string) : bool
{
	var lower : string;

	lower = StrLower(filename);

	if (StrBeginsWith(lower, "manualsave"))			{ return true; }
	if (StrBeginsWith(lower, "autosave"))			{ return true; }
	if (StrBeginsWith(lower, "quicksave"))			{ return true; }
	if (StrBeginsWith(lower, "checkpoint"))			{ return true; }
	if (StrBeginsWith(lower, "forcedcheckpoint"))	{ return true; }
	if (StrBeginsWith(lower, "pointofnoreturn"))	{ return true; }
	if (StrBeginsWith(lower, "importsave"))			{ return true; }
	if (StrBeginsWith(lower, "save"))				{ return true; }

	return false;
}


// First letter up. Only touches an ASCII letter on purpose: slicing a multibyte
// Polish character by one byte would corrupt it, so those are left alone.
function ModSaveNames_UpperFirstLetter(text : string) : string
{
	var first : string;

	if (StrLen(text) == 0)
	{
		return text;
	}

	first = StrLeft(text, 1);

	if ( !StrContains("abcdefghijklmnopqrstuvwxyz", first) )
	{
		return text;
	}

	return StrUpper(first) + StrMid(text, 1);
}


// Sentence-case the label if the knob says so (see ModSaveNames_SentenceCase).
function ModSaveNames_ApplyStyle(label : string) : string
{
	if ( !ModSaveNames_SentenceCase() || StrLen(label) == 0 )
	{
		return label;
	}

	return ModSaveNames_UpperFirstLetter(label);
}


// The custom name carried by a save file, or "" when the file is the game's own.
//   1. a [label] in the name wins (the renamer's "tag" mode)
//   2. a name the engine does not recognise is taken as the custom name
function ModSaveNames_CustomNameFromFilename(filename : string) : string
{
	var label : string;

	label = ModSaveNames_ExtractLabel(filename);

	if (StrLen(label) > 0)
	{
		return ModSaveNames_ApplyStyle(ModSaveNames_Tidy(label));
	}

	if (StrLen(filename) > 0 && !ModSaveNames_IsEngineName(filename))
	{
		return ModSaveNames_ApplyStyle(filename);
	}

	return "";
}


// The one place where the displayed name is decided.
function ModSaveNames_MakeLabel(save : SSavegameInfo, engineName : string) : string
{
	var label : string;

	label = ModSaveNames_CustomNameFromFilename(save.filename);

	if (StrLen(label) == 0)
	{
		return engineName;
	}

	if (ModSaveNames_ShowEngineName())
	{
		return label + " - " + engineName;
	}

	return label;
}


// ------------------------------------------------------------------- hook ----

// Replaces the global function that builds every row of the load/save list.
// @replaceMethod with NO parentheses = replace a global function (REDkit wiki,
// "WS: Script Compilation Errors overrides"). Adding empty parentheses is a
// syntax error - the parser expects a class name inside them.
function IngameMenu_PopulateSaveDataForSlotType(flashStorageUtility : CScriptedFlashValueStorage, saveType:int, parentObject:CScriptedFlashArray, allowEmptySlot:bool) : void
{
	var currentData		: CScriptedFlashObject;
	var numSaveSlots	: int;
	var saveDisplayName	: string;
	var menuLabel		: string;
	var currentSave		: SSavegameInfo;
	var saveGames		: array< SSavegameInfo >;
	var numSavesAdded	: int;
	var i				: int;

	theGame.ListSavedGames( saveGames, saveType );

	if (saveType == -1)
	{
		numSaveSlots = 0;
	}
	else
	{
		numSaveSlots = theGame.GetNumSaveSlots(saveType);
	}

	// --- vanilla: count the slots in use, so the empty slot row can appear ---
	numSavesAdded = 0;
	for (i = 0; i < saveGames.Size(); i += 1)
	{
		currentSave = saveGames[i];

		if (saveType == currentSave.slotType || saveType == -1)
		{
			numSavesAdded += 1;
		}
	}

	if (allowEmptySlot && (numSaveSlots == -1 || numSavesAdded < numSaveSlots) )
	{
		// --- vanilla empty-slot row, untouched ---
		currentData = flashStorageUtility.CreateTempFlashObject();

		currentData.SetMemberFlashString("id", "EMPTY");
		currentData.SetMemberFlashString("label", GetPlatformLocString("Empty_Save_Slot"));
		currentData.SetMemberFlashString("filename", "");
		currentData.SetMemberFlashInt("tag", -1);
		currentData.SetMemberFlashUInt("saveType", saveType);

		if (theGame.IsGalaxyUserSignedIn() && theGame.GetInGameConfigWrapper().GetVarValue('Gameplay', 'CrossProgression'))
		{
			currentData.SetMemberFlashUInt("cloudStatus", SCO_Uploading);
		}
		else
		{
			currentData.SetMemberFlashUInt("cloudStatus", SCO_Local);
		}

		parentObject.PushBackFlashObject(currentData);
	}

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		currentSave = saveGames[i];

		if (saveType == currentSave.slotType || saveType == -1)
		{
			currentData = flashStorageUtility.CreateTempFlashObject();

			saveDisplayName = theGame.GetDisplayNameForSavedGame(currentSave);

			// --- the mod: label from the file name, vanilla name otherwise ---
			menuLabel = ModSaveNames_MakeLabel(currentSave, saveDisplayName);

			currentData.SetMemberFlashString("id", menuLabel);
			currentData.SetMemberFlashString("label", menuLabel);
			currentData.SetMemberFlashString("filename", currentSave.filename);
			currentData.SetMemberFlashInt("tag", i);
			currentData.SetMemberFlashUInt("saveType", currentSave.slotType);
			currentData.SetMemberFlashUInt("cloudStatus", currentSave.comboStatus);

			parentObject.PushBackFlashObject(currentData);
		}
	}
}


// Same treatment for the "import save" screen (Witcher 2 imports). It only
// ever changes names that carry a [label], so it is inert for everything else.
// Delete this function if the 5.0 build of it differs too much to be worth it.
function IngameMenu_PopulateImportSaveData(flashStorageUtility : CScriptedFlashValueStorage, parentObject:CScriptedFlashArray) : void
{
	var saveGames		: array< SSavegameInfo >;
	var currentSave		: SSavegameInfo;
	var i				: int;
	var saveDisplayName	: string;
	var menuLabel		: string;
	var currentData		: CScriptedFlashObject;

	theGame.ListW2SavedGames( saveGames );

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		currentSave = saveGames[i];

		saveDisplayName = theGame.GetDisplayNameForSavedGame(currentSave);
		menuLabel       = ModSaveNames_MakeLabel(currentSave, saveDisplayName);

		currentData = flashStorageUtility.CreateTempFlashObject();

		currentData.SetMemberFlashString("id", menuLabel);
		currentData.SetMemberFlashString("label", menuLabel);
		currentData.SetMemberFlashString("filename", currentSave.filename);
		currentData.SetMemberFlashInt("tag", i);
		currentData.SetMemberFlashUInt("saveType", currentSave.slotType);
		currentData.SetMemberFlashUInt("cloudStatus", currentSave.comboStatus);

		parentObject.PushBackFlashObject(currentData);
	}
}


// ------------------------------------------------ whose save is this? --------
//
// The label lives IN the save, so it travels with the file: load a save and the
// game tells you whose it is. Nothing else in the mod is needed for that.
//
// WHERE IT IS STORED
// The game's fact database - the vanilla mechanism for script data that belongs
// to a save ("Facts are used to store data in saves", scripts/game/facts.ws). A
// fact holds one int, so a label travels packed four characters per fact as
// base-100 digits, with its length in a fact of its own. Facts are addressed by
// name and are written to disk when the game saves, which is why setSaveName
// reminds you to save.
//
// WHY NOT @addField(CR4Player) + "saved var" (the other way mods do this)?
// It persists just as well, but a field that has been written into a save may
// never be removed from the mod again: a save whose stored field no longer
// exists in the code fails to load. Facts carry no such coupling, so the mod can
// still be uninstalled.
//
// The alphabet is 92 characters (letters incl. Polish, digits, space, common
// punctuation) and stays below 100, which is what makes base-100 packing work.
// Anything outside it becomes 'A'. Labels are capped at 32 characters.

function ModSaveNames_Alphabet() : string
{
	return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_.:,!?()ąćęłńóśźżĄĆĘŁŃÓŚŹŻ";
}

// how many facts one label may use - 4 characters fit into each
function ModSaveNames_LabelSlots() : int
{
	return 8;
}

// base-100 digit weights: 1, 100, 10000, 1000000
function ModSaveNames_PackFactor(digit : int) : int
{
	if (digit == 0) { return 1; }
	if (digit == 1) { return 100; }
	if (digit == 2) { return 10000; }

	return 1000000;
}

function ModSaveNames_FactID(slot : int) : string
{
	return "modSaveNames_" + IntToString(slot);
}

// Put the label into the save (nothing reaches the disk until the game saves).
function ModSaveNames_StoreLabel(label : string)
{
	var alphabet : string;
	var length, slot, digit, code, value, index : int;
	var ch : string;

	alphabet = ModSaveNames_Alphabet();
	length   = StrLen(label);

	if (length > ModSaveNames_LabelSlots() * 4)
	{
		length = ModSaveNames_LabelSlots() * 4;
	}

	FactsSet("modSaveNames_len", length);

	for (slot = 0; slot < ModSaveNames_LabelSlots(); slot += 1)
	{
		value = 0;

		for (digit = 0; digit < 4; digit += 1)
		{
			index = slot * 4 + digit;

			if (index < length)
			{
				ch   = StrMid(label, index, 1);
				code = StrFindFirst(alphabet, ch);

				if (code < 0)
				{
					code = 0;
				}
			}
			else
			{
				code = 0;
			}

			value += code * ModSaveNames_PackFactor(digit);
		}

		FactsSet(ModSaveNames_FactID(slot), value);
	}
}

// Read the label back out of the save. "" when the save carries none.
function ModSaveNames_StoredLabel() : string
{
	var alphabet : string;
	var length, slot, digit, code, value, index : int;
	var label : string;

	alphabet = ModSaveNames_Alphabet();
	length   = FactsQueryLatestValue("modSaveNames_len");

	if (length <= 0)
	{
		return "";
	}

	if (length > ModSaveNames_LabelSlots() * 4)
	{
		length = ModSaveNames_LabelSlots() * 4;
	}

	label = "";

	for (slot = 0; slot < ModSaveNames_LabelSlots(); slot += 1)
	{
		value = FactsQueryLatestValue(ModSaveNames_FactID(slot));

		for (digit = 0; digit < 4; digit += 1)
		{
			index = slot * 4 + digit;
			code  = value - (value / 100) * 100;
			value = value / 100;

			if (index < length)
			{
				label = label + StrMid(alphabet, code, 1);
			}
		}
	}

	return label;
}

// The line the player reads when a save is loaded.
function ModSaveNames_AnnounceLabel()
{
	var label : string;

	if (thePlayer == null)
	{
		return;
	}

	label = ModSaveNames_StoredLabel();

	if (StrLen(label) > 0)
	{
		thePlayer.DisplayHudMessage("Save: " + label);
	}
	else
	{
		thePlayer.DisplayHudMessage("Unnamed save - name it with: setSaveName('Kamil')");
	}
}

// The player object is spawned every time a world is loaded, which is exactly the
// moment we want to answer "whose save did I just load?". Wrapping the event (not
// replacing anything) is the merge-free bootstrap other mods use.
function OnSpawned(spawnData : SEntitySpawnData)
{

	ModSaveNames_AnnounceLabel();
}


// ------------------------------------------------------------------ console ----
//
//   setSaveName('Kamil')   name the save you are playing; save the game to keep it
//   showSaveName()         what this save says right now
//   clearSaveName()        remove the name from this save

exec function setSaveName(name : string)
{
	if (thePlayer == null)
	{
		return;
	}

	ModSaveNames_StoreLabel(name);
	thePlayer.DisplayHudMessage("This save is now '" + name + "' - save the game to keep it");
}

exec function showSaveName()
{
	var label : string;

	if (thePlayer == null)
	{
		return;
	}

	label = ModSaveNames_StoredLabel();

	if (StrLen(label) > 0)
	{
		thePlayer.DisplayHudMessage("This save: " + label);
	}
	else
	{
		thePlayer.DisplayHudMessage("This save has no name - use setSaveName('Kamil')");
	}
}

exec function clearSaveName()
{
	if (thePlayer == null)
	{
		return;
	}

	ModSaveNames_StoreLabel("");
	thePlayer.DisplayHudMessage("Save name cleared");
}


// ------------------------------------------------------- in-game test tool ----

// Run from the debug console (~ with DBGConsoleOn=true, see the REDkit wiki).
// Two ways out, because the console does NOT echo log output:
//
//   modSaveNames_hello()   -> one HUD message: proves the mod is loaded
//   modSaveNames_hud()     -> the dump, printed ON SCREEN (no launch flags needed)
//   modSaveNames_dump()    -> the same data, written to the script log channel
//                             (needs the game started with -debugscripts, see
//                              docs/TEST-WITHOUT-REDKIT.md)
//
// Prints every save the game can see, the vanilla name and this mod's label.

function ModSaveNames_Version() : string
{
	return "0.2.0";
}

function ModSaveNames_Clip(text : string, maxLen : int) : string
{
	if (StrLen(text) <= maxLen)
	{
		return text;
	}

	return StrLeft(text, maxLen) + "...";
}

function ModSaveNames_Summary(save : SSavegameInfo) : string
{
	var engineName : string;

	engineName = theGame.GetDisplayNameForSavedGame(save);

	return "slot=" + IntToString(save.slotIndex)
		+ " type=" + IntToString(save.slotType)
		+ " file=" + save.filename
		+ " | engine='" + engineName + "'"
		+ " | shows='" + ModSaveNames_MakeLabel(save, engineName) + "'";
}

// One line on the HUD: proves the script is loaded and running.
exec function modSaveNames_hello()
{
	GetWitcherPlayer().DisplayHudMessage("modSaveNames " + ModSaveNames_Version() + ": loaded");
	LogChannel('modSaveNames', "hello - version " + ModSaveNames_Version());
}

// The dump on screen, in HUD messages (they queue up, a few seconds each).
exec function modSaveNames_hud()
{
	var saveGames : array< SSavegameInfo >;
	var i : int;

	theGame.ListSavedGames( saveGames, -1 );

	GetWitcherPlayer().DisplayHudMessage("modSaveNames " + ModSaveNames_Version() + ": " + IntToString(saveGames.Size()) + " save(s)");
	GetWitcherPlayer().DisplayHudMessage("this save's label: '" + ModSaveNames_StoredLabel() + "'");

	LogChannel('modSaveNames', "----- modSaveNames " + ModSaveNames_Version() + " - "
		+ IntToString(saveGames.Size()) + " save(s) -----");

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		GetWitcherPlayer().DisplayHudMessage("#" + IntToString(i) + " " + ModSaveNames_Clip(ModSaveNames_Summary(saveGames[i]), 140));
		LogChannel('modSaveNames', "[" + IntToString(i) + "] " + ModSaveNames_Summary(saveGames[i]));
	}
}

// Log-only version (scriptlog.txt). Kept separate so the on-screen one stays short.
exec function modSaveNames_dump()
{
	var saveGames : array< SSavegameInfo >;
	var engineName : string;
	var label : string;
	var i : int;

	theGame.ListSavedGames( saveGames, -1 );

	LogChannel('modSaveNames', "modSaveNames 0.2.0 - " + IntToString(saveGames.Size()) + " save(s) visible");

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		engineName = theGame.GetDisplayNameForSavedGame(saveGames[i]);
		label      = ModSaveNames_CustomNameFromFilename(saveGames[i].filename);

		LogChannel('modSaveNames', "[" + IntToString(i) + "] slot=" + IntToString(saveGames[i].slotIndex) + " type=" + IntToString(saveGames[i].slotType));
		LogChannel('modSaveNames', "      file  : " + saveGames[i].filename);
		LogChannel('modSaveNames', "      engine: " + engineName);
		LogChannel('modSaveNames', "      label : '" + label + "'  -> menu shows: '" + ModSaveNames_MakeLabel(saveGames[i], engineName) + "'");
	}
}