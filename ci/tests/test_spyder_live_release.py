"""Regression gates for the release UX and server-connected TestFlight flow."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]

def source(path): return (ROOT/path).read_text(encoding="utf-8")

class LiveReleaseChecks(unittest.TestCase):
    def test_chat_onboarding_never_requests_server_address(self):
        chat=source('Console/Features/Chats/ChatsHomeView.swift')
        setup=chat.split('private var setup:',1)[1].split('private var inviteSheet:',1)[0]
        self.assertNotIn('TextField("https://',setup)
        self.assertNotIn('text: $chat.serverAddress',setup)
        self.assertRegex(setup, r'chat\.register\(name: name, username: username(?:, discoverable: visibleInSearch)?\)')

    def test_public_address_cache_contains_no_secret_phrase(self):
        chains=source('Console/WalletCore/WalletChains.swift')
        self.assertIn('spyder.wallet.publicAddresses.v1',chains)
        self.assertIn('JSONEncoder().encode(resolved)',chains)
        self.assertNotIn('UserDefaults.standard.set(phrase',chains)

    def test_devnet_only_shown_when_explicitly_configured(self):
        home = source('Console/Features/Wallet/WalletHomeView.swift')
        self.assertRegex(home, r'if spider\.hasConfiguration\s*\{\s*DisclosureGroup\(isExpanded: \$showDevnet\)')
        self.assertIn('spiderSection', home)
        self.assertNotIn('WalletDemoLabel()', home)

    def test_mainnet_transfer_stays_non_broadcasting(self):
        root = source('Console/WalletRootView.swift')
        flow = source('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertIn('case .send:\n            WalletSendFlowView(preselected: sendChain)', root)
        self.assertIn('case .devnetTransfer:', root)
        self.assertIn('Mainnet', flow)
        self.assertNotIn('eth_sendRawTransaction', flow)
        self.assertNotIn('sendTransaction', flow)

    def test_market_prices_include_tokens_and_partial_banner(self):
        market=source('Console/WalletCore/WalletPublicAssets.swift')
        self.assertIn('tether,usd-coin',market)
        self.assertIn('var isPartialEstimate: Bool',market)
        self.assertIn('stablecoinPrices[ticker]',market)

    def test_chat_backend_enforces_authentication(self):
        router=source('server/src/index.mjs')
        self.assertIn("import chatWorker, { ChatHub } from './chat.mjs'",router)
        server=source('server/src/chat.mjs')
        self.assertIn('if(!me)return bad(\'unauthorized\',401)',server)
        self.assertIn('username_taken',server)
        self.assertIn('not_contacts',server)

if __name__=='__main__': unittest.main()
