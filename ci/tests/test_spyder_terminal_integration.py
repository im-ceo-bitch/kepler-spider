"""Static regression checks, not a substitute for macOS xcodebuild."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class SpyderTerminalIntegrationTests(unittest.TestCase):
    def test_xcodegen_local_package(self):
        project = (ROOT / "project.yml").read_text()
        self.assertIn("SpyderTerminalKit:\n    path: Packages/SpyderTerminalKit", project)
        self.assertIn("- package: SpyderTerminalKit\n        product: SpyderTerminalKit", project)

    def test_active_chat_routed_to_terminal(self):
        chat = (ROOT / "Console/Features/Chats/ChatDetailView.swift").read_text()
        root = (ROOT / "Console/WalletRootView.swift").read_text()
        bridge = (ROOT / "Console/Features/Chats/SpyderTerminalChatContainer.swift").read_text()
        shell = (ROOT / "Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalChatShell.swift").read_text()
        self.assertIn("SpyderTerminalChatContainer(contact: contact", root)
        self.assertIn("onOpenActivity:", root)
        self.assertIn("SpyderChatTerminalSwitchView(", bridge)
        self.assertIn("ChatDetailView(contact: contact", bridge)
        self.assertIn(".pickerStyle(.segmented)", shell)

    def test_catalogs_and_safety(self):
        source = ROOT / "Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources"
        ru = json.loads((source / "commands.ru.json").read_text())
        en = json.loads((source / "commands.en.json").read_text())
        self.assertEqual({x['id'] for x in ru}, {x['id'] for x in en})
        for lang, commands in [('ru', ru), ('en', en)]:
            self.assertGreaterEqual(len(commands), 30)
            themes = next(c for c in commands if c['id'] == 'chat.theme.set')
            prefix = 'сп' if lang == 'ru' else 'sp'
            self.assertTrue(any(x.startswith(prefix) for x in themes['standard']))
        view = (ROOT / 'Console/Features/Chats/SpyderChatTerminalView.swift').read_text()
        self.assertIn('case "chat.broadcast", "wallet.send":', view)
        self.assertIn('onAction(.receive)', view)
        self.assertIn('await chat.sendMessage(to: contact.id', view)
        self.assertIn('privacyHidden', view)

if __name__ == '__main__':
    unittest.main()
