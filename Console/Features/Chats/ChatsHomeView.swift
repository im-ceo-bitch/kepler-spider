import SwiftUI
import UIKit

struct SpyderDevnetChatsHomeView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.scenePhase) private var scenePhase
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    let onProfile: () -> Void
    let isActive: Bool
    @State private var search = ""
    @State private var name = ""
    @State private var username = ""
    @State private var lookup = ""
    @State private var claim = ""
    @State private var invitation = ""
    @State private var adding = false
    @State private var inviteSent = false
    @State private var visibleInSearch = true
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true

    private var accent: SpyderSignalAccent { SpyderSignalAccent(rawValue: accentValue) ?? .red }
    private var avatarMotion: SpyderAvatarMotion { chat.myAvatar?.motion ?? (SpyderAvatarMotion(rawValue: avatarValue) ?? .pulse) }
    private var identityAccent: SpyderSignalAccent { chat.myAvatar?.color ?? accent }


    private var filtered: [SpyderChatPerson] {
        search.isEmpty ? chat.contacts : chat.contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    Text("Сеть").font(.system(size: 34, weight: .bold)).foregroundStyle(WalletTheme.ink)
                    Spacer()
                    Button { onProfile() } label: {
                        SpyderProfileAvatarView(motion: avatarMotion, accent: identityAccent,
                                                diameter: 46, animate: motionEnabled, seed: chat.myAvatar?.seed ?? "")
                    }
                    .accessibilityLabel("Мой профиль Spyder")
                    if chat.hasIdentity {
                        Button { adding = true } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 19)).foregroundStyle(WalletTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(WalletTheme.surface, in: Circle())
                        }.accessibilityLabel("Новый контакт")
                    }
                }.spyderReveal(0.03)
                identityCard

                if !chat.hasIdentity { setup }
                else {
                    HStack(spacing: 8) {
                        Circle().fill(chat.connected ? Color.green : WalletTheme.secondary).frame(width: 7, height: 7)
                        Text(chat.connected ? "Сеть подключена" : (chat.refreshing ? "Подключаемся…" : "Нет соединения"))
                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        Spacer()
                        if chat.refreshing { ProgressView().controlSize(.mini) }
                    }
                    .accessibilityElement(children: .combine)
                    .spyderReveal(0.08)

                    if !chat.connected && !chat.refreshing {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 19))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Нет связи со Spyder Chat").font(.system(size: 15, weight: .semibold))
                                Text(chat.serverStatus ?? "Проверь соединение. Переписки и ключи сохранены.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                Text("Повторное подключение выполняется автоматически.")
                                    .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                                Button("Повторить сейчас") { Task { await chat.refresh() } }
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if chat.connected && !chat.pushEnabled {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 20))
                                .foregroundStyle(WalletTheme.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Уведомления выключены")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Разреши уведомления, чтобы видеть новые сообщения вне приложения.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer(minLength: 4)
                            Button("Включить") { Task { await chat.enablePush() } }
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(14)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if chat.myUsername.isEmpty && chat.personaKind != "private" {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("Создай свой @username").font(.system(size: 15, weight: .semibold))
                                TextField("your_username", text: $claim)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                Button("Сохранить username") { Task { _ = await chat.claimUsername(claim) } }
                                    .font(.system(size: 14, weight: .semibold))
                                    .disabled(claim.count < 3)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(WalletTheme.secondary)
                        TextField("Поиск контактов", text: $search)
                            .textInputAutocapitalization(.never)
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(WalletTheme.surface, in: Capsule())

                    if !chat.requests.isEmpty {
                        Text("Запросы на общение").font(.system(size: 18, weight: .semibold)).foregroundStyle(WalletTheme.ink)
                        ForEach(chat.requests) { peer in
                            HStack {
                                SpyderProfileAvatarView(motion: peer.avatar?.motion ?? .quiet,
                                                         accent: peer.avatar?.color ?? .blue,
                                                         diameter: 50, animate: motionEnabled,
                                                         seed: peer.avatar?.seed ?? "")
                                Text(peer.name).font(.system(size: 15, weight: .medium))
                                Spacer()
                                Button("Принять") { Task { await chat.accept(peer) } }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WalletTheme.contrast)
                                    .padding(.horizontal, 16).frame(height: 38)
                                    .background(WalletTheme.accent, in: Capsule())
                            }
                        }
                    }

                    if filtered.isEmpty {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 11) {
                                Image(systemName: "message.badge")
                                    .font(.system(size: 29)).foregroundStyle(WalletTheme.ink)
                                Text("Пока нет переписок")
                                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(WalletTheme.ink)
                                Text("Найди друга по @username, отправь запрос и начни переписку после его принятия.")
                                    .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                                Button("Добавить контакт") { adding = true }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WalletTheme.ink)
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filtered) { person in
                                Button { onOpen(WalletContact(id: person.id, name: person.name, handle: person.username.map { "@" + $0 } ?? "", letter: String(person.name.prefix(1)).uppercased(), preview: "Открыть переписку", time: "")) } label: {
                                    HStack(spacing: 14) {
                                        SpyderProfileAvatarView(motion: person.avatar?.motion ?? .quiet,
                                            accent: person.avatar?.color ?? .blue,
                                            diameter: 50, animate: motionEnabled,
                                            seed: person.avatar?.seed ?? "")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(person.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(WalletTheme.ink)
                                            Text(person.username.map { "@" + $0 } ?? "Открыть переписку")
                                                .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(WalletTheme.secondary)
                                    }
                                    .padding(.vertical, 12)
                                }.buttonStyle(.plain)
                                if person.id != filtered.last?.id { Divider().overlay(WalletTheme.divider) }
                            }
                        }
                    }
                    Label("E2EE v2 · CryptoKit · одно устройство. Проверяйте отпечатки ключей вручную. Нет мультиустройств и Double Ratchet.", systemImage: "lock.shield")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 25)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .refreshable {
            // Native iOS pull-to-refresh indicator appears at the top of the list.
            await chat.refresh()
        }
        .task(id: isActive) {
            guard isActive, scenePhase == .active else { return }
            await chat.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(chat.connected ? 10 : 6)) }
                catch { break }
                guard !Task.isCancelled, scenePhase == .active, isActive else { break }
                await chat.refresh()
            }
        }
        .sheet(isPresented: $adding) { inviteSheet }
        .alert("Spyder Chat", isPresented: Binding(get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
    }

    private var identityCard: some View {
        HStack(spacing: 15) {
            SpyderProfileAvatarView(motion: avatarMotion, accent: identityAccent,
                                    diameter: 88, animate: motionEnabled, seed: chat.myAvatar?.seed ?? "")
            VStack(alignment: .leading, spacing: 6) {
                Text(chat.hasIdentity ? (chat.myName.isEmpty ? "Мой Spyder ID" : chat.myName) : "Твой Spyder ID")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2)
                Text(chat.hasIdentity && !chat.myUsername.isEmpty ? "@" + chat.myUsername : (chat.personaKind == "private" ? "Приватная личность" : "Создай имя и @username"))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text(chat.connected ? "Связь установлена" : (chat.refreshing ? "Подключаемся к сети…" : "Подключение восстанавливается"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 145)
        .background(Color(red: 0.065, green: 0.067, blue: 0.078),
                    in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(accent.color.opacity(0.28), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { onProfile() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }


    private var setup: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Создай свой Spyder ID")
                .font(.system(size: 25, weight: .bold)).foregroundStyle(WalletTheme.ink)
            Text("Одно имя и уникальный @username — чтобы тебя могли найти друзья. Адрес кошелька не нужен.")
                .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
            if !chat.hasConfiguredServer {
                WalletCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Сервис сообщений пока не подключён", systemImage: "wifi.exclamationmark")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Spyder Chat станет доступен после активации сервера сети. Кошелёк и ключи работают независимо от чата.")
                            .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                    }.foregroundStyle(WalletTheme.ink)
                }
            }
            WalletCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Имя для чата").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    TextField("Как тебя зовут?", text: $name).font(.system(size: 16))
                        .foregroundStyle(WalletTheme.ink)
                    Divider()
                    Text("Username · уникальный, публичный").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    TextField("your_username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 16)).foregroundStyle(WalletTheme.ink)
                    Text("3–20 символов: a–z, 0–9, _. Начинай с буквы.")
                        .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                    Toggle("Показывать мой @username в поиске", isOn: $visibleInSearch)
                        .font(.system(size: 14))
                    Text("Если включено, другие пользователи Spyder смогут найти твой профиль и отправить запрос на общение.")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                }
            }
            if let status = chat.serverStatus, chat.hasConfiguredServer {
                Label(status, systemImage: "network")
                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
            }
            Button {
                Task { await chat.register(name: name, username: username, discoverable: visibleInSearch) }
            } label: {
                Text(chat.working ? "Подключаем…" : "Начать общение").spyderPrimaryButton()
            }.buttonStyle(.plain).disabled(!chat.hasConfiguredServer || chat.working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.count < 3)
            Text("После создания профиля найди друга по @username. Он примет запрос — и вы сможете переписываться. Никогда не делись фразой восстановления.")
                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
        }.spyderReveal(0.08)
    }

    private var inviteSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Контакты").font(.system(size: 28, weight: .bold))
                    Spacer()
                    Button("Готово") { adding = false }.foregroundStyle(WalletTheme.ink)
                }
                if !chat.myUsername.isEmpty {
                    Text("Мой профиль: @" + chat.myUsername)
                        .font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                }
                Text("Найти человека по @username")
                    .font(.system(size: 19, weight: .semibold))
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(WalletTheme.secondary)
                    TextField("Поиск @username", text: $lookup)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(14).background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .task(id: lookup) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await chat.searchUsers(lookup)
                }
                if chat.searching { ProgressView() }
                ForEach(chat.searchResults) { person in
                    HStack(spacing: 12) {
                        SpyderProfileAvatarView(motion: person.avatar?.motion ?? .quiet,
                                            accent: person.avatar?.color ?? .blue,
                                            diameter: 50, animate: motionEnabled,
                                            seed: person.avatar?.seed ?? "")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.name).font(.system(size: 15, weight: .semibold))
                            Text("@" + (person.username ?? ""))
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer()
                        if chat.contacts.contains(where: { $0.id == person.id }) {
                            Text("В контактах").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        } else {
                            Button("Добавить") {
                                Task { if await chat.inviteUsername(person.username ?? "") { inviteSent = true } }
                            }.font(.system(size: 13, weight: .semibold))
                        }
                    }.padding(.vertical, 5)
                }
                Divider()
                Text("Твой код приглашения")
                    .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
                Text(chat.inviteCode)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Button { UIPasteboard.general.string = chat.inviteCode } label: {
                    Label("Скопировать мой код", systemImage: "doc.on.doc").spyderPrimaryButton()
                }.buttonStyle(.plain)
                Divider()
                Text("Пригласить по коду").font(.system(size: 20, weight: .semibold))
                TextField("Код приглашения друга", text: $invitation)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(size: 16, design: .monospaced))
                    .padding(14).background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                Button {
                    Task {
                        if await chat.invite(invitation) { inviteSent = true; invitation = "" }
                    }
                } label: { Text("Отправить приглашение").spyderPrimaryButton() }
                    .buttonStyle(.plain)
                    .disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if inviteSent { Label("Приглашение отправлено. Друг увидит его во вкладке «Сеть».", systemImage: "checkmark.circle")
                    .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary) }
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(22)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible).presentationCornerRadius(30)
    }
}
