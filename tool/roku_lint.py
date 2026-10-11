#!/usr/bin/env python3
"""Checks the Roku channel's BrightScript for things the Roku's own compiler rejects but BrighterScript (the check in
CI) lets through: reserved words used as names, the component's `m` used as a loop variable, a method called on a
parenthesised expression. Usage: python3 tool/roku_lint.py [roku-folder]"""
import re
import sys
from pathlib import Path

# Words that are reserved in BrightScript but are not part of ordinary syntax, so they can only be misuse here.
# (`type` is the built-in function type(x): only a call is allowed.)
RESERVED = {'pos', 'tab', 'run', 'line_num', 'objfun', 'getglobalaa', 'getlastruncompileerror',
            'getlastrunruntimeerror', 'goto', 'let', 'dim', 'stop', 'rem', 'longinteger', 'interface'}


def strip(line: str) -> str:
    """The code of one line: no string contents, no comment."""
    out, in_str = [], False
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == '"':
                if line[i + 1:i + 2] == '"':
                    i += 1  # an escaped quote
                else:
                    in_str = False
        elif c == '"':
            in_str = True
            out.append('""')
        elif c == "'":
            break
        else:
            out.append(c)
        i += 1
    code = ''.join(out)
    return re.sub(r'(^|\s)rem(\s.*)?$', '', code, flags=re.I)


def check(path: Path) -> list:
    problems = []
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        code = strip(raw)
        low = code.lower()
        for w in RESERVED:
            if re.search(r'\b%s\b' % w, low):
                problems.append(f'{path}:{n}: reserved word "{w}" used as a name: {raw.strip()}')
        if re.search(r'\btype\b(?!\s*\()', low):
            problems.append(f'{path}:{n}: "type" is reserved (only the call type(x) is allowed): {raw.strip()}')
        if re.search(r'\bfor\s+each\s+m\b', low) or re.search(r'(^|[^.\w])m\s*=(?!=)', low):
            problems.append(f'{path}:{n}: "m" is the component\'s own variable, do not assign or loop with it: {raw.strip()}')
        if re.search(r'(^|[ =+(,])\([^()]*\)\.\w+', code):
            problems.append(f'{path}:{n}: a method called on a parenthesised expression: {raw.strip()}')
    return problems


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else 'roku')
    files = sorted(list(root.glob('source/**/*.brs')) + list(root.glob('components/**/*.brs')))
    if not files:
        print(f'no .brs files under {root}')
        return 1
    problems = [p for f in files for p in check(f)]
    for p in problems:
        print(p)
    print(f'{len(files)} files checked, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
