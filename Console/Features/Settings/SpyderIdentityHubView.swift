import SwiftUI
import CoreImage.CIFilterBuiltins

/// Public messaging identity only. This page is pushed by the Network stack,
/// so the wallet's account and recovery settings never appear here.
struct SpyderIdentityHubView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull: CGFloat = 0
    @State private var peakPull: CGFloat = 0
    @State private var dragging = false
    @State private var showingViewer = false
    @State private var savingPrivacy = false
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true


    private var accent: Color { (chat.myAvatar?.color ?? .blue).color }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 21) {
                    Color.clear.frame(height: 0).background(GeometryReader { proxy in
                        Color.clear.preference(key: SpyderIdentityPullKey.self,
                            value: proxy.frame(in: .named("spyder.identity.scroll")).minY - 20)
                    })
                    identityHeader(width: max(1, geometry.size.width - 40))
                    if chat.hasIdentity { shareActions }
                    else { noIdentityHint }
                    profileGroup
                    preferencesGroup
                    discoverabilityGroup
                    Text("Spyder ID и ключи переписки не связаны с seed-фразой криптовалютного кошелька.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink).padding(20)
            }
            .coordinateSpace(name: "spyder.identity.scroll")
            .onPreferenceChange(SpyderIdentityPullKey.self) { value in
                pull = max(0, value)
                if dragging { peakPull = max(peakPull, pull) }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { _ in
                    if !dragging { peakPull = 0 }
                    dragging = true
                }
                .onEnded { _ in
                    let expand = chat.hasIdentity && SpyderIdentityExpansion.opensViewer(peakPull: peakPull)
                    dragging = false; peakPull = 0
                    if expand { showingViewer = true }
                })
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Spyder ID")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingViewer) { SpyderIdentityViewer() }
        .onChange(of: chat.activePersonaID) { _, _ in showingViewer = false; pull = 0; peakPull = 0 }
        .task { if chat.hasIdentity { await chat.refresh() } }
        .alert("Spyder ID", isPresented: Binding(
            get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } }
        )) { Button("Понятно", role: .cancel) { chat.errorMessage = nil } }
            message: { Text(chat.errorMessage ?? "") }
    }

    private func identityHeader(width: CGFloat) -> some View {
        let size: CGFloat = 80
        let radius: CGFloat = 40
        return VStack(spacing: 12) {
            Button { showingViewer = true } label: {
                SpyderProfileAvatarView(motion: chat.myAvatar?.motion ?? .pulse,
                    accent: chat.myAvatar?.color ?? .blue, diameter: size,
                    animate: motionEnabled, seed: chat.myAvatar?.seed ?? "",
                    cornerRadius: radius, ringStyle: chat.personaStyle.ring)
            }
            .buttonStyle(.plain).disabled(!chat.hasIdentity)
            .accessibilityLabel("Открыть личность на весь экран")
            Text(chat.hasIdentity ? (chat.myName.isEmpty ? "Spyder ID" : chat.myName) : "Твой Spyder ID")
                .font(.system(size: 29, weight: .bold)).multilineTextAlignment(.center)
            Text(chat.myUsername.isEmpty ? "Только по приглашению" : "@" + chat.myUsername)
                .font(.system(size: 16)).foregroundStyle(WalletTheme.secondary).textSelection(.enabled)
            Label(chat.personaPrivacy.title, systemImage: chat.personaPrivacy.symbol)
                .font(.caption.weight(.medium)).foregroundStyle(accent)
            if !chat.myBio.isEmpty { Text(chat.myBio).font(.subheadline).multilineTextAlignment(.center) }
            if !chat.myStatus.isEmpty { Text(chat.myStatus).font(.caption).foregroundStyle(WalletTheme.secondary) }
            Label(chat.connected ? "Сеть доступна" : "Соединение восстанавливается",
                  systemImage: chat.connected ? "checkmark.shield" : "wifi.slash")
                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
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
            ShareLink(item: SpyderInviteLink.url(code: chat.inviteCode)?.absoluteString ?? chat.inviteCode) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.bordered)
        }
    }

    private var noIdentityHint: some View {
        WalletCard {
            Text("Создай Spyder ID во вкладке «Чаты». Это отдельная идентичность для сообщений, не кошелёк.")
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
            NavigationLink { SpyderPersonasView() } label: {
                identityRow("Мои личности", detail: "Публичные и приватные Spyder ID", symbol: "person.2.crop.square.stack")
            }
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
            NavigationLink { SpyderPersonaStyleView() } label: {
                identityRow("Аватар", detail: "Нативный аватар профиля", symbol: "paintpalette")
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
                Text("Уровень приватности").font(.headline)
                ForEach(SpyderPersonaPrivacy.allCases) { mode in
                    Button {
                        savingPrivacy = true
                        Task { _ = await chat.setPersonaPrivacy(mode); savingPrivacy = false }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: mode.symbol).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title).font(.subheadline.bold())
                                Text(mode.explanation).font(.caption).foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer(minLength: 0)
                            if chat.personaPrivacy == mode { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                        }.foregroundStyle(WalletTheme.ink).padding(.vertical, 5)
                    }.buttonStyle(.plain).disabled(!chat.hasIdentity || savingPrivacy)
                        .accessibilityAddTraits(chat.personaPrivacy == mode ? .isSelected : [])
                }
                if savingPrivacy { ProgressView() }
                Text("Для Public нужен @username. Hidden не удаляет старые чаты и не делает личность анонимной перед сервером. Личности, созданные приватными, по-прежнему не передают APNs-токен.")
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
    @State private var bio = ""
    @State private var status = ""
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
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
                Section("О себе") {
                    TextField("Биография (до 160 символов)", text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Статус (до 64 символов)", text: $status)
                    Button("Сохранить профиль и аватар") {
                        Task {
                            saving = true
                            let ok = await chat.updateProfile(bio: bio, status: status,
                                motion: chat.myAvatar?.motion ?? .pulse,
                                accent: chat.myAvatar?.color ?? .blue)
                            saving = false
                            result = ok ? "Профиль сохранён" : "Не удалось обновить профиль"
                        }
                    }
                    .disabled(saving || !chat.hasIdentity || bio.count > 160 || status.count > 64)
                    Text("Параметры анимированного аватара передаются контактам; видео или фотография не загружаются.")
                        .font(.footnote)
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
                    Text("@username уникален во всей сети. Видимость определяется уровнем Public / Private / Hidden. Допустимы 3–20 символов: латинские буквы, цифры и _. Отдельный кошелёк не создаётся.")
                        .font(.footnote)
                }
                if let result { Text(result).font(.footnote) }
            }
            .navigationTitle("Личные данные")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .onAppear {
                displayName = chat.myName
                username = chat.myUsername
                bio = chat.myBio
                status = chat.myStatus
            }
    }
}

struct SpyderIdentityQRView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    private var qrValue: String { SpyderInviteLink.url(code: chat.inviteCode)?.absoluteString ?? "" }

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
                Text("QR содержит код подключения этой личности. Отправляй его тем, с кем хочешь общаться. Hidden блокирует новые подключения даже по QR. Ключи и адреса кошелька не передаются.")
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

private struct SpyderIdentityPullKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
