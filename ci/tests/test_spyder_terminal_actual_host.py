"""Integration guards for authenticated real actions. Not an iOS build substitute."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(name): return (ROOT / name).read_text()
class ActualTerminalHostChecks(unittest.TestCase):
    def test_dictionaries_match_and_message_is_sensitive(self):
        ru = json.loads(read('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources/commands.ru.json'))
        en = json.loads(read('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources/commands.en.json'))
        self.assertEqual({x['id']: x['risk'] for x in ru}, {x['id']: x['risk'] for x in en})
        self.assertEqual(next(x for x in ru if x['id'] == 'chat.send')['risk'], 'sensitive')
        self.assertIn('сп измени тему на {theme}', next(x for x in ru if x['id'] == 'chat.theme.set')['standard'])
        self.assertIn('sp change theme to {theme}', next(x for x in en if x['id'] == 'chat.theme.set')['standard'])
    def test_real_host_uses_current_chat_and_data(self):
        code = read('Console/Features/Chats/SpyderTerminalChatContainer.swift')
        self.assertIn('request.context.conversationID == peerID', code)
        self.assertIn('Декоративные фоны отключены', code)
        self.assertNotIn('SpyderChatAppearanceStore.save(appearance, peer: peerID, persona: chat.activePersonaID)', code)
        self.assertIn('chat.contacts.contains(where: { $0.id == peerID })', code)
        self.assertIn('await chat.sendMessage(to: peerID, text: message)', code)
        self.assertIn('review: { [weak chat] request in', code)
        self.assertIn('spyder.wallet.privacyHidden', code)
        self.assertNotIn('host.register("wallet.send"', code)
        self.assertNotIn('host.register("chat.broadcast"', code)
        self.assertIn('onOpenActivity()', code)
        self.assertIn('onAction(.receive)', code)
    def test_root_and_address_book_wiring(self):
        root = read('Console/WalletRootView.swift')
        app = read('Console/ConsoleApp.swift')
        self.assertIn('onControlCenter: {', root)
        # Financial access now lives on a real NavigationStack page, not a fullScreenCover.
        self.assertIn('SpyderWalletProfilePage(', root)
        self.assertIn('NavigationStack(path: $walletPath)', root)
        self.assertIn('NavigationStack(path: $networkPath)', root)
        self.assertNotIn('WalletControlCenterView(', root)
        self.assertIn('case .security:', root)
        self.assertIn('case .addressBook:', root)
        self.assertIn('.environmentObject(addressBook)', app)
        self.assertIn('addressBook.selectWallet(id)', app)
    def test_sensitive_scrollback_redacted(self):
        shell = read('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalChatShell.swift')
        self.assertIn('match.risk == .sensitive', shell)
        self.assertIn('"[protected: " + match.commandID', shell)
if __name__ == '__main__': unittest.main()
