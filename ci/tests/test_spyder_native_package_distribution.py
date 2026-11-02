"""Check real package data and linkage declarations; this is not a Swift/iOS compilation."""
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / 'Packages/SpyderNativeCollection'

class NativePackageDistributionTests(unittest.TestCase):
    def test_uploaded_vector_data_passes_native_package_validator(self):
        result = subprocess.run([sys.executable, str(PACKAGE / 'Tools/validate_package.py')],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_resource_manifest_and_every_distributed_checksum(self):
        manifest = (PACKAGE / 'Package.swift').read_text()
        self.assertIn('resources: [.process("Resources")]', manifest)
        checksums = {}
        for line in (PACKAGE / 'SHA256SUMS.txt').read_text().splitlines():
            digest, relative = line.split('  ', 1)
            path = Path(relative)
            self.assertFalse(path.is_absolute())
            self.assertNotIn('..', path.parts)
            self.assertEqual(hashlib.sha256((PACKAGE / path).read_bytes()).hexdigest(), digest, relative)
            checksums[relative] = digest
        self.assertIn('Sources/SpyderNativeCollection/Resources/artworks.json', checksums)
        self.assertIn('Sources/SpyderNativeCollection/SpyderChatBackground.swift', checksums)

    def test_local_package_product_declared_for_app_and_app_tests(self):
        spec = (ROOT / 'project.yml').read_text()
        self.assertIn('path: Packages/SpyderNativeCollection', spec)
        app, tests = spec.split('  ConsoleTests:', 1)
        self.assertIn('product: SpyderNativeCollection', app)
        self.assertIn('product: SpyderNativeCollection', tests)

if __name__ == '__main__':
    unittest.main()
