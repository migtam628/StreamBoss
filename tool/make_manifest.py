#!/usr/bin/env python3
"""Writes the website's release list (releases.json) and the "latest" download folder for one release.

The app's update check, the Roku installer and the website's download buttons read releases.json, which has the
shape of GitHub's releases list (newest first): tag_name, name, prerelease, draft, html_url, body, published_at and
assets with name, size, browser_download_url and digest ("sha256:<hex>").

  python3 tool/make_manifest.py --tag v0.3.0b41 --artifacts artifacts --notes notes.md --prerelease true \\
      --feed old-releases.json --out releases.json --latest-dir latest

--feed is the list as it is on the website now (missing or empty is fine). --latest-dir gets a copy of each file with
the version taken out of its name (StreamBoss-0.3.0b41-android-arm64-v8a.apk -> StreamBoss-android-arm64-v8a.apk),
so a link such as /downloads/latest/StreamBoss-android-arm64-v8a.apk always gives the newest build.
"""
import argparse
import datetime
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

BASE = 'https://streamboss.site'
KEEP = 12  # releases kept in the list (and on the server: see server/README.md)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def latest_name(name: str, version: str) -> str:
    """The file name without the version: StreamBoss-0.3.0b41-macos.zip -> StreamBoss-macos.zip."""
    return name.replace('-' + version + '-', '-', 1) if ('-' + version + '-') in name else name


def entry_for(tag: str, artifacts: Path, notes: str, prerelease: bool, base: str = BASE, now=None) -> dict:
    files = sorted(p for p in artifacts.iterdir() if p.is_file())
    if not files:
        raise SystemExit(f'no files in {artifacts}')
    when = (now or datetime.datetime.now(datetime.timezone.utc)).strftime('%Y-%m-%dT%H:%M:%SZ')
    return {
        'tag_name': tag,
        'name': f'StreamBoss {tag}',
        'draft': False,
        'prerelease': prerelease,
        'html_url': f'{base}/downloads/{tag}/',
        'published_at': when,
        'body': notes,
        'assets': [
            {
                'name': p.name,
                'size': p.stat().st_size,
                'browser_download_url': f'{base}/downloads/{tag}/{p.name}',
                'digest': 'sha256:' + sha256_of(p),
            }
            for p in files
        ],
    }


def merge(feed: list, entry: dict, keep: int = KEEP) -> list:
    """The list with [entry] first, any older entry for the same tag replaced, and only the newest [keep] kept."""
    rest = [r for r in feed if isinstance(r, dict) and r.get('tag_name') != entry['tag_name']]
    return ([entry] + rest)[:keep]


def read_feed(path: Path) -> list:
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return []
    return data if isinstance(data, list) else []


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', required=True)
    ap.add_argument('--artifacts', required=True, type=Path)
    ap.add_argument('--notes', type=Path)
    ap.add_argument('--prerelease', default='false')
    ap.add_argument('--feed', type=Path)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--latest-dir', type=Path)
    ap.add_argument('--base', default=BASE)
    ap.add_argument('--keep', type=int, default=KEEP)
    a = ap.parse_args(argv)

    if not re.fullmatch(r'v\d+\.\d+\.\d+(b\d+|-[0-9A-Za-z.-]+)?', a.tag):
        raise SystemExit(f'odd tag: {a.tag}')
    notes = a.notes.read_text(encoding='utf-8').strip() if a.notes and a.notes.exists() else ''
    entry = entry_for(a.tag, a.artifacts, notes, a.prerelease == 'true', a.base)
    feed = read_feed(a.feed) if a.feed else []
    a.out.write_text(json.dumps(merge(feed, entry, a.keep), indent=2) + '\n', encoding='utf-8')

    if a.latest_dir:
        a.latest_dir.mkdir(parents=True, exist_ok=True)
        version = a.tag[1:]
        for asset in entry['assets']:
            shutil.copy2(a.artifacts / asset['name'], a.latest_dir / latest_name(asset['name'], version))
        (a.latest_dir / 'VERSION.txt').write_text(a.tag + '\n', encoding='utf-8')
    print(f'{a.out}: {len(entry["assets"])} files for {a.tag}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
