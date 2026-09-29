#!/usr/bin/env python3
"""w3save_renamer.py - give The Witcher 3 saves custom names (file-level tool).

Why a file-level tool: The Witcher 3 keeps no "save name" field you can set from
scripts. The save list handed to the game UI is a list of files
(SSavegameInfo { filename, slotType, slotIndex, comboStatus }), and the Load menu
ends up showing the save's on-disk name. So renaming the file (or the folder, on
old-gen saves) renames the save as the game displays it.

The overwrite problem
---------------------
Measured in game on 5.0: overwriting a save slot makes the game write a NEW file
under a name of its own making (ManualSave_53db9_7ea47000_5c98d32.sav) and delete
the old one - no orphan files are left behind - and the custom text in the old file
name is gone. So the reliable path is to give the label again after an overwrite
(one command), or to run `watch`, which reports the new save as it appears.

This tool also keeps a small label memory (~/.w3save_renamer/state.json, or
--state): every (engine name -> label) pair it has written out, keyed on the
engine's own name. That lets `watch` re-apply a label automatically *if* the game
reuses its name for a slot. Worth trying, but not observed: every save file we have
seen so far carried a fresh id, so treat the memory as a convenience, not a
guarantee. `list` shows remembered labels either way.

Save layout (measured on a real 5.0 save)
-----------------------------------------
5.0:      Documents/The Witcher 3/gamesaves/<name>.sav + <name>.json + <name>.png
          (the .json holds saveMetadata: buildID, gameVersion 29, saveVersion 66,
          platform, modsMetadata - it does NOT hold the displayed name)
old-gen:  Documents/The Witcher 3/gamesaves/<Name>-<id>/ (metadata.<id>.json + data)
All three 5.0 files share the base name and this tool renames them as one family:
the game looks the thumbnail up by base name (rename it out and the save still
loads, only the thumbnail is gone), so nothing may be left behind under the old
name.

What the menu displays (verified in game on 5.0)
------------------------------------------------
* a save the game named itself shows "<quest name> - <date>", e.g.
  "Bestia z Białego Sadu - wtorek, 29 września 2026 22:51:58"
* the engine reports file names in LOWER CASE, and the date it shows is the FILE's
  timestamp: a byte-identical copy of a save displayed the copy's time
* ANY rename makes the engine lose that lookup and fall back to the file name:
  renaming to kamil.sav showed "kamil - <date>", and the tag form
  ManualSave_[Test-etykiety]_53db9_... showed the whole file name with the date -
  yet the save kept its type (3 = manual) and its slot, so it still loads and stays
  in the right tab
* all three files move together; the game cleans the old ones up on overwrite
* that raw fallback is ugly, which is what the companion mod modSaveNames is for:
  it reads the [label] out of the file name and shows only that in the menu row

This tool never edits the inside of a save file. It only renames files/folders
in the gamesaves directory, after optional backup. Back up anyway.

Commands
--------
  list                        show the saves found in the save folder
  rename <save> <label>       rename a save to a custom label
  watch                       poll the folder; re-apply remembered labels and
                              report / optionally label genuinely new saves

Rename modes (--mode)
---------------------
  tag (default)     ManualSave_4711_9f2a.sav -> ManualSave_[My Label]_4711_9f2a.sav
                    the convention the REDkit companion mod (modSaveNames) reads;
                    the engine's slot id stays untouched - least invasive
  insert            ManualSave_4711_9f2a.sav -> ManualSave_My Label_4711_9f2a.sav
                    plain label, no markers (use when you only want file order)
  keep              ManualSave_4711_9f2a.sav -> ManualSave_My Label.sav
                    type prefix + label, engine id dropped (confirmed in game:
                    the engine still lists such a save and shows the file name)
  free              ManualSave_4711_9f2a.sav -> My Label.sav
                    no type prefix; the game may stop treating it as a save type
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

SAVE_TYPES = ("AutoSave", "CheckPoint", "ManualSave", "QuickSave", "PointOfInterest")
ILLEGAL = '<>:"/\\|?*'
MAX_LABEL = 80
STEAM_APPID = "292030"  # The Witcher 3: Wild Hunt
STATE_VERSION = 1
LABEL_MARK = re.compile(r"\[([^\]]*)\]")


# ---------------------------------------------------------------- helpers ----

def sanitize(label: str, max_len: int = MAX_LABEL) -> str:
    """Make a label safe as a Windows file name (this is where the game lives).

    Illegal characters become a SPACE, not a dash: the companion mod collapses runs
    of spaces, and a dash the player typed should stay a dash.
    """
    out = []
    for ch in label.strip():
        if ch in ILLEGAL or ord(ch) < 32 or ord(ch) == 127:
            out.append(" ")
        else:
            out.append(ch)
    text = re.sub(r"\s+", " ", "".join(out)).strip(" .")
    return text[:max_len]


def label_in_name(stem: str) -> str:
    """The [label] part of a file name, or '' if it carries none."""
    m = LABEL_MARK.search(stem)
    return m.group(1).strip() if m else ""


def engine_base(stem: str) -> str:
    """The engine's own name: the file name with any [label] markers removed.

    This must be stable across renames, because it is the key the label memory
    uses to recognise the same save after the game has overwritten it.
    """
    stripped = LABEL_MARK.sub("", stem)
    stripped = re.sub(r"[-_]{2,}", lambda m: m.group(0)[0], stripped)
    return stripped.strip("-_ ")


def default_save_dir() -> Path | None:
    """Best-effort guess of the gamesaves folder (plain Windows, Wine/Proton)."""
    cands: list[Path] = []
    env = os.environ.get("W3_SAVES")
    if env:
        cands.append(Path(env))
    home = Path.home()
    docs = ["Documents", "Dokumenty", "OneDrive/Documents"]
    for d in docs:
        cands.append(home / d / "The Witcher 3" / "gamesaves")
    for steam in (
        home / ".steam/steam",
        home / ".local/share/Steam",
        home / ".var/app/com.valvesoftware.Steam/data/Steam",
    ):
        for user in ("steamuser", "steam"):
            cands.append(
                steam / "steamapps/compatdata" / STEAM_APPID / "pfx/drive_c/users"
                / user / "Documents/The Witcher 3/gamesaves"
            )
    for c in cands:
        if c.is_dir():
            return c
    return None


def split_name(name: str) -> tuple[str, str, str]:
    """Split a save base name into (prefix, separator, rest)."""
    for sep in ("_", "-"):
        if sep in name:
            prefix, _, rest = name.partition(sep)
            if prefix in SAVE_TYPES:
                return prefix, sep, rest
    return "", "", name


@dataclass
class Save:
    path: Path
    is_dir: bool
    prefix: str = ""
    sep: str = ""
    rest: str = ""

    @property
    def base(self) -> str:
        return self.path.name

    @property
    def key(self) -> str:
        """Stable identity used to spot new saves: name for folders, stem for .sav."""
        return self.path.name if self.is_dir else self.path.stem

    @property
    def twin(self) -> Path:
        """The .png thumbnail, found by base name (5.0). Purely cosmetic: a save
        whose preview is renamed-out still loads, it just shows no thumbnail."""
        return self.path.with_suffix(".png")

    def mtime(self) -> float:
        return self.path.stat().st_mtime


def scan(save_dir: Path) -> list[Save]:
    saves: list[Save] = []
    for entry in sorted(save_dir.iterdir(), key=lambda p: p.name.lower()):
        if entry.is_dir() and any(entry.glob("metadata*.json")):
            prefix, sep, rest = split_name(entry.name)
            saves.append(Save(entry, True, prefix, sep, rest))
        elif entry.is_file() and entry.suffix.lower() == ".sav":
            prefix, sep, rest = split_name(entry.stem)
            saves.append(Save(entry, False, prefix, sep, rest))
    return saves


def find_save(save_dir: Path, needle: str) -> list[Save]:
    n = needle.lower()
    hits = [
        s for s in scan(save_dir)
        if s.base.lower() == n or s.path.name.lower() == n or s.base.lower().startswith(n)
    ]
    return hits


def target_base(save: Save, label: str, mode: str) -> str:
    if mode == "free" or not save.prefix:
        return label
    if mode == "keep":
        return f"{save.prefix}{save.sep}{label}"
    if mode == "tag":
        label = f"[{label}]"
    return f"{save.prefix}{save.sep}{label}{save.sep}{save.rest}" if save.rest else f"{save.prefix}{save.sep}{label}"


def backup_save(save: Save, backup_dir: Path) -> None:
    backup_dir.mkdir(parents=True, exist_ok=True)
    if save.is_dir:
        shutil.copytree(save.path, backup_dir / save.base, dirs_exist_ok=True)
    else:
        for sib in siblings(save):
            shutil.copy2(sib, backup_dir / sib.name)


def siblings(save: Save) -> list[Path]:
    """Every file belonging to one save, all sharing the base name.

    5.0 keeps `<name>.sav` + `<name>.json` (saveMetadata: buildID, saveVersion,
    platform, modsMetadata) + `<name>.png` (thumbnail, looked up by base name);
    old-gen keeps a folder. Renaming only the .sav leaves the two sidecars behind
    under the old name, so the whole family has to move together.
    """
    return sorted(
        p for p in save.path.parent.iterdir()
        if p.is_file() and p.stem == save.path.stem
    )


def rename_save(save: Save, label: str, mode: str, dry_run: bool, backup: bool) -> list[tuple[str, str]]:
    """Rename a save. Returns the list of (old, new) names it wants to apply."""
    new = target_base(save, label, mode)
    if new == save.base:
        raise SystemExit(f"nothing to do: already named {new!r}")
    changes: list[tuple[str, str]] = []
    if save.is_dir:
        changes.append((save.base, new))
    else:
        changes = [(p.name, new + p.suffix) for p in siblings(save)]
        if not changes:
            raise SystemExit(f"{save.base}: no files found to rename")
        missing = [s for s in (".json", ".png") if not save.path.with_suffix(s).exists()]
        if missing:
            note = ", ".join(
                f"{s} ({'metadata' if s == '.json' else 'thumbnail only - the save still loads without it'})"
                for s in missing
            )
            print(f"  ! note: {save.base} has no {note}")
    for _, n in changes:
        if (save.path.parent / n).exists():
            raise SystemExit(f"refusing to overwrite existing {n!r} in {save.path.parent}")
    if backup and not dry_run:
        backup_save(save, save.path.parent / "_backup")
    for old, n in changes:
        src = save.path.parent / old
        if dry_run:
            print(f"  [dry-run] {old}  ->  {n}")
        else:
            src.rename(save.path.parent / n)
            print(f"  {old}  ->  {n}")
    return changes


# ----------------------------------------------------------- label memory ----

def default_state_path() -> Path:
    env = os.environ.get("W3_SAVES_STATE")
    if env:
        return Path(env)
    return Path.home() / ".w3save_renamer" / "state.json"


def load_state(path: Path) -> dict:
    """{'labels': {engine_name: label}} - survives overwrites of the save."""
    if not path.exists():
        return {"version": STATE_VERSION, "labels": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"  ! label memory unreadable ({exc}) - starting empty")
        return {"version": STATE_VERSION, "labels": {}}
    data.setdefault("version", STATE_VERSION)
    data.setdefault("labels", {})
    return data


def memory_get(labels: dict, engine_name: str) -> tuple[str, str] | None:
    """(label, mode) remembered for an engine name; tolerates the old string form."""
    entry = labels.get(engine_name)
    if entry is None:
        return None
    if isinstance(entry, dict):
        return str(entry.get("label", "")), str(entry.get("mode", "tag"))
    return str(entry), "tag"


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True), encoding="utf-8")


def remember(state: dict, new_stem: str, label: str) -> None:
    state["labels"][engine_base(new_stem)] = label


# --------------------------------------------------------------- commands ----

def cmd_list(args: argparse.Namespace) -> int:
    save_dir = Path(args.dir)
    saves = scan(save_dir)
    if not saves:
        print(f"no saves found in {save_dir}")
        return 1
    labels = load_state(args.state)["labels"]
    print(f"{len(saves)} save(s) in {save_dir}")
    for s in saves:
        kind = "folder" if s.is_dir else "file  "
        when = datetime.fromtimestamp(s.mtime()).strftime("%Y-%m-%d %H:%M")
        if s.is_dir:
            extra = ""
        else:
            side = " ".join(p.suffix for p in siblings(s))
            extra = f"  [{side}]"
            if not s.path.with_suffix(".json").exists():
                extra += "  [no .json metadata]"
        shown = label_in_name(s.key)
        memo = memory_get(labels, engine_base(s.key))
        if shown:
            memory = f"  (label: {shown})"
        elif memo:
            memory = f"  (remembered label: {memo[0]} - run 'watch' to re-apply it after an overwrite)"
        else:
            memory = ""
        print(f"  {kind}  {when}  {s.base}{extra}{memory}")
    return 0


def cmd_rename(args: argparse.Namespace) -> int:
    save_dir = Path(args.dir)
    hits = find_save(save_dir, args.save)
    if not hits:
        print(f"no save matching {args.save!r} in {save_dir}")
        return 1
    if len(hits) > 1 and not args.all:
        print(f"{len(hits)} saves match {args.save!r} - be more specific or use --all:")
        for h in hits:
            print(f"  {h.base}")
        return 1
    label = sanitize(args.label)
    if not label:
        print("label is empty after sanitising")
        return 1
    if label != args.label.strip():
        print(f"label sanitised: {args.label!r} -> {label!r}")
    state = load_state(args.state) if args.memory else {"labels": {}}
    stored = 0
    for save in hits:
        print(f"{save.base}  (mode={args.mode})")
        try:
            changes = rename_save(save, label, args.mode, args.dry_run, args.backup)
        except SystemExit as exc:
            print(f"  ! skipped: {exc}")
            continue
        if args.memory and not args.dry_run:
            # Key on the ENGINE name (the name the game writes back after an
            # overwrite), so re-applying works in every mode: the label itself may
            # be the whole file name (keep/free) or sit between [] markers (tag).
            state["labels"][engine_base(save.key)] = {"label": label, "mode": args.mode}
            stored += 1
    if stored and not args.dry_run:
        save_state(args.state, state)
        print(f"label memory: {stored} save(s) remembered in {args.state}")
    if args.backup and not args.dry_run:
        print(f"backup in {save_dir / '_backup'}")
    print("done - check the Load game menu (and keep a copy of your saves)")
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    save_dir = Path(args.dir)
    present = {s.key for s in scan(save_dir)}
    labels = load_state(args.state)["labels"] if args.memory else {}
    print(f"watching {save_dir} (interval {args.interval}s, {len(present)} save(s) already there)")
    print(f"label memory: {len(labels)} entr{'y' if len(labels) == 1 else 'ies'} in {args.state}"
          if args.memory else "label memory: off")
    print("press Ctrl+C to stop")
    while True:
        time.sleep(args.interval)
        saves = scan(save_dir)
        current = {s.key for s in saves}
        fresh = [s for s in saves if s.key in current - present]
        for save in fresh:
            stamp = datetime.now().strftime("%H:%M:%S")
            memo = memory_get(labels, engine_base(save.key)) if args.memory else None
            if memo and save.key != memo[0] and label_in_name(save.key) != memo[0]:
                print(f"[{stamp}] {save.base}: known save (engine name) -> re-applying label "
                      f"{memo[0]!r} in mode {memo[1]} - this is what the game does on overwrite")
                action = ("reapply", memo[0], memo[1])
            elif args.label_template:
                label = sanitize(
                    args.label_template.format(
                        date=datetime.now().strftime("%Y-%m-%d"),
                        time=datetime.now().strftime("%H%M%S"),
                        orig=save.base,
                    )
                )
                print(f"[{stamp}] new save {save.base} -> {label}")
                action = ("label", label, args.mode)
            else:
                hint = ""
                if labels:
                    known = sorted({(memory_get(labels, k) or ("", ""))[0] for k in labels} - {""})
                    hint = "  (known labels: " + ", ".join(known[:4]) + ")"
                print(f"[{stamp}] new save: {save.base}  (rename with: rename {save.base!r} <label>){hint}")
                continue
            try:
                changes = rename_save(save, action[1], action[2], args.dry_run, args.backup)
            except SystemExit as exc:
                print(f"  ! skipped: {exc}")
            else:
                if args.memory and not args.dry_run:
                    labels[engine_base(save.key)] = {"label": action[1], "mode": action[2]}
                    save_state(args.state, {"version": STATE_VERSION, "labels": labels})
        # recompute what is on disk now, so a name the engine reverts to later
        # (or one of our own renamed files) is not mistaken for a new save
        present = {s.key for s in scan(save_dir)}
        if args.once:
            return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Custom names for The Witcher 3 saves (renames gamesaves files).")
    p.add_argument("--dir", help="gamesaves folder (default: auto-detect)")
    p.add_argument("--dry-run", action="store_true", help="show what would happen")
    p.add_argument("--backup", action="store_true", help="copy originals to <gamesaves>/_backup first")
    p.add_argument("--state", help="label-memory file (default: ~/.w3save_renamer/state.json)")
    p.add_argument("--no-memory", dest="memory", action="store_false", help="do not use the label memory")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="list saves")

    r = sub.add_parser("rename", help="rename a save")
    r.add_argument("save", help="current save name (prefix is enough if unique)")
    r.add_argument("label", help="custom label")
    r.add_argument("--mode", choices=("tag", "insert", "keep", "free"), default="tag")
    r.add_argument("--all", action="store_true", help="rename every match")

    w = sub.add_parser("watch", help="poll for new saves / re-apply remembered labels")
    w.add_argument("--interval", type=float, default=5.0)
    w.add_argument("--once", action="store_true", help="single scan then exit (testing)")
    w.add_argument("--label-template", help="auto-label new saves, e.g. 'Session-{date}-{time}'")
    w.add_argument("--mode", choices=("tag", "insert", "keep", "free"), default="tag")

    args = p.parse_args(argv)
    if not args.dir:
        found = default_save_dir()
        if not found:
            print("could not find the save folder - pass --dir (or set W3_SAVES)")
            return 2
        args.dir = str(found)
        print(f"save folder: {args.dir}")
    if not Path(args.dir).is_dir():
        print(f"{args.dir} is not a directory")
        return 2
    if not args.state:
        args.state = default_state_path()
    else:
        args.state = Path(args.state)
    return {"list": cmd_list, "rename": cmd_rename, "watch": cmd_watch}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
