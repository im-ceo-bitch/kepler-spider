"""Keep Safari WebExtension icons portable through Xcode resource copying."""
import json
from pathlib import Path
import re
import struct
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / 'Extensions/SpyderSafari/Resources'


class SafariPNGResourcesTests(unittest.TestCase):
    def test_safari_target_is_not_in_host_only_release(self):
        spec = (ROOT / 'project.yml').read_text()
        for name in ('SpyderSafari', 'SpyderAutoFill', 'SpyderShare'):
            self.assertNotRegex(spec, rf'(?m)^  {name}:\s*$')
            self.assertNotRegex(spec, rf'(?m)^\s*- target: {name}\s*$')
        self.assertNotIn('type: app-extension', spec)
        self.assertIn('path: Shared/SpyderID', spec)

    def test_manifest_icons_match_archive_preflight(self):
        manifest = json.loads((RES / 'manifest.json').read_text())
        self.assertEqual(set(manifest['icons']), {'48', '96', '128'})
        for size, name in manifest['icons'].items():
            with self.subTest(size=size):
                self.assertEqual(Path(name).name, name)
                data = (RES / name).read_bytes()
                self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
                self.assertEqual(data[8:16], b'\x00\x00\x00\rIHDR')
                self.assertEqual(struct.unpack('>II', data[16:24]), (int(size), int(size)))
                pos = 8
                chunks = []
                while pos < len(data):
                    length, = struct.unpack_from('>I', data, pos)
                    end = pos + 12 + length
                    self.assertLessEqual(end, len(data))
                    chunk = data[pos+4:pos+8+length]
                    crc, = struct.unpack_from('>I', data, pos+8+length)
                    self.assertEqual(zlib.crc32(chunk) & 0xffffffff, crc)
                    chunks.append(chunk[:4])
                    pos = end
                self.assertEqual(chunks[-1], b'IEND')
                self.assertIn(b'IDAT', chunks)
                self.assertNotIn(b'CgBI', chunks)


if __name__ == '__main__':
    unittest.main()
