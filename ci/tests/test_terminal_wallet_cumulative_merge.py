"""CI gate for Wallet Control Center + E2EE Terminal v2 integration."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
class TerminalWalletCumulativeMergeTests(unittest.TestCase):
    def test_control_center_and_terminal_routing_coexist(self):
        root=read('Console/WalletRootView.swift')
        for token in ('SpyderWalletProfilePage(', 'onControlCenter:', 'case .security:',
                      'WalletSecurityCenterView()', 'case .addressBook:',
                      'WalletAddressBookView()', 'onOpenActivity:',
                      'SpyderConversationSession(contact: contact', 'SpyderIdentityHubView()',
                      'openChatAfterNotificationIfNeeded()', '.spyderChatOpenRequested',
                      'NavigationStack(path: $walletPath)', 'NavigationStack(path: $networkPath)'):
            self.assertIn(token,root)
        session=read('Console/Features/Chats/SpyderConversationSession.swift')
        self.assertIn('ChatDetailView(contact: contact',session)
        self.assertIn('.environmentObject(session)',session)
        self.assertNotIn('WalletControlCenterView(', root)
        self.assertNotIn('SpyderTerminalSettingsScreen()',
                      read('Console/Features/Settings/SpyderIdentityHubView.swift'))
    def test_terminal_package_in_xcodegen(self):
        project=read('project.yml')
        for token in ('product: WalletCore','Features/Chats/SpyderChatTerminalView.swift','excludes:'):
            self.assertIn(token,project)
    def test_terminal_ui_available_in_chats_and_settings(self):
        self.assertNotIn('SpyderChatTerminalView(',read('Console/Features/Chats/ChatDetailView.swift'))
        self.assertNotIn('SpyderTerminalSettingsScreen()',read('Console/Features/Settings/SpyderIdentityHubView.swift'))
        self.assertIn('struct SpyderChatTerminalView',read('Console/Features/Chats/SpyderChatTerminalView.swift'))
    def test_market_and_chat_preserved(self):
        self.assertIn('WalletCatalogSection(catalog: catalog)',read('Console/Features/Wallet/WalletHomeView.swift'))
        self.assertIn('WalletLiveMarket',read('Console/WalletCore/WalletLiveMarket.swift'))
        self.assertIn('class SpyderChatStore',read('Console/ChatLive/SpyderChatService.swift'))
        self.assertTrue((ROOT/'server/src/chat.mjs').exists())
if __name__=='__main__': unittest.main()
