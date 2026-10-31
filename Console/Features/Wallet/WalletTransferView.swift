import SwiftUI
import UIKit

struct WalletTransferView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spider: SpiderDevnetStore
    let isRequest: Bool
    let contact: WalletContact
    @State private var amount = ""
    @State private var recipient = ""
    @State private var note = ""
    @State private var isReview = false
    @State private var didSubmit = false
    @State private var transferError: String?

    private var amountIsValid: Bool {
        guard let units = try? SpiderProtocolV1.amountUnits(amount) else { return false }
        return units > 0
    }
    private var validDestination: Bool {
        SpiderDevnetSigner.isValidAddress(recipient.trimmingCharacters(in: .whitespacesAndNewlines)) &&
        recipient.trimmingCharacters(in: .whitespacesAndNewlines) != spider.address
    }
    private var canContinue: Bool {
        amountIsValid && (isRequest || (validDestination && spider.connected &&
            spider.address != nil && spider.pendingForAddress == nil && !spider.sending))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                Spacer()
                Text(isRequest ? "ДЕМО-ЗАПРОС" : "TEST DEVNET")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(spacing: 11) {
                        Image(systemName: isRequest ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 27))
                            .frame(width: 70, height: 70)
                            .background(WalletTheme.surface, in: Circle())
                        Text(isRequest ? "Запросить SPD" : "Отправить тестовые SPD")
                            .font(.system(size: 26, weight: .bold))
                        if !contact.id.isEmpty {
                            Text("Контакт: \(contact.name) · адрес нужно ввести отдельно")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 25)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 14) {
                            if !isRequest {
                                Text("Адрес получателя · Spider Chain")
                                    .font(.system(size: 13, weight: .semibold))
                                TextField("spider1…", text: $recipient)
                                    .font(.system(size: 14, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.asciiCapable)
                                    .onChange(of: recipient) { _, _ in isReview = false }
                                Divider()
                            }
                            Text("Сумма · SPD")
                                .font(.system(size: 13, weight: .semibold))
                            TextField("0.000000000", text: $amount)
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                                .keyboardType(.decimalPad)
                                .onChange(of: amount) { _, _ in isReview = false }
                            Text(isRequest ? "Только просмотр запроса без публикации" :
                                 (spider.connected ? "Доступно: \(spider.balanceText) тестовых SPD" : "Для отправки требуется подключённый Devnet в профиле"))
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            if isRequest {
                                Divider()
                                TextField("Комментарий (необязательно)", text: $note)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    if !isRequest, spider.address == nil {
                        Button { spider.deriveAddress() } label: {
                            Label("Открыть SPD-адрес через Face ID", systemImage: "faceid")
                                .font(.system(size: 14, weight: .medium))
                        }.disabled(spider.busy)
                    }
                    if !isRequest, spider.hasConfiguration, !spider.connected, spider.address != nil {
                        Button { Task { await spider.refresh() } } label: {
                            Label("Проверить соединение", systemImage: "arrow.clockwise")
                        }.disabled(spider.refreshing)
                    }
                    if isReview {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(isRequest ? "Предпросмотр запроса" : "Подтверждение отправки", systemImage: "checkmark.shield")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(amount) SPD")
                                    .font(.system(size: 24, weight: .semibold))
                                if !isRequest {
                                    Text(recipient)
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text("Сетевая комиссия по текущему контракту: 0.000021 SPD. Отправка подписывается на устройстве после Face ID.")
                                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                } else {
                                    Text("Это только демонстрация. Сетевой запрос не создаётся.")
                                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                }
                            }
                        }
                    }
                    if !isRequest, let pending = spider.pendingForAddress {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(pending.queued ? "В очереди, ещё не подтверждено" : "Статус отправки неизвестен", systemImage: "clock")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(pending.id).font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Button("Проверить финализацию") { Task { await spider.refresh() } }
                                    .disabled(spider.refreshing)
                                Text("До подтверждения не запускайте повторный перевод с этим nonce.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    }
                    if didSubmit, spider.pendingForAddress == nil, spider.latestConfirmed != nil {
                        Label("Тестовая транзакция финализирована", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            Button {
                if !isReview {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { isReview = true }
                } else if isRequest {
                    dismiss()
                } else {
                    Task {
                        do {
                            try await spider.send(to: recipient, amountText: amount)
                            didSubmit = true
                        } catch { transferError = error.localizedDescription }
                    }
                }
            } label: {
                HStack {
                    if spider.sending { ProgressView().tint(WalletTheme.contrast) }
                    Text(isReview ? (isRequest ? "Закрыть предпросмотр" : "Подписать и отправить в Devnet") : "Продолжить")
                }.spyderPrimaryButton()
            }
            .disabled(!canContinue || didSubmit)
            .opacity((canContinue && !didSubmit) ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.bottom, 25)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .alert("Spider Devnet", isPresented: Binding(
            get: { transferError != nil }, set: { if !$0 { transferError = nil } }
        )) {
            Button("Понятно", role: .cancel) { transferError = nil }
        } message: { Text(transferError ?? "") }
    }
}

struct WalletReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    @State private var selected: SpyderChain? = nil
    @State private var acknowledge = false
    @State private var copied = false

    private var address: String? {
        if let selected { return chains.address(for: selected) }
        return spider.address
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Receive")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                        Text("Выбери сеть для адреса")
                            .font(.system(size: 14))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    Spacer()
                    SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                }
                .spyderReveal(0.02)
                VStack(spacing: 9) {
                    Button { selected = nil; acknowledge = false; copied = false } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "network").font(.system(size: 21)).frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Spider Chain").font(.system(size: 15, weight: .semibold))
                                Text("SPD · только тестовая Devnet").font(.system(size: 11))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: selected == nil ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                        }
                        .foregroundStyle(WalletTheme.ink)
                        .padding(13)
                        .background(selected == nil ? WalletTheme.canvas : WalletTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain)
                    ForEach(SpyderChain.allCases) { chain in
                        Button { selected = chain; acknowledge = false; copied = false } label: {
                            HStack(spacing: 13) {
                                Image(systemName: chain.symbol)
                                    .font(.system(size: 21))
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chain.name).font(.system(size: 15, weight: .semibold))
                                    Text(chain.detail).font(.system(size: 11))
                                        .foregroundStyle(WalletTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: selected == chain ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                            }
                            .foregroundStyle(WalletTheme.ink)
                            .padding(13)
                            .background(selected == chain ? WalletTheme.canvas : WalletTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                }
                WalletCard {
                    VStack(spacing: 17) {
                        Label(selected == nil ? "SPIDER TEST DEVNET ONLY" : "MAINNET ADDRESS · TESTING ONLY",
                              systemImage: "exclamationmark.shield")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WalletTheme.secondary)
                        Text(selected?.warning ?? "Это адрес для тестовых SPD в Spider Chain. Нельзя отправлять на него реальные деньги или токены из других сетей.")
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                            .multilineTextAlignment(.center)
                        if let address {
                            if acknowledge {
                                SpyderQRView(address: address)
                                    .frame(width: 210, height: 210)
                                    .frame(maxWidth: .infinity)
                                    .privacySensitive()
                                Text(address)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(WalletTheme.ink)
                                    .multilineTextAlignment(.center)
                                    .textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = address
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    copied = true
                                } label: {
                                    Label(copied ? "Адрес скопирован" : "Скопировать адрес",
                                          systemImage: copied ? "checkmark" : "doc.on.doc")
                                        .spyderPrimaryButton()
                                }
                                .buttonStyle(.plain)
                            } else {
                                Image(systemName: "eye.slash")
                                    .font(.system(size: 36, weight: .ultraLight))
                                    .foregroundStyle(WalletTheme.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 90)
                                Toggle("Понимаю: это ранняя тестовая версия. Не отправлять реальные средства.", isOn: $acknowledge)
                                    .font(.system(size: 13))
                                    .tint(WalletTheme.ink)
                                    .foregroundStyle(WalletTheme.ink)
                            }
                        } else {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 36))
                                .foregroundStyle(WalletTheme.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                            Text("Сначала активируй адрес после проверки Face ID")
                                .font(.system(size: 13))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WalletTheme.secondary)
                            Button { if selected == nil { spider.deriveAddress() } else { chains.activate() } } label: {
                                HStack {
                                    if chains.isLoading || spider.busy { ProgressView().tint(WalletTheme.contrast) }
                                    Text(chains.isLoading || spider.busy ? "Проверяем…" : "Активировать адрес")
                                }
                                .spyderPrimaryButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(chains.isLoading || spider.busy)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Spider Chain — исследовательская Devnet. Другие адреса показаны только для тестирования. Не используйте этот экран для реальных депозитов.")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .padding(22)
            .padding(.bottom, 28)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .alert("Ошибка получения адресов", isPresented: Binding(
            get: { chains.errorMessage != nil },
            set: { if !$0 { chains.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { chains.errorMessage = nil }
        } message: { Text(chains.errorMessage ?? "") }
    }
}
