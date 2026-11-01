import SwiftUI
import CoreImage.CIFilterBuiltins

/// Spyder ID is the identity for the messaging network, not the wallet seed.
/// One real account only: additional cryptographic identities require a backend migration.
struct SpyderIdentityHubView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @State private var showingNotifications = false
    @State private var showingWalletSettings = false
    @State private var showingMotion = false
    @State private var showingProfileEdit = false
    @State private var showingQR = false
    @State private var showingDeveloperInfo = false

    private var accent: SpyderSignalAccent { SpyderSignalAccent(rawValue: accentValue) ?? .red }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Spyder ID").font(.system(size: 29, weight: .bold))
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(WalletTheme.surface, in: Circle())
                        }.accessibilityLabel("Закрыть профиль")
                    }
                    .foregroundStyle(WalletTheme.ink)

                    VStack(spacing: 11) {
                        SpyderProfileAvatarView(
                            motion: SpyderAvatarMotion(rawValue: avatarValue) ?? .pulse,
                            accent: accent, diameter: 108, animate: motionEnabled)
                        Text(chat.hasIdentity ? chat.myName : "Твой Spyder ID")
                            .font(.system(size: 27, weight: .bold)).foregroundStyle(WalletTheme.ink)
                            .lineLimit(2).multilineTextAlignment(.center)
                        Text(chat.myUsername.isEmpty ? "Публичное имя ещё не создано" : "@" + chat.myUsername)
                            .font(.system(size: 15)).foregroundStyle(WalletTheme.secondary)
                            .textSelection(.enabled)
                        Label(chat.connected ? "Сеть доступна" : "Нет подключения к чату",
                              systemImage: chat.connected ? "checkmark.shield" : "wifi.slash")
                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    if chat.hasIdentity {
                        HStack(spacing: 10) {
                            Button { showingQR = true } label: {
                                Label("Мой QR", systemImage: "qrcode")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WalletTheme.accent)
                            .foregroundStyle(WalletTheme.contrast)
                            ShareLink(item: chat.myUsername.isEmpty ? chat.inviteCode : "@" + chat.myUsername) {
                                Label("Поделиться", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if !chat.hasIdentity {
                        WalletCard {
                            Label("Создай Spyder ID во вкладке «Сеть», чтобы настроить профиль и приглашения.", systemImage: "person.crop.circle.badge.plus")
                                .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    if chat.hasIdentity {
                    WalletCard {
                        VStack(spacing: 0) {
                            row("Личные данные", detail: "Имя и @username", symbol: "person.crop.circle") {
                                showingProfileEdit = true
                            }
                            Divider()
                            row("QR и код приглашения", detail: "Добавить контакт", symbol: "qrcode") {
                                showingQR = true
                            }
                            Divider()
                            row("Профили", detail: "Основная идентичность", symbol: "person.2.crop.square.stack") {
                                showingDeveloperInfo = true
                            }
                        }
                    }
                    }
                    WalletCard {
                        VStack(spacing: 0) {
                            row("Уведомления и звуки", detail: "Spyder Pulse · APNs", symbol: "bell.badge") {
                                showingNotifications = true
                            }
                            Divider()
                            row("Персонализация", detail: "Цвет, аватар, анимация", symbol: "paintpalette") {
                                showingMotion = true
                            }
                            Divider()
                            row("Настройки кошелька", detail: "Безопасность, язык, резервная копия", symbol: "gearshape") {
                                showingWalletSettings = true
                            }
                        }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Показывать меня в поиске", isOn: Binding(
                                get: { chat.discoverable },
                                set: { enabled in Task { await chat.updateDiscovery(enabled) } }
                            ))
                            .disabled(!chat.hasIdentity)
                            Text("Выключение скрывает профиль из поиска по @username. Контакты с существующим приглашением остаются доступными.")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Text("Spyder ID использует отдельные ключи сообщений. Фраза восстановления кошелька не открывает переписки. Проверяй отпечатки контактов.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNotifications) { SpyderNotificationSettingsView() }
            .sheet(isPresented: $showingWalletSettings) { WalletSettingsView() }
            .sheet(isPresented: $showingMotion) { SpyderMotionSettingsView() }
            .sheet(isPresented: $showingProfileEdit) { SpyderProfileEditView() }
            .sheet(isPresented: $showingQR) { SpyderIdentityQRView() }
            .alert("Дополнительные профили", isPresented: $showingDeveloperInfo) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Сейчас доступен один реальный Spyder ID на устройство. Несколько независимых профилей потребуют отдельные серверные аккаунты, ключи и маршрутизацию сообщений. Мы не создаём фиктивные профили.")
            }
            .task { if chat.hasIdentity { await chat.refresh() } }
        }
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 19))
                    .frame(width: 31).foregroundStyle(accent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(WalletTheme.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                }
                Spacer(minLength: 7)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }.frame(minHeight: 58).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SpyderProfileEditView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var username = ""
    @State private var saving = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    TextField("Имя профиля", text: $displayName)
                        .textContentType(.nickname)
                        .autocorrectionDisabled()
                    Button("Сохранить имя") {
                        Task {
                            saving = true
                            let ok = await chat.updateDisplayName(displayName)
                            saving = false
                            result = ok ? "Имя обновлено" : "Не удалось обновить имя"
                        }
                    }
                    .disabled(saving || !chat.hasIdentity || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Username") {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Сохранить @username") {
                        Task {
                            saving = true
                            let ok = await chat.claimUsername(username)
                            saving = false
                            result = ok ? "Username сохранён" : "Не удалось сохранить username"
                        }
                    }
                    .disabled(saving || !chat.hasIdentity || username.count < 3)
                    Text("Публичное имя уникально во всей сети. Допустимы 3–20 символов: латинские буквы, цифры и _. Отдельный кошелёк не создаётся.")
                        .font(.footnote)
                }
                if let result { Text(result).font(.footnote) }
            }
            .navigationTitle("Личные данные")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .onAppear {
                displayName = chat.myName
                username = chat.myUsername
            }
        }
    }
}

private struct SpyderIdentityQRView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    private var qrValue: String { chat.myUsername.isEmpty ? chat.inviteCode : "@" + chat.myUsername }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Мой Spyder QR").font(.title2.bold())
                if let image = qrCode(qrValue) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable().scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(17).background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("QR-код профиля")
                }
                Text(qrValue).font(.headline.monospaced()).textSelection(.enabled)
                ShareLink(item: qrValue) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                Text("QR содержит только публичный @username или код приглашения. Приватные ключи и адреса кошелька в нём отсутствуют.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary).multilineTextAlignment(.center)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }

    private func qrCode(_ value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(value.utf8)
        generator.correctionLevel = "M"
        let context = CIContext()
        guard let output = generator.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
