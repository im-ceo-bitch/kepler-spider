"""Native Originals / wire compatibility regression checks. Xcode build is still required."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ORIGINALS = ROOT / 'Console/Features/Chats/SpyderOriginals.swift'
CHAT = ROOT / 'Console/Features/Chats/ChatDetailView.swift'
SERVICE = ROOT / 'Console/ChatLive/SpyderChatService.swift'


class SpyderOriginalsTests(unittest.TestCase):
    def test_eight_unique_serialized_originals_and_no_remote_assets(self):
        text = ORIGINALS.read_text()
        self.assertIn('case watcher, blink, threat, webDrop, crawl, phantom, webCast, retreat', text)
        self.assertIn('spyder:originals:v1:', text)
        self.assertIn('return Self(rawValue: String(message.dropFirst(prefix.count)))', text)
        self.assertNotIn('URLSession', text)
        self.assertNotIn('WKWebView', text)
        self.assertIn('import SceneKit', text)
        self.assertIn('!reduceMotion', text)
        self.assertIn('isLowPowerModeEnabled', text)
        self.assertIn('view.isPlaying = false', text)

    def test_chat_uses_existing_encrypted_send_and_does_not_delete_draft(self):
        chat = CHAT.read_text()
        service = SERVICE.read_text()
        self.assertIn('SpyderOriginalsPicker(canSend:', chat)
        self.assertIn('SpyderOriginal.decode(message.text)', chat)
        self.assertIn('transmit(original.payload, clearDraft: false)', chat)
        self.assertIn('if clearDraft && draft.trimmingCharacters(in: .whitespacesAndNewlines) == content {', chat)
        self.assertIn('await chat.sendMessage(to: contact.id, text: content)', chat)
        self.assertIn('await chat.sendNextMessage(to: contact.id, text: content, personaID: persona)', chat)
        self.assertIn('SpyderMessageCrypto.seal(clean', service)
        self.assertIn('SpyderOriginal.decode(text).map', service)

    def test_wire_codec_compiles_and_rejects_unknown_or_partial_codes(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler not available')
        source = ORIGINALS.read_text().split('enum SpyderOriginal:', 1)[1].split('/// GPU-rendered', 1)[0]
        with tempfile.TemporaryDirectory(prefix='spyder-originals-codec-') as tmp:
            swift = Path(tmp) / 'main.swift'
            swift.write_text('''import Foundation
            enum SpyderOriginal:''' + source + '''
            assert(SpyderOriginal.allCases.count == 8)
            for item in SpyderOriginal.allCases {
                assert(SpyderOriginal.decode(item.payload) == item)
            }
            assert(SpyderOriginal.decode("spyder:originals:v1:unknown") == nil)
            assert(SpyderOriginal.decode("spyder:originals:v1:watcher more") == nil)
            assert(SpyderOriginal.decode("Spyder Originals") == nil)
            assert(SpyderOriginal.decode("spyder:originals:v2:watcher") == nil)
            print("Wire codec OK")
            ''')
            exe = Path(tmp) / 'codec'
            build = subprocess.run(['swiftc', str(swift), '-o', str(exe)], capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stderr)
            check = subprocess.run([str(exe)], capture_output=True, text=True, timeout=20)
            self.assertEqual(check.returncode, 0, check.stderr)
            self.assertIn('Wire codec OK', check.stdout)


if __name__ == '__main__':
    unittest.main()
