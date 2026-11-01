import SwiftUI
import CoreImage.CIFilterBuiltins

/// Public messaging identity only. This page is pushed by the Network stack,
/// so the wallet's account and recovery settings never appear here.
struct SpyderIdentityHubView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @State private var showIdentityLimit = false

    private var accent: Color {
        (SpyderSignalAccent(rawValue: accentValue) ?? .red).color
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                identityHeader
                if chat.hasIdentity { shareActions }
                else { noIdentityHint }
                profileGroup
                preferencesGroup
                discoverabilityGroup
                Text("Spyder ID и ключи переписки не связаны с seed-фразой криптовалютного кошелька.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(20)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Spyder ID")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Дополнительные профили", isPresented: $showIdentityLimit) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Сейчас доступен один криптографический Spyder ID на устройство. Новые независимые идентичности потребуют отдельного безопасного хранения ключей и серверного маршрутизатора.")
        }
        .task { if chat.hasIdentity { await chat.refresh() } }
    }

    private var identityHeader: some View {
        VStack(spacing: 12) {
            SpyderProfileAvatarView(
                motion: SpyderAvatarMotion(rawValue: avatarValue) ?? .pulse,
                accent: SpyderSignalAccent(rawValue: accentValue) ?? .red,
                diameter: 114, animate: motionEnabled)
            Text(chat.hasIdentity ? (chat.myName.isEmpty ? "Spyder ID" : chat.myName) : "Твой Spyder ID")
                .font(.system(size: 29, weight: .bold))
                .multilineTextAlignment(.center)
            Text(chat.myUsername.isEmpty ? "Username не создан" : "@" + chat.myUsername)
                .font(.system(size: 16))
                .foregroundStyle(WalletTheme.secondary)
                .textSelection(.enabled)
            Label(chat.connected ? "Сеть доступна" : "Соединение восстанавливается",
                  systemImage: chat.connected ? "checkmark.shield" : "wifi.slash")
                .font(.system(size: 12))
                .foregroundStyle(WalletTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var shareActions: some View {
        HStack(spacing: 12) {
            NavigationLink { SpyderIdentityQRView() } label: {
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

    private var noIdentityHint: some View {
        WalletCard {
            Text("Создай Spyder ID во вкладке «Сеть». Это отдельная идентичность для сообщений, не кошелёк.")
                .font(.subheadline).foregroundStyle(WalletTheme.secondary)
        }
    }

    private var profileGroup: some View {
        VStack(spacing: 0) {
            NavigationLink { SpyderProfileEditView() } label: {
                identityRow("Личные данные", detail: "Имя и @username", symbol: "person.crop.circle")
            }
            Divider()
            NavigationLink { SpyderIdentityQRView() } label: {
                identityRow("QR и код приглашения", detail: "Поделиться Spyder ID", symbol: "qrcode")
            }
            Divider()
            Button { showIdentityLimit = true } label: {
                identityRow("Мои идентичности", detail: "Один реальный профиль", symbol: "person.2.crop.square.stack")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 26))
    }

    private var preferencesGroup: some View {
        VStack(spacing: 0) {
            NavigationLink { SpyderNotificationSettingsView() } label: {
                identityRow("Уведомления и звуки", detail: "Spyder Pulse · APNs", symbol: "bell.badge")
            }
            Divider()
            NavigationLink { SpyderMotionSettingsView() } label: {
                identityRow("Персонализация", detail: "Аватар, цвета, анимации", symbol: "paintpalette")
            }
            Divider()
            NavigationLink { SpyderChatAppearanceSettingsView(peerID: nil) } label: {
                identityRow("Оформление чатов", detail: "Обои, пузырьки и эффекты", symbol: "bubble.left.and.bubble.right")
            }
            Divider()
            NavigationLink { SpyderTerminalSettingsScreen() } label: {
                identityRow("Spyder Terminal", detail: "Режим, команды и печать", symbol: "terminal")
            }
            Divider()
            NavigationLink { SpyderChatConnectionSettingsView() } label: {
                identityRow("Сеть и диагностика", detail: "Подключение и состояние сервера", symbol: "network")
            }
        }
        .padding(.horizontal, 16)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 26))
    }

    private var discoverabilityGroup: some View {
        WalletCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Показывать меня в поиске", isOn: Binding(
                    get: { chat.discoverable },
                    set: { enabled in Task { await chat.updateDiscovery(enabled) } }
                ))
                .disabled(!chat.hasIdentity)
                Text("Настройка определяет видимость в поиске по @username. Уже добавленные контакты сохраняются.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
        }
    }

    private func identityRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(width: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
            }
            Spacer(minLength: 5)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WalletTheme.secondary)
        }
        .frame(minHeight: 63)
        .contentShape(Rectangle())
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

private struct SpyderIdentityQRView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    private var qrValue: String { chat.myUsername.isEmpty ? chat.inviteCode : "@" + chat.myUsername }

    var body: some View {
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
            .navigationTitle("Мой QR")
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
