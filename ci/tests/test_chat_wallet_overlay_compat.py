"""Cross-patch compatibility: Chat Unified + Wallet LIVE Dual Theme."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

class ChatWalletOverlayCompatibility(unittest.TestCase):
    def test_chat_push_delegate_and_token_observer_remain_connected(self):
        app = read("Console/ConsoleApp.swift")
        delegate = read("Console/ChatLive/SpyderPushAppDelegate.swift")
        self.assertIn('@UIApplicationDelegateAdaptor(SpyderPushAppDelegate.self)', app)
        self.assertIn('NotificationCenter.default.publisher(for: .spyderChatDeviceToken)', app)
        self.assertIn('spyderChat.registerPushToken(token)', app)
        self.assertIn('registerForRemoteNotifications()', app)
        self.assertIn('spyderChatOpenRequested', delegate)

    def test_push_open_route_survives_wallet_overlay(self):
        root = read("Console/WalletRootView.swift")
        self.assertIn('openChatAfterNotificationIfNeeded()', root)
        self.assertIn('selectedTab = .chats', root)
        self.assertIn('WalletReceiveView(preselected: sendChain ?? .ethereum)', root)

    def test_live_market_environment_and_lifecycle_survive_chat_overlay(self):
        app = read("Console/ConsoleApp.swift")
        for fragment in ('WalletMarketStore()', 'WalletLiveMarketStore()',
                         '.environmentObject(marketData)', '.environmentObject(liveMarket)',
                         'await liveMarket.run()', 'liveMarket.stop()',
                         'publicAssets.applyMarketQuotes(quotes)'):
            self.assertIn(fragment, app)

    def test_unified_chat_routing_works_without_replacing_messagechain(self):
        index = read("server/src/index.mjs")
        self.assertIn('export { SpyderMessageRoom, ChatHub }', index)
        self.assertIn("if (url.pathname.startsWith('/v1/conversations/'))", index)
        self.assertIn("url.pathname === '/chat/health'", index)

if __name__ == '__main__':
    unittest.main()
