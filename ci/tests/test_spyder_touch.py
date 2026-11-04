from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import plistlib

ROOT = Path(__file__).resolve().parents[2]

class SpyderTouchTests(unittest.TestCase):
    def test_release_framing(self):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory() as folder:
            exe = str(Path(folder) / 'touch')
            built = subprocess.run([swift, '-swift-version', '5',
                str(ROOT / 'Console/Features/Touch/SpyderTouchFrame.swift'),
                str(ROOT / 'ci/tests/spyder_touch_frame_driver.swift'), '-o', exe],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            run = subprocess.run([exe], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('Touch framing checks passed', run.stdout)

    def test_local_network_disclosure(self):
        with (ROOT / 'Config/Console-Info.plist').open('rb') as f:
            config = plistlib.load(f)
        self.assertIn('_spyder-touch2._tcp', config['NSBonjourServices'])
        self.assertTrue(config['NSLocalNetworkUsageDescription'].strip())
        self.assertTrue(config['NSNearbyInteractionUsageDescription'].strip())

    def test_touch_reachable_and_no_demo(self):
        invite = (ROOT / 'Console/Features/Chats/SpyderInvitePage.swift').read_text()
        view = (ROOT / 'Console/Features/Touch/WalletTouchView.swift').read_text()
        self.assertIn('WalletTouchView', invite)
        self.assertNotIn('WalletContact.samples', view)
        self.assertNotIn('simulationActive', view)
        self.assertIn('await chat.invite(code)', view)
        self.assertNotIn('touch.connect(device)', view)

    def test_release_proximity_gate_swift5(self):
        self.run_proximity('5')

    def test_release_proximity_gate_swift6(self):
        self.run_proximity('6')

    def run_proximity(self, language):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory() as folder:
            exe = str(Path(folder) / 'proximity')
            result = subprocess.run([swift, '-swift-version', language,
                str(ROOT / 'Console/Features/Touch/SpyderTouchProximityGate.swift'),
                str(ROOT / 'ci/tests/spyder_touch_proximity_driver.swift'), '-o', exe],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([exe], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Touch proximity checks passed', result.stdout)
