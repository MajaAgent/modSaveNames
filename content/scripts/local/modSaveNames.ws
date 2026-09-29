/***********************************************************************/
/**  modSaveNames 0.1.0
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


// -------------------------------------------------------------- utilities ----

// "ManualSave_[Rodrigo boss fight]_4711_9f2a11" -> "Rodrigo boss fight"
// "ManualSave_8559a_7ea47000_515dab8"          -> ""   (no label)
// "kamil"                                      -> ""   (no label)
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


// Labels live in file names, so characters Windows refuses were written as "-";
// put the spaces back for the player.
function ModSaveNames_Prettify(label : string) : string
{
	return StrReplaceAll(label, "-", " ");
}


// The one place where the displayed name is decided.
function ModSaveNames_MakeLabel(save : SSavegameInfo, engineName : string) : string
{
	var label : string;

	label = ModSaveNames_Prettify(ModSaveNames_ExtractLabel(save.filename));

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

// Run from the debug console (~ with DBGConsoleOn=true, see the REDkit wiki):
//     modSaveNames_dump()
// Prints every save the game can see, its vanilla name and the label this mod
// would show. This is how you verify the hook without hunting through the menu -
// and how you tell me what the engine reports for a renamed save.
exec function modSaveNames_dump()
{
	var saveGames : array< SSavegameInfo >;
	var engineName : string;
	var label : string;
	var i : int;

	theGame.ListSavedGames( saveGames, -1 );

	LogChannel('modSaveNames', "modSaveNames 0.1.0 - " + IntToString(saveGames.Size()) + " save(s) visible");

	for (i = 0; i < saveGames.Size(); i += 1)
	{
		engineName = theGame.GetDisplayNameForSavedGame(saveGames[i]);
		label      = ModSaveNames_Prettify(ModSaveNames_ExtractLabel(saveGames[i].filename));

		LogChannel('modSaveNames', "[" + IntToString(i) + "] slotType=" + IntToString(saveGames[i].slotType) + " slotIndex=" + IntToString(saveGames[i].slotIndex));
		LogChannel('modSaveNames', "      file  : " + saveGames[i].filename);
		LogChannel('modSaveNames', "      engine: " + engineName);
		LogChannel('modSaveNames', "      label : '" + label + "'  -> menu shows: '" + ModSaveNames_MakeLabel(saveGames[i], engineName) + "'");
	}
}
