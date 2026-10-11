#!/usr/bin/env python3
"""Lists the texts the app asks tr()/trf() for, and which of them a language still lacks.

    python3 tool/l10n_keys.py            # every key found in lib/
    python3 tool/l10n_keys.py missing es # keys with no Spanish translation yet (es, it or pt)

The English text is the key (see lib/l10n/l10n.dart). Texts that are looked up through a table (the option labels
in Settings, layout names and descriptions, colours) do not appear in a `tr('...')` call; they are listed in
EXTRA below and in lib/layouts/ui_layout.dart, so keep this scan honest by running the l10n test.
"""
import os, re, sys

SENTENCE = os.environ.get('SENTENCE') == '1'
NAMED = ['title','subtitle','label','tooltip','hintText','labelText','helperText','hint','semanticLabel','message','text']
# 'text' / 'message' only when it is a named argument (not variables)

def scan_string(s, i):
    """s[i] is a quote. Return (end_index_exclusive, value or None if interpolated/unsupported, raw)"""
    q = s[i]
    raw = i > 0 and s[i-1] == 'r' and (i < 2 or not (s[i-2].isalnum() or s[i-2]=='_'))
    if s.startswith(q*3, i):
        return None  # triple quoted: skip
    j = i + 1
    out = []
    interp = False
    while j < len(s):
        c = s[j]
        if c == q:
            return j + 1, (None if interp else ''.join(out))
        if c == '\n':
            return None
        if raw:
            out.append(c); j += 1; continue
        if c == '\\':
            n = s[j+1]
            m = {'n':'\n','t':'\t',"'":"'",'"':'"','\\':'\\','$':'$','r':'\r'}
            if n in m:
                out.append(m[n]); j += 2; continue
            if n == 'u':
                if s[j+2] == '{':
                    k = s.index('}', j)
                    out.append(chr(int(s[j+3:k],16))); j = k+1; continue
                out.append(chr(int(s[j+2:j+6],16))); j += 6; continue
            return j+2 if False else None
        if c == '$':
            interp = True
            j += 1; continue
        out.append(c); j += 1
    return None

def tokens(s):
    """Yield (kind, start, end, value) for string literals, skipping comments."""
    i = 0
    n = len(s)
    res = []
    while i < n:
        c = s[i]
        if s.startswith('//', i):
            j = s.find('\n', i)
            i = n if j < 0 else j; continue
        if s.startswith('/*', i):
            j = s.find('*/', i)
            i = n if j < 0 else j + 2; continue
        if c in '\'"':
            if s.startswith(c*3, i):
                j = s.find(c*3, i+3)
                i = n if j < 0 else j + 3; continue
            # find end honoring escapes and ${} nesting
            j = i + 1
            depth = 0
            interp_vals = False
            raw = i > 0 and s[i-1] == 'r'
            while j < n:
                d = s[j]
                if not raw and d == '\\':
                    j += 2; continue
                if d == '$' and not raw and j+1 < n and s[j+1] == '{':
                    # skip nested
                    k = j + 2; dep = 1
                    while k < n and dep:
                        if s[k] == '{': dep += 1
                        elif s[k] == '}': dep -= 1
                        elif s[k] in '\'"':
                            # nested string
                            qq = s[k]; k += 1
                            while k < n and s[k] != qq:
                                if s[k] == '\\': k += 1
                                k += 1
                        k += 1
                    j = k; continue
                if d == c:
                    break
                if d == '\n':
                    break
                j += 1
            end = j + 1
            sc = scan_string(s, i)
            val = sc[1] if sc and sc[0] == end else None
            res.append((i, end, val))
            i = end; continue
        i += 1
    return res

def keys_in(root='lib'):
    found = {}
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.endswith('.dart') or dp.startswith(os.path.join('lib', 'l10n')):
                continue
            path = os.path.join(dp, f)
            s = open(path).read()
            toks = tokens(s)
            groups = []
            for t in toks:
                if groups and re.fullmatch(r'\s*', s[groups[-1][-1][1]:t[0]]):
                    groups[-1].append(t)
                else:
                    groups.append([t])
            for g in groups:
                if any(t[2] is None for t in g):
                    continue
                before = s[:g[0][0]].rstrip()
                if re.search(r'(?<![\w.])(tr|trf)\($', before):
                    key = ''.join(t[2] for t in g)
                    if not key.startswith('//'):  # shader sample text
                        found.setdefault(key, path)
    return found

if __name__ == '__main__':
    keys = keys_in()
    if len(sys.argv) > 2 and sys.argv[1] == 'missing':
        table = open('lib/l10n/strings_%s.dart' % sys.argv[2]).read()
        have = set(m.group(1) for m in re.finditer(r"^\s*'((?:[^'\\]|\\.)*)':", table, re.M))
        for k in sorted(keys):
            esc = k.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('$', '\\$')
            if esc not in have:
                print(repr(k))
    else:
        for k in sorted(keys):
            print(repr(k))
