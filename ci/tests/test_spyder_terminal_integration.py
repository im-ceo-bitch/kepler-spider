"""Static regression checks, not a substitute for macOS xcodebuild."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class SpyderTerminalIntegrationTests(unittest.TestCase):
    def test_xcodegen_local_package(self):
        project = (ROOT / "project.yml").read_text()
        self.assertNotIn("SpyderTerminalKit:\n    path: Packages/SpyderTerminalKit", project)
        self.assertNotIn("product: SpyderTerminalKit", project)

    def test_chat_transfer_entry_without_terminal(self):
        chat = (ROOT / "Console/Features/Chats/ChatDetailView.swift").read_text()
        root = (ROOT / "Console/WalletRootView.swift").read_text()
        self.assertNotIn("SpyderChatTerminalView(", chat)
        self.assertIn("onOpenActivity:", root)
        # Transfer is intentionally moved out of the cluttered + menu.
        self.assertIn('Button { openPayment() } label:', chat)
        self.assertIn('.accessibilityLabel("Начать перевод")', chat)
        self.assertIn('.accessibilityIdentifier("spyder.chat.transfer")', chat)
        self.assertIn('SpyderChatPaymentView(', chat)
        self.assertIn('Button("Выбрать сумму") { openPayment(asset: payment.asset) }', chat)

    def test_catalogs_and_safety(self):
        source = ROOT / "Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources"
        ru = json.loads((source / "commands.ru.json").read_text())
        en = json.loads((source / "commands.en.json").read_text())
        self.assertEqual({x['id'] for x in ru}, {x['id'] for x in en})
        for lang, commands in [('ru', ru), ('en', en)]:
            self.assertGreaterEqual(len(commands), 28)
            self.assertEqual(len({c["id"] for c in commands}), len(commands))
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
