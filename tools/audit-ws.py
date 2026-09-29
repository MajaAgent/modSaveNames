#!/usr/bin/env python3
"""audit-ws.py - compile-risk check for WitcherScript, using the game's own scripts.

The engine's compiler stops at the first syntax error per file and cannot be run
outside the game, so the traps that are easy to hit are checked here instead:

  1. identifiers that are engine TYPE names - `name` for example is a type
     (`exec function acticon( contentToActivate : name )` in scripts/engine/game.ws),
     so `function f(name : string)` is a *syntax error*: the lexer returns
     TOKEN_TYPE_NAME and the parser will not take it as a parameter name;
  2. file-scope `var` - WitcherScript has no globals; `var` is only legal inside a
     function, class, struct, enum or state;
  3. calls to functions that appear nowhere in the game's scripts (typo);
  4. bracket balance (counted with string literals kept - braces do appear in text).

Comments and literals are masked, not deleted, so every reported line number is the
real one. The corpus (the game's `scripts` folder, as UTF-8) is optional: without it
check 3 is skipped and check 1 falls back to the built-in type list.

usage: audit-ws.py <mod .ws files...> [--corpus /path/to/game/scripts]
"""
import re
import sys
from pathlib import Path

# Types the engine provides. Anything here is a syntax error as an identifier.
BUILTIN_TYPES = {
    "void", "bool", "int", "float", "string", "name", "vector", "array", "handle",
    "localizedString", "CName", "EntityID", "TDateTime", "TTimeSpan", "matrix",
    "color", "actionPoint", "CScriptedFlashObject", "EntityHandle",
}

# Reserved words of the WitcherScript lexer. A word from this list cannot name a
# variable, parameter, field, function or class - the compiler answers with
# "unexpected TOKEN_<something>, expecting TOKEN_IDENT" and names the word.
# Source: the keyword table of the WitcherScript parser/LSP crate
# github.com/webspam/witcherscript-language (`classify_anonymous_keyword`),
# plus the control-flow words from the same grammar. Cross-checked against the
# engine's own messages: `name` gives TOKEN_TYPE_NAME, `entry` gives TOKEN_ENTRY.
RESERVED = {
    "class", "struct", "enum", "state", "statemachine", "function", "event", "extends",
    "var", "autobind", "defaults", "hint", "abstract", "latent", "import", "const",
    "final", "editable", "saved", "optional", "out", "inlined", "private", "protected",
    "public", "cleanup", "entry", "exec", "quest", "reward", "storyscene", "timer",
    "single", "if", "else", "for", "while", "do", "switch", "case", "default", "break",
    "continue", "return", "true", "false", "new", "delete", "this", "super", "and",
    "or", "not", "in",
}

# Words the parser knows; never identifiers we control, and not "unknown calls".
KEYWORDS = {
    "var", "function", "exec", "import", "final", "latent", "optional", "out", "in",
    "private", "protected", "public", "const", "new", "this", "super", "parent",
    "if", "else", "for", "while", "do", "switch", "case", "default", "break",
    "continue", "return", "true", "false", "null", "class", "struct", "enum",
    "state", "autobind", "event", "timer", "hint", "editable", "tooltip", "range",
    "saved", "inline", "abstract", "native", "static", "wrapped", "editoronly",
}

# Names the engine and the mod loader provide. They are NOT declared in the game's
# .ws files, so a scan of the corpus cannot find them - and a word that is neither
# here, nor in the corpus, nor declared in the mod is how `null` (the literal is
# `NULL`) or a typo gets caught.
ENGINE_GLOBALS = {
    "theGame", "thePlayer", "theInput", "theSound", "theCamera", "theUI", "theHud",
    "theWeather", "theTimer", "theDebug", "theToast", "theSoundSystem", "NULL",
    "wrapMethod", "wrappedMethod", "replaceMethod", "addMethod", "addField",
    "removeMethod", "addStat", "addEffect", "addBuff", "addAbility",
}

# Part of the modding API, not in the game's own scripts.
MODDING_API = {"wrapMethod", "wrappedMethod", "addStat", "addEffect"}


def mask(text: str, keep_strings: bool = False) -> str:
    """Comments (and optionally string literals) blanked out, length and newlines kept.

    A character scanner, not a regex: an apostrophe inside a "..." string - legal, and
    the game itself writes them (`npc + "'s dust attack"`) - defeats any pattern that
    does not track the state, and a mis-masked file reports wrong lines and phantom
    unknown names.
    """
    out: list[str] = []
    i, n = 0, len(text)
    state = "code"
    while i < n:
        c = text[i]
        if state == "code":
            if c == "/" and i + 1 < n and text[i + 1] == "/":
                out.append("  "); i += 2; state = "line"; continue
            if c == "/" and i + 1 < n and text[i + 1] == "*":
                out.append("  "); i += 2; state = "block"; continue
            if c in "\"'":
                out.append(c if keep_strings else " ")
                i += 1
                state = "dquote" if c == '"' else "squote"
                continue
            out.append(c); i += 1; continue
        if state == "line":
            out.append("\n" if c == "\n" else " ")
            if c == "\n":
                state = "code"
            i += 1; continue
        if state == "block":
            if c == "*" and i + 1 < n and text[i + 1] == "/":
                out.append("  "); i += 2; state = "code"; continue
            out.append("\n" if c == "\n" else " "); i += 1; continue
        if c == "\\" and i + 1 < n:
            out.append(text[i:i + 2] if keep_strings else "  "); i += 2; continue
        if (state == "dquote" and c == '"') or (state == "squote" and c == "'"):
            out.append(c if keep_strings else " "); i += 1; state = "code"; continue
        out.append(c if keep_strings else ("\n" if c == "\n" else " "))
        i += 1
    return "".join(out)


def corpus_types(corpus: Path) -> set[str]:
    """Type names declared by a directory of .ws files: the game's own scripts, or the
    engine's builtin declarations that ship with the parser crate (some enums, like
    ESaveGameType, are declared nowhere in the game's scripts but are usable)."""
    names = set()
    for f in corpus.rglob("*.ws"):
        code = mask(f.read_text(encoding="utf-8", errors="ignore"))
        for m in re.finditer(r"\b(?:class|struct|enum|state)\s+([A-Za-z_]\w*)", code):
            names.add(m.group(1))
        # enum members: `enum ECloudOp { SCO_Uploading, SCO_Local }`, usually multi-line
        for m in re.finditer(r"\benum\s+[A-Za-z_]\w*\s*\{(.*?)\}", code, flags=re.S):
            for part in m.group(1).split(","):
                nm = part.strip().split("=")[0].strip()
                if re.fullmatch(r"[A-Za-z_]\w*", nm):
                    names.add(nm)
    return names


def corpus_functions(corpus: Path) -> set[str]:
    names = set()
    for f in corpus.rglob("*.ws"):
        for m in re.finditer(r"\bfunction\s+([A-Za-z_]\w*)\s*\(",
                             f.read_text(encoding="utf-8", errors="ignore")):
            names.add(m.group(1))
    return names


def declared_identifiers(code: str) -> list[tuple[int, str, str]]:
    """(line, kind, name) for every variable and parameter the file introduces."""
    out = []
    for i, line in enumerate(code.splitlines(), 1):
        m = re.match(r"\s*var\s+([^:;]+):", line)
        if m:
            for part in m.group(1).split(","):
                nm = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", nm):
                    out.append((i, "variable", nm))
        m = re.match(r"\s*(?:(?:exec|private|public|protected|final|static)\s+)*"
                     r"function\s+[A-Za-z_]\w*\s*\(([^)]*)\)", line)
        if m:
            for param in m.group(1).split(","):
                param = re.sub(r"^(?:optional|out|in)\s+", "", param.strip())
                pm = re.match(r"([A-Za-z_]\w*)\s*:", param)
                if pm:
                    out.append((i, "parameter", pm.group(1)))
        for m in re.finditer(r"\b(?:function|class|struct|enum|state)\s+([A-Za-z_]\w*)", line):
            out.append((i, "declaration", m.group(1)))
    return out


def main() -> int:
    argv = sys.argv[1:]
    corpus = None
    builtins = None
    for opt in ("--corpus", "--builtins"):
        if opt in argv:
            i = argv.index(opt)
            value = Path(argv[i + 1])
            argv = argv[:i] + argv[i + 2:]
            if opt == "--corpus":
                corpus = value
            else:
                builtins = value
    files = [Path(p) for p in argv]
    if not files:
        print("usage: audit-ws.py <files...> [--corpus <dir>] [--builtins <dir>]")
        return 2

    types = set(BUILTIN_TYPES)
    engine_fns: set[str] = set()
    for label, where in (("corpus", corpus), ("builtins", builtins)):
        if where and where.is_dir():
            types |= corpus_types(where)
            engine_fns |= corpus_functions(where)
            print(f"{label}: {where}")
        else:
            print(f"{label}: not given - skipped")
    if not (corpus or builtins):
        print("       (engine type names, reserved words and structure are still checked)")

    mine: set[str] = set()
    for f in files:
        code = mask(f.read_text(encoding="utf-8"))
        mine |= set(re.findall(r"\bfunction\s+([A-Za-z_]\w*)", code))
        for m in re.finditer(r"\bvar\s+([^:;\n]+):", code):
            for part in m.group(1).split(","):
                nm = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", nm):
                    mine.add(nm)
        for m in re.finditer(r"\bfunction\s+[A-Za-z_]\w*\s*\(([^)]*)\)", code):
            for param in m.group(1).split(","):
                pm = re.match(r"(?:optional\s+|out\s+|in\s+)?([A-Za-z_]\w*)\s*:", param.strip())
                if pm:
                    mine.add(pm.group(1))

    problems = 0
    for f in files:
        raw = f.read_text(encoding="utf-8")
        code = mask(raw)
        print(f"== {f.name}")

        for line, kind, nm in declared_identifiers(code):
            if nm in RESERVED:
                print(f"   FAIL line {line}: {kind} '{nm}' - reserved word "
                      f"(the compiler answers TOKEN_<X>, expecting TOKEN_IDENT)")
                problems += 1
            elif nm in types:
                print(f"   FAIL line {line}: {kind} '{nm}' - that is an engine TYPE name")
                problems += 1

        depth = 0
        for i, line in enumerate(code.splitlines(), 1):
            if re.match(r"\s*var\s+", line) and depth == 0:
                print(f"   FAIL line {i}: file-scope 'var' - no globals in WitcherScript")
                problems += 1
            depth += line.count("{") - line.count("}")

        if engine_fns:
            unknown = sorted(
                c for c in set(re.findall(r"(?<![\w.])([A-Za-z_]\w*)\s*\(", code))
                if c not in mine and c not in engine_fns and c not in KEYWORDS
                and c not in MODDING_API
            )
            for u in unknown:
                print(f"   FAIL call '{u}' is in neither this mod nor the game's scripts")
                problems += 1
            if not unknown:
                print("   ok  every call resolves to this mod or to the game")

            # every word used as a name must exist: here, in the game, or in the
            # engine/loader globals. This is the check that catches `null` (the
            # literal is `NULL`) and any typo the compiler would answer with
            # "I dont know any '<word>'".
            engine_syms = engine_fns | types | ENGINE_GLOBALS
            words = set(re.findall(r"(?<![.\w])([A-Za-z_]\w*)", code))
            alien = sorted(w for w in words
                           if w not in mine and w not in engine_syms
                           and w not in RESERVED and w not in KEYWORDS)
            for w in alien:
                print(f"   FAIL '{w}' is declared nowhere in this mod and does not exist "
                      f"in the game (a typo, or a literal like `null` - use `NULL`)")
                problems += 1
            if not alien:
                print("   ok  every name is either this mod's or the game's")

        # `null` is not a WitcherScript literal: the compiler answers
        # "I dont know any 'null'". The literal is NULL, in capitals.
        for i, line in enumerate(code.splitlines(), 1):
            if re.search(r"(?<![.\w])null(?![.\w])", line):
                print(f"   FAIL line {i}: `null` does not exist - the literal is `NULL`")
                problems += 1

        plain = mask(raw, keep_strings=True)   # braces live in text too
        for o, c, what in (("{", "}", "braces"), ("(", ")", "parentheses")):
            d = plain.count(o) - plain.count(c)
            if d:
                print(f"   FAIL {what} unbalanced by {d:+d}")
                problems += 1

    print()
    print(f"FAIL - {problems} problem(s) the compiler would reject" if problems
          else "PASS - no syntax traps found")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
