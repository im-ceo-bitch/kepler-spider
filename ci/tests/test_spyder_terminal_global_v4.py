"""Regression checks for the global terminal route and fail-closed action registry."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path): return (ROOT / path).read_text()

class GlobalTerminalChecks(unittest.TestCase):
    def test_root_global_entry_is_real_tab(self):
        root = read("Console/WalletRootView.swift")
        model = read("Console/Models/WalletModels.swift")
        self.assertIn("case wallet, chats, terminal", model)
        self.assertIn("case .terminal:", root)
        self.assertIn("SpyderGlobalTerminalView(onAction:", root)
        self.assertIn('tabButton(.terminal, title: "Терминал"', root)
        self.assertIn("SpyderTerminalChatContainer(contact: contact", root)

    def test_global_host_fails_closed_and_does_not_sign(self):
        global_view = read("Console/Features/Chats/SpyderGlobalTerminalView.swift")
        self.assertIn("guard request.context.conversationID == nil", global_view)
        self.assertIn("privacyHidden", global_view)
        self.assertNotIn('host.register("wallet.send"', global_view)
        self.assertNotIn('host.register("chat.broadcast"', global_view)
        self.assertNotIn('host.register("chat.send"', global_view)
        self.assertNotIn('host.register("chat.theme.set"', global_view)
        self.assertIn("showsChatSwitch: false", global_view)

    def test_parser_only_offers_real_actions(self):
        kit = read("Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalChatShell.swift")
        input_view = read("Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalViews.swift")
        host = read("Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalActionRegistryHost.swift")
        self.assertIn("availableCommands: { supportedCommands() }", kit)
        self.assertIn("availableCommandIDs: availableCommands()", input_view)
        self.assertIn("public var availableCommandIDs", host)

    def test_dictionary_parity_and_sensitive_risk(self):
        directory = "Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources/"
        ru, en = (json.loads(read(directory + "commands." + lang + ".json")) for lang in ("ru", "en"))
        self.assertEqual({x["id"]: x["risk"] for x in ru}, {x["id"]: x["risk"] for x in en})
        self.assertGreaterEqual(len(ru), 35)
        self.assertEqual(next(x for x in ru if x["id"] == "wallet.send")["risk"], "sensitive")
        self.assertEqual(next(x for x in en if x["id"] == "chat.broadcast")["risk"], "sensitive")

if __name__ == "__main__": unittest.main()
