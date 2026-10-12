#!/usr/bin/env python3
"""The Apple TV app's translations.

The app's texts are written in English in the Swift code: SwiftUI's Text("..."), Button("..."), TextField("...") and
friends (which look the text up in Localizable.strings by themselves), and tr("...") / trf("...", args) in Core/
(which do the same for plain strings). The English text is the key. The Spanish, Italian and Portuguese versions
live in tvos/i18n/strings.json and this script writes them to tvos/App/Resources/<lang>.lproj/Localizable.strings.
It also checks that:
  * every text used in the code has all three translations with the same %@ / %lld placeholders,
  * no translation is left over after its text was removed from the code,
  * nobody writes  Button(cond ? "A" : "B")  or the same with Text/TextField (those pick a plain String and are
    never translated; wrap each in LocalizedStringKey("...")),
  * project.yml lists the four languages.

  python3 tool/tvos_i18n.py            write the .strings files
  python3 tool/tvos_i18n.py --check    fail if anything is missing or the files are out of date (CI runs this)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / 'tvos'
JSON_FILE = ROOT / 'i18n' / 'strings.json'
RES = ROOT / 'App' / 'Resources'
LANGS = ('es', 'it', 'pt')

# Calls whose first argument, when it is a string literal, is looked up in Localizable.strings.
CALLS = ('Text', 'Button', 'TextField', 'SecureField', 'Picker', 'Label', 'Toggle', 'NavigationLink',
         'navigationTitle', 'LocalizedStringKey', 'NSLocalizedString', 'tr', 'trf')
INT_HINT = re.compile(r'\.count\b|\bseason\b|\bnumber\b|\?\? 0\b|\bn\b|\bnum\b')


def blank_comments(text: str) -> str:
    """The source with // and /* */ comments replaced by spaces (strings are left alone: "http://host" is not a comment)."""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(ch if ch == '\n' else ' ' for ch in text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def scan(text: str):
    """Yield (offset, call name, literal key) for every  Name("literal"...)  in Swift source (comments skipped)."""
    text = blank_comments(text)
    pat = re.compile(r'(?<![\w])(' + '|'.join(CALLS) + r')\(\s*"')
    for m in pat.finditer(text):
        i, key, ok = m.end(), [], True
        while i < len(text):
            c = text[i]
            if c == '\\' and text[i + 1:i + 2] == '(':
                depth, j = 1, i + 2
                while j < len(text) and depth:
                    depth += {'(': 1, ')': -1}.get(text[j], 0)
                    j += 1
                expr = text[i + 2:j - 1]
                key.append('%lld' if INT_HINT.search(expr) else '%@')
                i = j
                continue
            if c == '\\':
                key.append({'n': '\n', 't': '\t', '"': '"', '\\': '\\'}.get(text[i + 1:i + 2], text[i + 1:i + 2]))
                i += 2
                continue
            if c == '"':
                break
            if c == '\n':
                ok = False
                break
            key.append(c)
            i += 1
        if ok:
            yield m.start(), m.group(1), ''.join(key)


def used_keys(problems: list) -> dict:
    keys = {}
    for f in sorted((ROOT / 'App').rglob('*.swift')) + sorted((ROOT / 'Core').rglob('*.swift')):
        src = f.read_text(encoding='utf-8')
        for off, call, key in scan(src):
            if call == 'tr' or call == 'NSLocalizedString' or call in CALLS:
                line = src.count('\n', 0, off) + 1
                keys.setdefault(key, f'{f.relative_to(ROOT.parent)}:{line}')
        code = blank_comments(src)
        for m in re.finditer(r'\b(Text|Button|TextField|SecureField|Picker|Label)\(\s*(?:[^()"\n]|\([^()\n]*\))*\?\s*"[^"\n]*"\s*:\s*"', code):
            line = code.count('\n', 0, m.start()) + 1
            problems.append(f'{f.relative_to(ROOT.parent)}:{line}: a choice between two string literals is not translated; wrap each in LocalizedStringKey("...")')
    return keys


def placeholders(s: str) -> list:
    return sorted(re.findall(r'%(?:lld|@)', s))


def strings_file(table: dict, lang: str) -> str:
    def esc(s):
        return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    head = f'/* GENERATED by tool/tvos_i18n.py from tvos/i18n/strings.json. Do not edit by hand. ({lang}) */\n'
    return head + ''.join(f'"{esc(k)}" = "{esc(table[k][lang])}";\n' for k in table)


def main() -> int:
    check = '--check' in sys.argv
    table = json.loads(JSON_FILE.read_text(encoding='utf-8'))
    problems = []
    used = used_keys(problems)
    for key, where in sorted(used.items()):
        if key not in table:
            problems.append(f'{where}: no translation for "{key}" (add it to tvos/i18n/strings.json)')
    for key in sorted(table):
        if key not in used:
            problems.append(f'tvos/i18n/strings.json: "{key}" is not used in the code any more (remove it)')
        for lang in LANGS:
            v = table[key].get(lang)
            if not isinstance(v, str) or not v.strip():
                problems.append(f'tvos/i18n/strings.json: "{key}" has no {lang} text')
            elif placeholders(v) != placeholders(key):
                problems.append(f'tvos/i18n/strings.json: "{key}" in {lang} has placeholders {placeholders(v)}, the English has {placeholders(key)}')
    yml = (ROOT / 'project.yml').read_text(encoding='utf-8')
    m = re.search(r'CFBundleLocalizations:\s*\[([^\]]*)\]', yml)
    langs = sorted(x.strip() for x in m.group(1).split(',')) if m else []
    if langs != sorted(('en',) + LANGS):
        problems.append(f'tvos/project.yml: CFBundleLocalizations must list en, es, it, pt (found {langs})')

    for lang in LANGS:
        path = RES / f'{lang}.lproj' / 'Localizable.strings'
        text = strings_file(table, lang)
        if check:
            if not path.exists() or path.read_text(encoding='utf-8') != text:
                problems.append(f'{path.relative_to(ROOT.parent)} is out of date: run python3 tool/tvos_i18n.py')
        elif not problems:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
            print(f'wrote {path.relative_to(ROOT.parent)}')
    for p in problems:
        print(p)
    print(f'{len(used)} texts used, {len(table)} translated, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
