/***********************************************************************/
/**  modSaveNames 0.1.7
/**  Custom save names for The Witcher 3: Wild Hunt (5.0 / next-gen)
/**
/**  WHAT IT DOES
/**  The save/load menu shows the name the engine derives for a save. When the
/**  engine cannot derive one, it falls back to the save's file name - which is
/**  why a hand-renamed save already shows your text, but polluted with the
/**  type prefix, the marker and the engine ids:
/**      ManualSave_[Rodrigo boss fight]_4711_9f2a11
/**  This mod keeps the file naming scheme (the renamer's "tag" mode) and shows
/**  only the label part:
/**      Rodrigo boss fight
/**  Saves without a label show the vanilla name, exactly as before.
/**
/**  COMPANION TOOL
/**  w3save_renamer.py (in the research folder) writes the [label] into the file
/**  name and re-applies it after every overwrite (label memory). The mod cannot
/**  create or persist a name: scripts have no file access. Renamer = truth,
/**  mod = display (and it makes the name readable without the noise).
/**
/**  MEASURED ON 5.0 (in-game, modSaveNames_hud(); 14 saves, one renamed by hand)
/**    file      = "manualsave_53db9_7ea47000_5a6e4ad"   engine names are LOWER CASE
/**    engine    = "Bestia z Białego Sadu - wtorek, 29 września 2026 22:51:58"
/**    renamed   = "kamil"  ->  engine "kamil - wtorek, ..." (fallback: name+date)
/**    slotType  = 1 autosave | 2 quicksave | 3 manual | 5 checkpoint
/**  Conclusions that shape everything:
/**    * a normal save's name is <quest name> + date; the engine loses the quest
/**      lookup for a file it cannot classify and falls back to the file name -
/**      so the file name is the only per-save text storage we have;
/**    * a hand-renamed save keeps its type (kamil still reports 3 = manual), so
/**      it stays in the right tab;
/**    * an overwrite is a NEW file under the game's own name, so the custom text
/**      is gone until the renamer re-applies it.
/**
/**  HOW IT HOOKS
/**  The save list rows are assembled in script, in
/**  IngameMenu_PopulateSaveDataForSlotType() (vanilla file
/**  game/gui/main_menu/ingamemenu/igmUtilities.ws): it walks
/**  theGame.ListSavedGames(), asks the native
/**  theGame.GetDisplayNameForSavedGame(save) for the text and writes the Flash
/**  row members "id" / "label" / "filename". "label" is what the player reads.
/**  GetDisplayNameForSavedGame is `import final` (native, not replaceable), the
/**  function above it is plain script - so we replace that one.
/**
/**  STATUS - read this before compiling
/**  The body below is the next-gen 4.0 vanilla function plus the label logic.
/**  5.0 is what you actually run: in REDkit's Script Studio, check out
/**  game/gui/main_menu/ingamemenu/igmUtilities.ws (5.0) and diff it against
/**  reference/next-gen-4.0/igmUtilities.ws; keep every 5.0 line that differs
/**  and change only the label computation. If 5.0 added a row member, this body
/**  must set it too or the menu will misbehave.
/**
/**  API used (all verified against the engine's own script API):
/**    StrContains / StrAfterFirst / StrBeforeFirst / StrReplaceAll / StrLen  (core/string.ws)
/**    LogChannel(channel : name, text : string)                             (core/misc.ws)
/**  Safety: nothing here touches save files or gameplay state; worst case the
/**  save list looks wrong.
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
@replaceMethod
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
@replaceMethod
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
	return "0.1.7";
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

	GetWitcherPlayer().DisplayHudMessage("modSaveNames: " + IntToString(saveGames.Size()) + " save(s)");

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

	LogChannel('modSaveNames', "modSaveNames 0.1.7 - " + IntToString(saveGames.Size()) + " save(s) visible");

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
