#!/usr/bin/env python3
"""Stage 3 code-level UX and transfer safety guards (not a substitute for Xcode runtime tests)."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
def read(p): return (r / p).read_text()
send = read('Console/Features/Wallet/WalletSendFlowView.swift')
receive = read('Console/Features/Wallet/WalletTransferView.swift')
touch = read('Console/Features/Touch/WalletTouchView.swift')
payment = read('Console/Features/Chats/SpyderChatPaymentView.swift')
status = read('Console/Features/Chats/SpyderTransferStatusView.swift')
checks = {
    'review separated from input stage': 'if !reviewing && submitted == nil {' in send and 'Шаг 2 из 2 · Проверка' in send,
    're-review offers edit without resending': 'Button("Изменить") { clearQuote() }' in send,
    'manual-address transfers remain nonpayable': 'guard let context = chatRecipient' in send and 'return WalletEthereumSignature.verifyOwnership' in send,
    'preflight must match quote and wallet': 'quote.matches(sender:' in send and 'approvedWalletID == access.activeWalletID' in send,
    'send gated by separate confirmation': 'else if canSendUSDT { confirmUSDT = true }' in send and 'confirmationDialog("Отправить USDT' in send,
    'chain technical data is collapsed': 'DisclosureGroup("Технические сведения о сети")' in send,
    'preview warns unsupported assets': 'Это предпросмотр. Отправка выбранного актива здесь недоступна.' in send,
    'receive requires explicit network approval': 'if acknowledged {' in receive and 'Label("Показать адрес и QR"' in receive,
    'receiving address rederived from protected wallet': 'chains.verifiedForReceiving' in receive and 'chains.verifiedWalletID == access.activeWalletID' in receive,
    'receive copy has limited lifetime': '.expirationDate: Date().addingTimeInterval(120)' in receive and '.localOnly: true' in receive,
    'share address only after acknowledgement': 'ShareLink(item: address)' in receive and receive.index('if acknowledged {') < receive.index('ShareLink(item: address)'),
    'receive advanced RPC verification collapsed': 'DisclosureGroup {' in receive and 'Проверить зачисление по хешу · дополнительно' in receive,
    'receive contract data collapsed': 'DisclosureGroup("Адрес контракта токена · дополнительно")' in receive,
    'devnet submission protected from repeated taps': 'isSubmitting = true' in receive and 'else if !isSubmitting' in receive and 'defer { isSubmitting = false }' in receive,
    'devnet after submission can close': 'if didSubmit { dismiss() }' in receive and 'Text(didSubmit ? "Готово"' in receive,
    'devnet not sold as production': 'Подписать и отправить тестовые SPD' in receive,
    'touch shows pending verification': 'ProgressView("Проверяем устройство рядом…")' in touch,
    'touch disabled until comparison ready': '!promptReady || touch.ambiguous' in touch,
    'touch provides QR fallback': 'Button("Подключиться другим способом")' in touch,
    'touch only opens settings for permission errors': 'if needsLocalNetworkPermission {' in touch,
    'chat payment exposes in-progress state': 'Подтверждаем и отправляем реквизиты…' in payment,
    'chat payment reports both send failures': payment.count('Не удалось отправить') >= 2,
    'transaction status preserves previously assessed state': 'if error != nil { return "Проверка сети недоступна" }' not in status,
    'transaction retry checks network without resending': 'Button("Повторить проверку") { retryCount += 1 }' in status and 'retryCount)' in status,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()): raise SystemExit('Stage 3 UX static checks failed')
print(f'Passed {len(checks)} stage-three static UX checks')
