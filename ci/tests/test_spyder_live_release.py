"""Release regression checks compatible with Spyder Wallet Blocks 1–4.

Keep this test focused on *observable safety properties* rather than naming an
obsolete view. Mainnet send remains preview-only until independently audited.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LiveReleaseChecks(unittest.TestCase):
    def test_chat_onboarding_never_requests_server_address(self):
        chat = source('Console/Features/Chats/ChatsHomeView.swift')
        setup = chat.split('private var setup:', 1)[1].split('private var inviteSheet:', 1)[0]
        self.assertNotIn('TextField("https://', setup)
        self.assertNotIn('text: $chat.serverAddress', setup)
        self.assertIn('chat.register(name: name, username: username)', setup)

    def test_public_address_cache_contains_no_secret_phrase(self):
        chains = source('Console/WalletCore/WalletChains.swift')
        self.assertIn('spyder.wallet.publicAddresses.v1', chains)
        self.assertIn('JSONEncoder().encode(resolved)', chains)
        self.assertNotIn('UserDefaults.standard.set(phrase', chains)

    def test_spider_devnet_is_absent_or_explicitly_gated(self):
        home = source('Console/Features/Wallet/WalletHomeView.swift')
        body = home.split('var body: some View {', 1)[1].split('private var spiderSection:', 1)[0]
        if 'spiderSection' in body:
            # A configured test chain may be shown directly or inside a closed-by-default disclosure.
            self.assertRegex(body, r'if\s+spider\.hasConfiguration\s*\{')
            self.assertTrue(
                re.search(r'if\s+spider\.hasConfiguration\s*\{\s*spiderSection\b', body)
                or re.search(r'if\s+spider\.hasConfiguration\s*\{\s*DisclosureGroup\([^)]*\)\s*\{\s*spiderSection\b', body),
                'Devnet is accessible only when explicitly configured'
            )
        self.assertNotIn('WalletDemoLabel()', body)

    def test_mainnet_send_preview_cannot_broadcast(self):
        root = source('Console/WalletRootView.swift')
        flow = source('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertRegex(root, r'case\s+\.send:\s*WalletSendFlowView\(preselected:\s*sendChain\)')
        self.assertIn('showUnavailable = true', flow)
        self.assertIn('Отправка пока недоступна', flow)
        self.assertIn('Отправка ещё не включена', flow)
        # Do not mistake a visible send form for a complete signing engine.
        for api in ('eth_sendRawTransaction', 'sendRawTransaction', 'sendTransaction',
                    'sendAndConfirmTransaction', 'broadcastTransaction', 'URLSession.shared.data(for:'):
            self.assertNotIn(api, flow, f'Mainnet preview unexpectedly references {api}')
        self.assertIn('.disabled(!validToReview)', flow)

    def test_market_prices_include_tokens_and_partial_banner(self):
        market = source('Console/WalletCore/WalletPublicAssets.swift')
        self.assertIn('tether,usd-coin', market)
        self.assertIn('var isPartialEstimate: Bool', market)
        self.assertIn('stablecoinPrices[ticker]', market)

    def test_chat_backend_enforces_authentication(self):
        server = source('server/src/index.mjs')
        self.assertIn("if(!me)return bad('unauthorized',401)", server)
        self.assertIn('username_taken', server)
        self.assertIn('not_contacts', server)


if __name__ == '__main__':
    unittest.main()
