import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import make_manifest as m  # noqa: E402


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.art = self.tmp / 'art'
        self.art.mkdir()
        (self.art / 'StreamBoss-0.3.0b41-macos.zip').write_bytes(b'mac')
        (self.art / 'StreamBoss-0.3.0b41-android-arm64-v8a.apk').write_bytes(b'apk!')
        (self.art / 'SHA256SUMS.txt').write_text('x')

    def run_main(self, tag='v0.3.0b41', feed=None, pre='true'):
        out = self.tmp / 'releases.json'
        args = ['--tag', tag, '--artifacts', str(self.art), '--prerelease', pre, '--out', str(out),
                '--latest-dir', str(self.tmp / 'latest')]
        if feed:
            args += ['--feed', str(feed)]
        self.assertEqual(m.main(args), 0)
        return json.loads(out.read_text())

    def test_entry_has_the_fields_the_clients_read(self):
        feed = self.run_main()
        self.assertEqual(len(feed), 1)
        r = feed[0]
        self.assertEqual((r['tag_name'], r['prerelease'], r['draft']), ('v0.3.0b41', True, False))
        names = [a['name'] for a in r['assets']]
        self.assertEqual(names, sorted(names))
        mac = next(a for a in r['assets'] if a['name'].endswith('macos.zip'))
        self.assertEqual(mac['size'], 3)
        self.assertEqual(mac['browser_download_url'], 'https://streamboss.site/downloads/v0.3.0b41/StreamBoss-0.3.0b41-macos.zip')
        self.assertEqual(mac['digest'], 'sha256:348a629f5ceed032c3e8706ec47d9bfafb00fb4250b018dd965435ca50cb836e')

    def test_latest_folder_has_names_without_the_version(self):
        self.run_main()
        got = sorted(p.name for p in (self.tmp / 'latest').iterdir())
        self.assertEqual(got, ['SHA256SUMS.txt', 'StreamBoss-android-arm64-v8a.apk', 'StreamBoss-macos.zip', 'VERSION.txt'])
        self.assertEqual((self.tmp / 'latest' / 'VERSION.txt').read_text(), 'v0.3.0b41\n')

    def test_new_release_goes_first_and_the_same_tag_is_replaced(self):
        old = self.tmp / 'old.json'
        old.write_text(json.dumps([{'tag_name': 'v0.3.0b40'}, {'tag_name': 'v0.3.0b41', 'body': 'stale'}, {'tag_name': 'v0.3.0b39'}]))
        feed = self.run_main(feed=old)
        self.assertEqual([r['tag_name'] for r in feed], ['v0.3.0b41', 'v0.3.0b40', 'v0.3.0b39'])
        self.assertNotEqual(feed[0].get('body'), 'stale')

    def test_only_the_newest_are_kept(self):
        self.assertEqual(len(m.merge([{'tag_name': f'v0.3.0b{i}'} for i in range(30)], {'tag_name': 'v0.3.0b99'})), m.KEEP)

    def test_a_missing_or_broken_list_is_an_empty_one(self):
        self.assertEqual(m.read_feed(self.tmp / 'nope.json'), [])
        bad = self.tmp / 'bad.json'
        bad.write_text('<html>404</html>')
        self.assertEqual(m.read_feed(bad), [])
        bad.write_text('{"not": "a list"}')
        self.assertEqual(m.read_feed(bad), [])

    def test_a_tag_that_does_not_look_like_one_is_refused(self):
        with self.assertRaises(SystemExit):
            self.run_main(tag='main')

    def test_latest_name(self):
        self.assertEqual(m.latest_name('StreamBoss-0.3.0b41-roku.zip', '0.3.0b41'), 'StreamBoss-roku.zip')
        self.assertEqual(m.latest_name('SHA256SUMS.txt', '0.3.0b41'), 'SHA256SUMS.txt')


if __name__ == '__main__':
    unittest.main()
