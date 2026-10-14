"""The Website workflow syncs site/ into the website folder with --delete, so everything the Release workflow puts in
that folder has to be excluded, or a change to the page would wipe it (it once removed the web app)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE_OWNED = ('downloads/', 'releases.json', 'webapp/')


class SiteWorkflowTest(unittest.TestCase):
    def test_release_owned_paths_survive_a_site_publish(self):
        site = (ROOT / '.github/workflows/site.yml').read_text(encoding='utf-8')
        for name in RELEASE_OWNED:
            self.assertIn(f"--exclude '/{name}'", site, f'site.yml would delete {name} on the server')

    def test_the_release_script_writes_where_the_site_workflow_leaves_alone(self):
        script = (ROOT / 'tool/publish_site.sh').read_text(encoding='utf-8')
        for name in RELEASE_OWNED:
            self.assertIn(name.rstrip('/'), script, f'publish_site.sh no longer writes {name}: update the exclude list')

    def test_the_web_app_is_served_from_the_whole_website_folder(self):
        # A bind mount of webapp/ alone goes stale (404 until Caddy restarts) when a publish deletes and remakes it.
        overlay = (ROOT / 'server/docker-compose.webapp.yml').read_text(encoding='utf-8')
        caddy = (ROOT / 'server/sites/webapp.caddy').read_text(encoding='utf-8')
        self.assertNotIn('/webapp:/', overlay)
        self.assertIn(':/srv/web:ro', overlay)
        self.assertIn('root * /srv/web/webapp', caddy)


if __name__ == '__main__':
    unittest.main()
