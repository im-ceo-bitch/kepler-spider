"""P3 source regression gates for transaction status and user recovery.

Structural checks, not a replacement for Xcode builds or device-based UX review.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def swift(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

class P3TransactionUXChecks(unittest.TestCase):
    def test_usdt_confirmation_is_single_attempt_per_screen(self):
        flow = swift('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertIn('@State private var sendAttempted = false', flow)
        self.assertIn('guard canSendUSDT, !transfers.busy, !sendAttempted', flow)
        self.assertIn('sendAttempted = true\n            submissionPending = true\n            Task {', flow)
        self.assertIn('submissionPending = false', flow)
        self.assertIn('recipientContextValid, submitted == nil, !sendAttempted', flow)
        self.assertIn('else if canSendUSDT { confirmUSDT = true }', flow)
        self.assertIn('Button("Подтвердить через Face ID / код") { sendUSDT() }', flow)

    def test_uncertain_real_transfer_does_not_reset_into_send(self):
        flow = swift('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertIn('if sendAttempted && submitted == nil && !submissionPending {', flow)
        self.assertIn('Результат отправки неизвестен.', flow)
        self.assertIn('if submitted != nil || sendAttempted { dismiss() }', flow)
        self.assertNotIn('                else { clearQuote() }\n            }\n        } catch', flow)
        self.assertIn('walletID == walletID && $0.intent == intent', flow)
        self.assertIn('Это предпросмотр. Отправка выбранного актива здесь недоступна.', flow)

    def test_transaction_status_remains_interactive_after_submission(self):
        flow = swift('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertIn('if let submitted {\n                        WalletCard {\n                            SpyderTransferStatusView', flow)
        self.assertNotIn('.disabled(transfers.busy || submitted != nil)', flow)
        self.assertIn('chatRecipient == nil ? "Готово" : "Вернуться в чат"', flow)

    def test_devnet_ambiguous_send_blocks_repeat_and_preserves_exit(self):
        transfer = swift('Console/Features/Wallet/WalletTransferView.swift')
        self.assertIn('@State private var didAttempt = false', transfer)
        self.assertIn('didAttempt = true\n                    Task {', transfer)
        self.assertIn('if didAttempt && !didSubmit && !isSubmitting {', transfer)
        self.assertIn('else if didAttempt { dismiss() }', transfer)
        self.assertIn('Не повторяйте перевод до проверки статуса сети.', transfer)
        self.assertIn('isSubmitting || spider.sending || (!didSubmit && !didAttempt && !canContinue)', transfer)
        self.assertIn('.interactiveDismissDisabled(isSubmitting || spider.sending)', transfer)
        self.assertIn('Подписать и отправить тестовые SPD', transfer)

    def test_receiving_reconfirms_after_verified_address_changes(self):
        receive = swift('Console/Features/Wallet/WalletTransferView.swift')
        self.assertIn('.onChange(of: verifiedAddress) { previous, current in', receive)
        self.assertIn('guard previous != current else { return }', receive)
        self.assertIn('acknowledged = false', receive)
        self.assertIn('copied = false', receive)
        self.assertIn('if phase != .active { copied = false }', receive)
        self.assertIn('chains.verifiedForReceiving', receive)

    def test_status_refresh_never_republishes_transfer(self):
        status = swift('Console/Features/Chats/SpyderTransferStatusView.swift')
        self.assertIn('Button("Повторить проверку") { retryCount += 1 }', status)
        self.assertIn('Text(checking ? "Проверяем статус…" : "Обновить статус")', status)
        self.assertIn('let result = try await WalletEVMOutgoingTracker().reconcile', status)
        self.assertIn('case .confirmed, .reverted: return true', status)
        self.assertNotIn('transfers.send(', status)
        self.assertNotIn('publish(', status)

if __name__ == '__main__':
    unittest.main()
