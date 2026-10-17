#!/usr/bin/env python3
"""Checks that the website (site/index.html) has a Spanish version for everything marked for translation.

English is the page itself; Spanish is the JSON block with id "i18n-es". Fails when:
  - a data-t / data-t-<attribute> key has no Spanish text, or a Spanish text is never used
  - an install device has no Spanish entry, or its steps / files / side notes do not line up with the English ones
  - the head's texts or the small interface texts are missing in Spanish
Run:  python3 tool/test_site_i18n.py   (needs node, which the CI image has)
"""
import json, re, subprocess, sys, pathlib

HTML = (pathlib.Path(__file__).resolve().parent.parent / 'site' / 'index.html').read_text(encoding='utf-8')
fails = []

m = re.search(r'<script id="i18n-es" type="application/json">(.*?)</script>', HTML, re.S)
if not m:
    sys.exit('no i18n-es block in site/index.html')
es = json.loads(m.group(1))

used = set(re.findall(r'\sdata-t="([^"]+)"', HTML)) | set(re.findall(r'\sdata-t-[a-z-]+="([^"]+)"', HTML))
for k in sorted(used - set(es['s'])):
    fails.append(f'no Spanish text for key {k!r}')
for k in sorted(set(es['s']) - used):
    fails.append(f'Spanish text {k!r} is never used')
for k, v in es['s'].items():
    if not v.strip():
        fails.append(f'Spanish text {k!r} is empty')
for k in ('install', 'copy', 'copied', 'selcopy', 'opendl', 'newest', 'alldl'):
    if not es['ui'].get(k):
        fails.append(f'no Spanish interface text {k!r}')
for k in ('title', 'desc', 'ogt', 'ogd'):
    if not es['meta'].get(k):
        fails.append(f'no Spanish head text {k!r}')

# The English devices, read from the page's own script, against the Spanish ones.
js = re.search(r'const DEVICES=(\[.*?\n\]);\nlet release', HTML, re.S)
if not js:
    sys.exit('could not find DEVICES in site/index.html')
prog = 'const code=n=>"";const DEVICES=%s;console.log(JSON.stringify(DEVICES))' % js.group(1)
out = subprocess.run(['node', '-e', prog], capture_output=True, text=True)
if out.returncode:
    sys.exit('node could not read DEVICES: ' + out.stderr)
for d in json.loads(out.stdout):
    e = es['dev'].get(d['id'])
    if not e:
        fails.append(f"device {d['id']} has no Spanish entry")
        continue
    for k in ('name', 'sub', 'title'):
        if not e.get(k):
            fails.append(f"device {d['id']}: no Spanish {k}")
    if len(e['steps']) != len(d['steps']):
        fails.append(f"device {d['id']}: {len(d['steps'])} steps in English, {len(e['steps'])} in Spanish")
    if len(e.get('side', [])) != len(d['side']):
        fails.append(f"device {d['id']}: side notes differ in number")
    if len(e.get('files', [])) != len(d.get('files') or []):
        fails.append(f"device {d['id']}: file buttons differ in number")
    if bool(e.get('note')) != bool(d.get('note')):
        fails.append(f"device {d['id']}: a note in only one language")
    if bool(e.get('open')) != bool(d.get('open')):
        fails.append(f"device {d['id']}: the open-in-browser button in only one language")
    # the same download codes in both
    en_codes = sorted(re.findall(r'\[\[code:(\d+)\]\]', ' '.join(d['steps'])))
    es_codes = sorted(re.findall(r'\[\[code:(\d+)\]\]', ' '.join(e['steps'])))
    if en_codes != es_codes:
        fails.append(f"device {d['id']}: download codes differ ({en_codes} vs {es_codes})")

if fails:
    print('\n'.join('FAIL ' + f for f in fails))
    sys.exit(1)
print(f"ok: {len(used)} marked texts and {len(es['dev'])} devices have a Spanish version")
