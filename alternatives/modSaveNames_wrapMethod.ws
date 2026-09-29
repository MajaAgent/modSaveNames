/***********************************************************************/
/**  modSaveNames - ALTERNATIVE implementation (wrap instead of replace)
/**
/**  Use this ONLY if the @replaceMethod version in
/**  ../content/scripts/local/modSaveNames.ws refuses to compile for a global
/**  function, or if 5.0's body differs so much that replacing it is risky.
/**
/**  Why it is safer: the vanilla function still runs and builds every row
/**  exactly as it does today; we only rewrite the "label" of rows whose file
/**  name carries a [label]. Nothing else about the list can drift.
/**
/**  Why it may not work: it needs to READ members of an already-built Flash row,
/**  i.e. a getter for a string member and indexed access to the row array.
/**  Those two names are NOT verified here (the game's scripts only ever write
/**  rows, never read them back). Before using this file, type
/**  "flash" in Script Studio's autocomplete on a CScriptedFlashObject /
/**  CScriptedFlashArray variable and use the real getter names it offers;
/**  the two calls to fix are marked with  >>> CHECK NAMES <<<.
/**
/**  Do not ship both files at once: two implementations of the same hook.
/***********************************************************************/


function ModSaveNames_AltExtractLabel(filename : string) : string
{
	var afterOpen : string;

	if ( !StrContains(filename, "[") )
	{
		return "";
	}

	afterOpen = StrAfterFirst(filename, "[");

	if ( !StrContains(afterOpen, "]") )
	{
		return "";
	}

	return StrBeforeFirst(afterOpen, "]");
}


function ModSaveNames_AltLabelFor(engineName : string, filename : string) : string
{
	var label : string;

	label = StrReplaceAll(ModSaveNames_AltExtractLabel(filename), "-", " ");

	if (StrLen(label) == 0)
	{
		return engineName;
	}

	return label;
}


/*
 * For a GLOBAL function the REDkit wiki only documents the bare form
 * (@replaceMethod ...). Bare @wrapMethod is the guess for the same case - if the
 * compiler rejects it, use the replaceMethod implementation instead.
 */
@wrapMethod
function IngameMenu_PopulateSaveDataForSlotType(flashStorageUtility : CScriptedFlashValueStorage, saveType:int, parentObject:CScriptedFlashArray, allowEmptySlot:bool) : void
{
	var row			: CScriptedFlashObject;
	var rowCount	: int;
	var i			: int;
	var filename	: string;

	// vanilla builds the whole list, including the empty-slot row and the
	// cross-progression bits - we do not touch any of that
	wrappedMethod(flashStorageUtility, saveType, parentObject, allowEmptySlot);

	rowCount = parentObject.Size();   // >>> CHECK NAMES <<< (indexed access on CScriptedFlashArray)

	for (i = 0; i < rowCount; i += 1)
	{
		row = parentObject.GetFlashObject(i);   // >>> CHECK NAMES <<<

		if (row == null)
		{
			continue;
		}

		filename = row.GetMemberFlashString("filename");   // >>> CHECK NAMES <<<

		if (StrLen(filename) == 0 || !StrContains(filename, "["))
		{
			continue;
		}

		row.SetMemberFlashString(
			"label",
			ModSaveNames_AltLabelFor(row.GetMemberFlashString("label"), filename)
		);
		row.SetMemberFlashString(
			"id",
			row.GetMemberFlashString("label")
		);
	}
}
