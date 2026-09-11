"""Exercise packaging without touching Wi-Fi, system packages or real user files."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.app = self.base / 'Application With Spaces'
        self.desktop = self.base / 'Desktop With Spaces'

    def install(self, app=None):
        return subprocess.run(
            ['bash', str(ROOT / 'install.sh'), '--target', str(app or self.app), str(self.desktop)],
            text=True, capture_output=True)

    def test_install_and_update_preserve_settings(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        settings = self.app / 'settings.txt'
        ssid, password = settings.read_text().splitlines()
        self.assertEqual(ssid, 'Deck-Hotspot')
        self.assertRegex(password, r'^[0-9a-f]{24}$')
        self.assertEqual(settings.stat().st_mode & 0o777, 0o600)
        launcher = (self.desktop / 'Steam-Deck-Hotspot.desktop').read_text()
        self.assertIn(f'Exec=/bin/bash "{self.app}/toggle.sh"', launcher)
        settings.write_text('Custom Name\nMyOwnPassword42\n')
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(settings.read_text(), 'Custom Name\nMyOwnPassword42\n')

    def test_unique_passwords(self):
        self.assertEqual(self.install().returncode, 0)
        other = self.base / 'Other'
        self.assertEqual(self.install(other).returncode, 0)
        self.assertNotEqual((self.app / 'settings.txt').read_text(), (other / 'settings.txt').read_text())

    def test_reject_existing_directory(self):
        self.app.mkdir()
        sentinel = self.app / 'keep.txt'
        sentinel.write_text('untouched')
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(sentinel.read_text(), 'untouched')

    def test_reject_ambiguous_desktop_paths(self):
        for char in ['"', '\\', '`', '$', '%', '\n', '\r']:
            with self.subTest(char=char):
                self.assertNotEqual(self.install(self.base / ('Bad' + char)).returncode, 0)

    def test_uninstall_only_owned_files(self):
        self.assertEqual(self.install().returncode, 0)
        sentinel = self.app / 'keep.txt'
        sentinel.write_text('untouched')
        mock = self.base / 'bin'
        mock.mkdir()
        auth = mock / 'pkexec'
        auth.write_text('#!/bin/sh\n[ "$3" = uninstall ]\n')
        auth.chmod(0o755)
        # In a Flatpak test runner, mimic host dispatch without escaping the fixture.
        spawn = mock / 'flatpak-spawn'
        spawn.write_text('#!/bin/sh\nshift\nexec "$@"\n')
        spawn.chmod(0o755)
        script = self.app / 'uninstall.sh'
        script.write_text(script.read_text().replace('[[ -f /.flatpak-info ]]', '[[ -f /nonexistent-test-flatpak-info ]]'))
        result = subprocess.run(['bash', str(script)], env={**os.environ, 'PATH': str(mock) + ':' + os.environ['PATH']}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(sentinel.exists())
        self.assertFalse((self.app / 'settings.txt').exists())
        self.assertFalse((self.desktop / 'Steam-Deck-Hotspot.desktop').exists())


if __name__ == '__main__':
    unittest.main()
