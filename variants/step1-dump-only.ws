/***********************************************************************/
/**  modSaveNames - STEP 1 ONLY: the console diagnostic, no hook.
/**
/**  Use this file if the full mod refuses to compile: drop it in as
/**  content/scripts/local/modSaveNames.ws *instead* of the full file. It has no
/**  @replaceMethod at all, so it cannot fail on an override - it only adds the
/**  console command modSaveNames_dump(), which prints for every save:
/**      file:   the file name on disk (where a custom label can live)
/**      engine: what the game's own GetDisplayNameForSavedGame() returns
/**      label:  what the full mod would display
/**  That output alone tells us whether the API this mod needs exists in your
/**  game version, and how the menu name is built.
/**
/**  Generated from content/scripts/local/modSaveNames.ws - edit the full file and
/**  regenerate rather than editing this copy.
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
	return "0.1.2";
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

	return "slotType=" + IntToString(save.slotType)
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
