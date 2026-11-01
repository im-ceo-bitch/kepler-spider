import SwiftUI
import UserNotifications

private enum SpyderAlertTone: String, CaseIterable, Identifiable {
    case pulse, system, mute
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pulse: "Spyder Pulse"
        case .system: "Системный звук"
        case .mute: "Без звука"
        }
    }
}

/// The APNs path is diagnosed in three separate layers; 'queued' is NOT proof of delivery.
struct SpyderNotificationSettingsView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spyder.chat.sound.preference") private var tone = "pulse"
    @AppStorage("spyder.chat.sound.sent.enabled") private var sendingSound = true
    @State private var permission = "Проверяем…"
    @State private var checking = false
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    private var accent: Color { (SpyderSignalAccent(rawValue: accentValue) ?? .red).color }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 27)).foregroundStyle(accent)
                        Text("Уведомления и звуки")
                            .font(.system(size: 28, weight: .bold)).foregroundStyle(WalletTheme.ink)
                        Text("Выбирай, как звучит твоя сеть.")
                            .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Toggle("Сообщения и приглашения", isOn: Binding(
                                get: { chat.pushEnabled },
                                set: { enabled in
                                    Task {
                                        if enabled { await chat.enablePush() }
                                        else { await chat.disablePush() }
                                        await reloadDiagnostics()
                                    }
                                }))
                                .font(.system(size: 16, weight: .medium))
                                .disabled(!chat.hasIdentity)
                            Text("На заблокированном iPhone уведомление содержит только нейтральный текст — без сообщения и приватных ключей.")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Звук входящих").font(.headline)
                            Picker("Звук входящих", selection: $tone) {
                                ForEach(SpyderAlertTone.allCases) { option in
                                    Text(option.label).tag(option.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                            .onChange(of: tone) { _, selected in
                                Task { await chat.updatePushSound(selected) }
                            }
                            Button {
                                SpyderSonicPlayer.shared.preview("spyder_receive")
                            } label: {
                                Label("Прослушать Spyder Pulse", systemImage: "play.circle")
                                    .foregroundStyle(accent)
                            }
                            Toggle("Звук отправки", isOn: $sendingSound)
                            Button {
                                SpyderSonicPlayer.shared.preview("spyder_sent")
                            } label: {
                                Label("Прослушать звук отправки", systemImage: "play.circle")
                                    .foregroundStyle(accent)
                            }
                        }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Диагностика доставки").font(.headline)
                            statusRow("Разрешение iOS", permission)
                            statusRow("Cloudflare → APNs", chat.pushProviderReady.map { $0 ? "Настроено" : "Не настроено" } ?? "Не проверено")
                            statusRow("Подписка устройства", chat.pushRegisteredOnServer.map { $0 ? "Зарегистрирована" : "Нет" } ?? "Не проверена")
                            if let serverTone = chat.pushSoundOnServer {
                                statusRow("Звук на сервере", SpyderAlertTone(rawValue: serverTone)?.label ?? serverTone)
                            }
                            if let status = chat.lastAPNsResponse {
                                statusRow("Последний ответ Apple", status == 200 ? "200 · принято APNs" : "HTTP \(status) · ошибка")
                            } else {
                                statusRow("Последний ответ Apple", "Нет попыток")
                            }
                            if let attempted = chat.lastAPNsAttempt {
                                Text("Последняя попытка: " + attempted)
                                    .font(.caption2).foregroundStyle(WalletTheme.secondary)
                            }
                            if let pushStatus = chat.pushStatus {
                                Text(pushStatus).font(.footnote).foregroundStyle(WalletTheme.secondary)
                            }
                            Button(checking ? "Проверяем…" : "Проверить подключение") {
                                Task { await reloadDiagnostics() }
                            }
                            .disabled(checking || !chat.hasIdentity)
                            .buttonStyle(.bordered)
                            Button("Отправить тестовое уведомление") {
                                Task { await chat.sendTestPush() }
                            }
                            .disabled(!chat.pushEnabled || chat.pushRegisteredOnServer != true)
                            .foregroundStyle(accent)
                            Text("Успешная постановка в очередь APNs не гарантирует появления баннера. Для проверки заблокируй iPhone и проверь режим «Фокусирование».")
                                .font(.caption).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Text("Системный звук и показ баннеров зависят от настроек iOS, режима без звука и Фокусирования.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Уведомления и звуки")
            .task { await reloadDiagnostics() }
    }

    private func statusRow(_ label: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline)
            Spacer(minLength: 10)
            Text(detail).font(.subheadline).foregroundStyle(WalletTheme.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func reloadDiagnostics() async {
        guard !checking else { return }
        checking = true
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: permission = "Разрешено"
        case .provisional: permission = "Тихие уведомления"
        case .denied: permission = "Запрещено — открой настройки iPhone"
        case .notDetermined: permission = "Не запрошено"
        case .ephemeral: permission = "Временное"
        @unknown default: permission = "Неизвестно"
        }
        await chat.refreshPushDiagnostics()
        checking = false
    }
}
