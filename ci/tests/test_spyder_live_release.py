"""Release regressions for wallet routes and supported transfer boundaries.

Mainnet generic/manual transfers remain preview-only. A reviewed USDT ERC-20
transfer can only be sent to verified chat-recipient credentials after an
explicit confirmation and authorization. The tests guard that distinction.
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
        self.assertRegex(setup, r'chat\.register\(name: name, username: username(?:, discoverable: visibleInSearch)?\)')

    def test_public_address_cache_contains_no_secret_phrase(self):
        chains = source('Console/WalletCore/WalletChains.swift')
        self.assertIn('spyder.wallet.publicAddresses.v1', chains)
        self.assertIn('JSONEncoder().encode(resolved)', chains)
        self.assertNotIn('UserDefaults.standard.set(phrase', chains)

    def test_spider_devnet_is_absent_or_explicitly_gated(self):
        home = source('Console/Features/Wallet/WalletHomeView.swift')
        body = home.split('var body: some View {', 1)[1].split('private var spiderSection:', 1)[0]
        if 'spiderSection' in body:
            # Stage 2 additionally requires the portfolio view to be selected.
            # Devnet stays closed by default, even when the backend is configured.
            self.assertIn('@State private var showDevnet = false', home)
            self.assertRegex(body, r'if\s+selectedSection\s*==\s*WalletHomeSection\.assets\.rawValue\s*&&\s*spider\.hasConfiguration\s*\{\s*DisclosureGroup\(isExpanded:\s*\$showDevnet\)\s*\{\s*spiderSection')
        self.assertNotIn('WalletDemoLabel()', body)

    def test_mainnet_ui_has_no_direct_broadcaster_and_requires_review(self):
        root = source('Console/WalletRootView.swift')
        flow = source('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertRegex(root, r'case\s+\.send:\s*WalletSendFlowView\(preselected:\s*sendChain\)')
        # Manual-address and other coins are preview-only. The ONLY active
        # transfer needs verified in-chat USDT credentials and a separate confirm.
        self.assertIn('guard let context = chatRecipient, context.payment.asset == .usdtEthereum,', flow)
        self.assertIn('WalletEthereumSignature.verifyOwnership(', flow)
        self.assertIn('else if canSendUSDT { confirmUSDT = true }', flow)
        self.assertIn('Button("Подтвердить через Face ID / код") { sendUSDT() }', flow)
        self.assertIn('guard canSendUSDT, !transfers.busy', flow)
        self.assertIn('Это предпросмотр. Отправка выбранного актива здесь недоступна.', flow)
        self.assertIn('Подтвердить и отправить USDT', flow)
        # Do not mistake a visible send form for a complete signing engine.
        for api in ('eth_sendRawTransaction', 'sendRawTransaction', 'sendTransaction',
                    'sendAndConfirmTransaction', 'broadcastTransaction', 'URLSession.shared.data(for:'):
            self.assertNotIn(api, flow, f'Mainnet preview unexpectedly references {api}')
        self.assertIn('.disabled(transfers.busy || (submitted == nil && (!reviewing && (!validToReview || quoteLoading))))', flow) # prevent quoting when invalid or still loading

    def test_market_prices_include_tokens_and_partial_banner(self):
        market = source('Console/WalletCore/WalletPublicAssets.swift')
        self.assertIn('tether,usd-coin', market)
        self.assertIn('var isPartialEstimate: Bool', market)
        self.assertIn('stablecoinPrices[ticker]', market)

    def test_chat_backend_enforces_authentication(self):
        router = source('server/src/index.mjs')
        server = source('server/src/chat.mjs')
        self.assertIn("import chatWorker, { ChatHub } from './chat.mjs'", router)
        self.assertIn("if(!me)return bad('unauthorized',401)", server)
        self.assertIn('username_taken', server)
        self.assertIn('not_contacts', server)


if __name__ == '__main__':
    unittest.main()
