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

# Words the parser knows; never identifiers we control, and not "unknown calls".
KEYWORDS = {
    "var", "function", "exec", "import", "final", "latent", "optional", "out", "in",
    "private", "protected", "public", "const", "new", "this", "super", "parent",
    "if", "else", "for", "while", "do", "switch", "case", "default", "break",
    "continue", "return", "true", "false", "null", "class", "struct", "enum",
    "state", "autobind", "event", "timer", "hint", "editable", "tooltip", "range",
    "saved", "inline", "abstract", "native", "static", "wrapped", "editoronly",
    "and", "or", "not", "extends",
}

# Part of the modding API, not in the game's own scripts.
MODDING_API = {"wrapMethod", "wrappedMethod", "addStat", "addEffect"}


def mask(text: str, keep_strings: bool = False) -> str:
    """Comments (and optionally literals) blanked out, newlines kept: line numbers
    stay true, and nothing inside a comment can produce a hit."""
    def blank(m: re.Match) -> str:
        return re.sub(r"[^\n]", " ", m.group(0))

    out = re.sub(r"/\*.*?\*/", blank, text, flags=re.S)
    out = re.sub(r"//[^\n]*", blank, out)
    if not keep_strings:
        out = re.sub(r"'(\\.|[^'\\])*'", blank, out)
        out = re.sub(r'"(\\.|[^"\\])*"', blank, out)
    return out


def corpus_types(corpus: Path) -> set[str]:
    names = set()
    for f in corpus.rglob("*.ws"):
        for m in re.finditer(r"\b(?:class|struct|enum|state)\s+([A-Za-z_]\w*)",
                             mask(f.read_text(encoding="utf-8", errors="ignore"))):
            names.add(m.group(1))
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
    return out


def main() -> int:
    argv = sys.argv[1:]
    corpus = None
    if "--corpus" in argv:
        i = argv.index("--corpus")
        corpus = Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    files = [Path(p) for p in argv]
    if not files:
        print("usage: audit-ws.py <files...> [--corpus <dir>]")
        return 2

    types = set(BUILTIN_TYPES)
    engine_fns: set[str] = set()
    if corpus and corpus.is_dir():
        types |= corpus_types(corpus)
        engine_fns = corpus_functions(corpus)
        print(f"corpus: {corpus} ({len(types)} type names, {len(engine_fns)} functions)")
    else:
        print("corpus: not given - checking engine type names and structure only")

    mine: set[str] = set()
    for f in files:
        mine |= set(re.findall(r"\bfunction\s+([A-Za-z_]\w*)\s*\(",
                               mask(f.read_text(encoding="utf-8"))))

    problems = 0
    for f in files:
        raw = f.read_text(encoding="utf-8")
        code = mask(raw)
        print(f"== {f.name}")

        for line, kind, nm in declared_identifiers(code):
            if nm in types:
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
