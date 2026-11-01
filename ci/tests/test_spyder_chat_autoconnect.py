"""Regression gates: keep public Chat v2 endpoint, refresh and APNs opt-in safe."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def source(name): return (ROOT / name).read_text(encoding='utf-8')

class ChatAutoconnectTests(unittest.TestCase):
    def test_fallback_endpoint_and_identity_binding(self):
        src = source('Console/ChatLive/SpyderChatEndpoint.swift')
        self.assertIn('https://kepler-spider.helloiumrah.workers.dev', src)
        self.assertIn('normalized(identity) ?? normalized(bundled)', src)
        self.assertIn('parts.scheme?.lowercased() == "https"', src)

    def test_service_preserves_keys_and_push_optin(self):
        src = source('Console/ChatLive/SpyderChatService.swift')
        self.assertIn('SpyderChatEndpoint.resolve(identity: identity?.server', src)
        self.assertIn('lastPushToken', src)
        self.assertIn('lastRegisteredPushToken != token', src)
        self.assertIn('guard pushEnabled, hasIdentity, hasConfiguredServer', src)
        self.assertIn('private static let serverKey', src)

    def test_pull_refresh_and_foreground_poll(self):
        src = source('Console/Features/Chats/ChatsHomeView.swift')
        self.assertIn('.refreshable {', src)
        self.assertIn('.task(id: scenePhase) {', src)
        self.assertNotIn('Image(systemName: "arrow.clockwise")', src)
        self.assertIn('await chat.refresh()', src)

    def test_preserves_live_market_in_app(self):
        src = source('Console/ConsoleApp.swift')
        self.assertIn('WalletMarketStore()', src)
        self.assertIn('WalletLiveMarketStore()', src)
        self.assertIn('.environmentObject(liveMarket)', src)
        self.assertIn('Task { await spyderChat.refresh() }', src)

if __name__ == '__main__': unittest.main()
