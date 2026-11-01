"""Static safety regression checks; Xcode build remains the release gate."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOTION = ROOT / 'Console' / 'Design' / 'MotionKit'


class SpyderMotionKitTests(unittest.TestCase):
    def test_twelve_animation_preset_names(self):
        body = (MOTION / 'SpyderMotionPreferences.swift').read_text()
        section = body.split('enum SpyderAvatarMotion:', 1)[1].split('var id:', 1)[0]
        cases = re.findall(r'^\s*case\s+([\w, ]+)', section, flags=re.MULTILINE)
        names = [v.strip() for line in cases for v in line.split(',')]
        self.assertEqual(len(names), 12)
        self.assertEqual(len(set(names)), 12)

    def test_compatible_integration_points(self):
        app = (ROOT / 'Console' / 'ConsoleApp.swift').read_text()
        settings = (ROOT / 'Console' / 'Features/Settings/WalletSettingsView.swift').read_text()
        self.assertIn('SpyderBrandHandoff(', app)
        self.assertIn('SpyderMotionSettingsView()', settings)
        self.assertIn('SpyderProfileAvatarView(', settings)
        self.assertIn('!introSeen', app)
        self.assertIn('onSkip: { showingBrand = false }', app)

    def test_eye_is_based_on_user_native_canvas(self):
        eye = (MOTION / 'NativeEyeAnimationView.swift').read_text()
        self.assertIn('horizontalGaze(at: phase)', eye)
        self.assertIn('blinkAmount(at: phase)', eye)
        self.assertIn('Image("SpyderEyeGlyph")', eye)
        self.assertIn('accessibilityReduceMotion', eye)

    def test_logo_uses_real_alpha_mask_and_is_bounded(self):
        source = (MOTION / 'SpyderParticleLogoView.swift').read_text()
        self.assertIn('UIImage(named: "SpyderLaunchLogo")', source)
        self.assertIn('prefix(1_200)', source)
        self.assertIn('(!loops && completed)', source)
        self.assertNotIn('Timer.scheduledTimer', source)
        self.assertTrue((ROOT / 'Console/Resources/Assets.xcassets/SpyderEyeGlyph.imageset/SpiderEyeGlyph.png').is_file())

    def test_source_of_truth_no_secret_access(self):
        for source in MOTION.glob('*.swift'):
            text = source.read_text()
            self.assertNotIn('WalletVault', text)
            self.assertNotIn('UserDefaults.standard.set(', text)
            self.assertNotIn('WalletAccess', text)


if __name__ == '__main__':
    unittest.main()
