"""Verify opt-in streaming access without touching the machine firewall."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = (ROOT / 'src/hotspot-helper.sh').read_text()
FUNCTIONS = HELPER[HELPER.index('enable_sunshine_access() {'):HELPER.index('stop_hotspot() {')]


class FirewallTests(unittest.TestCase):
    def configure(self, enabled=True, preexisting=False, zone='nm-shared'):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / 'sunshine-access.txt').write_text('enabled\n' if enabled else 'disabled\n')
            trace = base / 'trace'
            trace.touch()
            script = '''set -euo pipefail
BR=deckbr0
command() { [[ $* == '-v firewall-cmd' ]] || builtin command "$@"; }
firewall-cmd() {
    case $1 in
        --state) return 0;;
        --get-zone-of-interface=*) echo "$ZONE"; return 0;;
    esac
    case $2 in
        --query-port=47984/tcp) [[ $EXISTING == yes ]];;
        --query-port=*) return 1;;
        --add-port=*|--remove-port=*) printf '%s\\n' "$*" >>"$TRACE";;
        *) return 2;;
    esac
}
'''
            script += FUNCTIONS + '\nenable_sunshine_access\nclear_sunshine_access\n'
            result = subprocess.run(['bash', '-c', script], text=True, capture_output=True, env={**os.environ, 'DIR': str(base), 'STATE': str(base), 'TRACE': str(trace), 'EXISTING': 'yes' if preexisting else 'no', 'ZONE': zone})
            return result, trace.read_text().splitlines()

    def test_opt_in_restores_and_removes_runtime_ports(self):
        result, trace = self.configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        ports = ['47984/tcp', '47989/tcp', '48010/tcp', '47998-48000/udp']
        self.assertEqual(trace, [f'--zone=nm-shared --add-port={p}' for p in ports] + [f'--zone=nm-shared --remove-port={p}' for p in ports])

    def test_preexisting_rules_are_preserved(self):
        result, trace = self.configure(preexisting=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any('47984/tcp' in line for line in trace))

    def test_disabled_leaves_firewall_alone(self):
        result, trace = self.configure(enabled=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace, [])

    def test_unexpected_zone_is_not_modified(self):
        result, trace = self.configure(zone='public')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(trace, [])


if __name__ == '__main__':
    unittest.main()
