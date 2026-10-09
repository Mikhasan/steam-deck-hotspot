"""Verify SteamOS recovery and read-only rollback with mocked system commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DEPENDENCIES = (ROOT / 'src/dependencies.sh').read_text()
HELPER = (ROOT / 'src/hotspot-helper.sh').read_text()
CLEANUP = HELPER[HELPER.index('cleanup() {'):HELPER.index('trap cleanup EXIT')]


class DependencyTests(unittest.TestCase):
    def run_recovery(self, ready=False, readonly='enabled', fail='', seeds=True):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            if seeds:
                (base / 'archlinux.gpg').touch()
                (base / 'holo.gpg').touch()
            library = base / 'dependencies.sh'
            library.write_text(DEPENDENCIES.replace('/usr/share/pacman/keyrings', str(base)))
            script = '''set -Eeuo pipefail
readonly_changed=0
started=0
command() {
    if [[ $1 != -v ]]; then builtin command "$@"; return; fi
    case $2 in
        dnsmasq|hostapd|hostapd_cli|wpa_passphrase) [[ $READY == yes ]];;
        *) return 0;;
    esac
}
steamos-readonly() {
    printf 'readonly %s\\n' "$*" >>"$TRACE"
    case $1 in
        status) printf '%s\\n' "$READONLY";;
        disable) READONLY=disabled;;
        enable) READONLY=enabled;;
    esac
}
pacman-key() {
    printf 'key %s\\n' "$*" >>"$TRACE"
    [[ $FAIL != $1 ]]
}
pacman() {
    printf 'pacman %s\\n' "$*" >>"$TRACE"
    [[ $FAIL != install ]] || return 1
    READY=yes
}
'''
            script += CLEANUP + '\ntrap cleanup EXIT\nsource "$LIBRARY"\nensure_hotspot_dependencies\n'
            trace = base / 'trace'
            trace.touch()
            result = subprocess.run(['bash', '-c', script], env={**os.environ, 'TRACE': str(trace), 'LIBRARY': str(library), 'READY': 'yes' if ready else 'no', 'READONLY': readonly, 'FAIL': fail}, text=True, capture_output=True)
            return result, trace.read_text().splitlines()

    def test_normal_launch_leaves_system_alone(self):
        result, trace = self.run_recovery(ready=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, [])

    def test_update_restores_keyring_before_packages(self):
        result, trace = self.run_recovery()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, ['readonly status', 'readonly disable', 'key --init', 'key --populate archlinux holo', 'pacman -S --needed --noconfirm dnsmasq hostapd wpa_supplicant', 'readonly enable'])

    def test_preserves_already_writable_system(self):
        result, trace = self.run_recovery(readonly='disabled')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('readonly disable', trace)
        self.assertNotIn('readonly enable', trace)

    def test_failed_steps_restore_readonly_protection(self):
        for failure in ('--init', '--populate', 'install'):
            with self.subTest(failure=failure):
                result, trace = self.run_recovery(fail=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(trace[-1], 'readonly enable')
                if failure != 'install':
                    self.assertFalse(any(line.startswith('pacman ') for line in trace))

    def test_missing_distro_keys_does_not_install(self):
        result, trace = self.run_recovery(seeds=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(trace, [])

    def test_unknown_readonly_state_stops_before_mutation(self):
        result, trace = self.run_recovery(readonly='unknown')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(trace, ['readonly status'])


if __name__ == '__main__':
    unittest.main()
