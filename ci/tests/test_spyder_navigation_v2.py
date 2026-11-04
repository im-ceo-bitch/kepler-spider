"""Navigation v2 release gates: guard real routes, wallet/network separation and safe terminal output."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text(encoding='utf-8')

class NavigationV2Tests(unittest.TestCase):
    def test_independent_paths_and_no_modal_control_center(self):
        root = read('Console/WalletRootView.swift')
        for part in ('@State private var walletPath:', '@State private var networkPath:',
                     'NavigationStack(path: $walletPath)', 'NavigationStack(path: $networkPath)',
                     'private var atRoot:', 'if atRoot { bottomBar }'):
            self.assertIn(part, root)
        self.assertNotIn('path = NavigationPath()', root)
        self.assertNotIn('showControlCenter = true', root)

    def test_profile_and_peer_are_push_pages(self):
        root = read('Console/WalletRootView.swift')
        home = read('Console/Features/Chats/ChatsHomeView.swift')
        detail = read('Console/Features/Chats/ChatDetailView.swift')
        hub = read('Console/Features/Settings/SpyderIdentityHubView.swift')
        self.assertIn('networkPath.append(.identity)', root)
        session = read('Console/Features/Chats/SpyderConversationSession.swift')
        self.assertIn('SpyderConversationSession(contact: contact', root)
        self.assertIn('.navigationDestination(isPresented: $showingContact)', session)
        self.assertIn('.environmentObject(session)', session)
        self.assertNotIn('.sheet(isPresented: $showingContact)', session)
        self.assertIn('Button(action: onOpenContact)', detail)
        self.assertIn('Button(action: onProfile)', home)
        self.assertIn('NavigationLink { SpyderProfileEditView() }', hub)
        self.assertNotIn('.sheet(isPresented: $showingPrivacy)', home)
        self.assertNotIn('WalletSettingsView()', hub)

    def test_financial_portal_contains_only_financial_accounts(self):
        portal = read('Console/Features/Wallet/SpyderWalletProfilePage.swift')
        self.assertIn('WalletAccess', portal)
        self.assertIn('WalletChainStore', portal)
        self.assertNotIn('SpyderChatStore', portal)
        self.assertNotIn('WalletVault.revealForBackup', portal)
        self.assertIn('WalletAddressBookView()', read('Console/WalletRootView.swift'))
        self.assertIn('WalletSecurityCenterView()', read('Console/WalletRootView.swift'))

    def test_terminal_motion_is_accessible_and_bounded(self):
        terminal = read('Console/Features/Chats/SpyderChatTerminalView.swift')
        for fragment in ('struct SpyderTerminalOutputLine', 'accessibilityReduceMotion',
                         'isLowPowerModeEnabled', 'fullText.count <= 320',
                         'spyder.terminal.typewriter', 'accessibilityLabel(entry.text)'):
            self.assertIn(fragment, terminal)
        self.assertIn('case "chat.broadcast", "wallet.send":', terminal)

    def test_peer_does_not_claim_unimplemented_features(self):
        peer = read('Console/Features/Chats/SpyderContactProfilePage.swift')
        self.assertIn('peerFingerprints[contact.id]', peer)
        self.assertNotIn('SpyderChatAppearanceSettingsView(', peer)
        self.assertIn('await chat.block(contact.id)', peer)
        self.assertNotIn('В сети сейчас', peer)

if __name__ == '__main__': unittest.main()
