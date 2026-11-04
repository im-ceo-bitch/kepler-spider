import SwiftUI
import UIKit

struct SpyderDevnetChatsHomeView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.scenePhase) private var scenePhase
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    let onProfile: () -> Void
    let isActive: Bool
    @State private var selectedPersona = ""
    @State private var showIdentityQR = false
    @State private var showPersonaStyle = false
        @State private var showPersonas = false
    @State private var switchingPersona = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var archived = false
    @State private var pendingDelete: SpyderChatPerson?
    @State private var showHidden = false
    @State private var pendingBlock: SpyderChatPerson?
    @State private var search = ""
    @State private var name = ""
    @State private var username = ""
    @State private var claim = ""
    @State private var visibleInSearch = true
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true

    private var accent: SpyderSignalAccent { SpyderSignalAccent(rawValue: accentValue) ?? .red }
    private var avatarMotion: SpyderAvatarMotion { chat.myAvatar?.motion ?? (SpyderAvatarMotion(rawValue: avatarValue) ?? .pulse) }
    private var identityAccent: SpyderSignalAccent { chat.myAvatar?.color ?? accent }


    private var filtered: [SpyderConversationSummary] {
        chat.conversations.filter { item in
            (showHidden || !item.preferences.hidden) &&
            (item.preferences.archived == true) == archived &&
            (search.isEmpty || item.peer.name.localizedCaseInsensitiveContains(search) ||
             (item.peer.username ?? "").localizedCaseInsensitiveContains(search))
        }.sorted { left, right in
            if (left.preferences.pinned == true) != (right.preferences.pinned == true) {
                return left.preferences.pinned == true
            }
            let l = left.last_message?.created_at ?? "", r = right.last_message?.created_at ?? ""
            return l == r ? left.peer.name.localizedCaseInsensitiveCompare(right.peer.name) == .orderedAscending : l > r
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Чаты").font(.system(size: 34, weight: .bold))
                        Spacer()
                        if chat.hasIdentity {
                            Button(action: onAdd) {
                                Label("Пригласить", systemImage: "person.badge.plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 14).frame(height: 44)
                                    .background(WalletTheme.surface, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    identityCarousel
                    if !chat.hasIdentity { setup }
                    else {
                        HStack(spacing: 7) {
                            Circle().fill(chat.connected ? WalletTheme.ink : WalletTheme.secondary).frame(width: 6, height: 6)
                            Text(chat.connected ? "Подключено" : "Нет соединения").font(.caption)
                            Spacer()
                            if chat.refreshing { ProgressView().controlSize(.mini) }
                        }.foregroundStyle(WalletTheme.secondary)
                        if let status = chat.serverStatus {
                            Text(status).font(.caption).foregroundStyle(WalletTheme.secondary)
                            Button("Повторить") { Task { await chat.refresh() } }
                        }
                        if !chat.pushEnabled {
                            Button("Включить уведомления") { Task { await chat.enablePush() } }
                        }
                        if chat.myUsername.isEmpty && chat.personaKind != "private" {
                            TextField("Создать @username", text: $claim)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Сохранить username") { Task { _ = await chat.claimUsername(claim) } }
                                .disabled(claim.count < 3)
                        }
                        TextField("Поиск переписок", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(WalletTheme.surface, in: Capsule())
                        Picker("Переписки", selection: $archived) {
                            Text("Чаты").tag(false)
                            Text("Архив").tag(true)
                        }.pickerStyle(.segmented)
                        if chat.contactPreferences.values.contains(where: { $0.hidden }) {
                            Toggle("Показать скрытые", isOn: $showHidden).font(.caption)
                        }
                    }
                }
                .foregroundStyle(WalletTheme.ink)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if chat.hasIdentity {
                Section {
                    if filtered.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(archived ? "Архив пуст" : "Пока нет переписок").font(.headline)
                            Text(search.isEmpty ? "Подключи контакт через «Пригласить»." : "Нет совпадений.")
                                .font(.caption).foregroundStyle(WalletTheme.secondary)
                            if !archived { Button("Пригласить", action: onAdd) }
                        }.padding(.vertical, 15).listRowBackground(Color.clear)
                    }
                    ForEach(filtered) { item in
                        conversationRow(item)
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingDelete = item.peer } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                                Button {
                                    Task { await chat.conversationAction(peer: item.id,
                                        action: item.preferences.archived == true ? "unarchive" : "archive") }
                                } label: { Label(item.preferences.archived == true ? "Вернуть" : "Архив", systemImage: "archivebox") }
                                    .tint(.gray)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    Task { await chat.conversationAction(peer: item.id,
                                        action: item.preferences.pinned == true ? "unpin" : "pin") }
                                } label: { Label(item.preferences.pinned == true ? "Открепить" : "Закрепить", systemImage: "pin") }
                                    .tint(.orange)
                                Button { toggleMute(item) } label: {
                                    Label(item.preferences.muted ? "Звук" : "Без звука", systemImage: "bell.slash")
                                }.tint(.gray)
                            }
                            .contextMenu {
                                Button("Открыть и выбрать личность") { open(item.peer) }
                                Button(item.preferences.muted ? "Включить уведомления" : "Выключить уведомления") { toggleMute(item) }
                                Button(item.preferences.hidden ? "Показать чат" : "Скрыть чат") {
                                    Task { await chat.setContactPreferences(peer: item.id,
                                        muted: item.preferences.muted, hidden: !item.preferences.hidden) }
                                }
                                Button("Заблокировать", role: .destructive) { pendingBlock = item.peer }
                            }
                    }
                } footer: {
                    Text("Перевод начинается с выбора собеседника. Сравнивай отпечатки ключей перед первым обменом реквизитами.")
                        .font(.caption2)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .refreshable {
            // Native iOS pull-to-refresh indicator appears at the top of the list.
            await chat.refresh()
        }
        .task(id: "\(isActive)-\(scenePhase == .active)") {
            guard isActive, scenePhase == .active else { return }
            chat.resumeDecryption()
            await chat.updatePresence(active: true)
            await chat.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(chat.connected ? 10 : 6)) }
                catch { break }
                guard !Task.isCancelled, scenePhase == .active, isActive else { break }
                await chat.updatePresence(active: true)
                await chat.refresh()
            }
        }
        .sheet(isPresented: $showIdentityQR) { NavigationStack { SpyderIdentityQRView() } }
        .sheet(isPresented: $showPersonaStyle) {
            NavigationStack { SpyderPersonaStyleView()
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showPersonaStyle = false }
                } }
            }
        }
        .sheet(isPresented: $showPersonas) {
            NavigationStack { SpyderPersonasView() }
        }
        .onAppear { selectedPersona = chat.activePersonaID ?? "" }
        .onChange(of: chat.activePersonaID) { _, id in selectedPersona = id ?? "" }
        .onChange(of: selectedPersona) { _, id in
            if id == "create-persona" {
                showPersonas = true
                selectedPersona = chat.activePersonaID ?? ""
                return
            }
            guard !id.isEmpty, id != chat.activePersonaID, !switchingPersona else { return }
            switchingPersona = true
            Task {
                await chat.activatePersona(id)
                selectedPersona = chat.activePersonaID ?? ""
                switchingPersona = false
            }
        }
        .confirmationDialog("Удалить переписку у тебя?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            if let person = pendingDelete {
                Button("Удалить у меня", role: .destructive) {
                    Task { await chat.conversationAction(peer: person.id, action: "delete") }
                    pendingDelete = nil
                }
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: { Text("История собеседника сохранится. Новое входящее сообщение вернёт чат в список.") }
        .confirmationDialog("Заблокировать контакт?", isPresented: Binding(
            get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }
        ), titleVisibility: .visible) {
            if let person = pendingBlock {
                Button("Заблокировать " + person.name, role: .destructive) {
                    Task { _ = await chat.block(person.id) }
                    pendingBlock = nil
                }
            }
            Button("Отмена", role: .cancel) { pendingBlock = nil }
        }
        .alert("Spyder Chat", isPresented: Binding(get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
    }

    private func open(_ person: SpyderChatPerson) {
        onOpen(WalletContact(id: person.id, name: person.name,
            handle: person.username.map { "@" + $0 } ?? "", letter: String(person.name.prefix(1)), preview: "", time: ""))
    }

    private func toggleMute(_ item: SpyderConversationSummary) {
        Task { await chat.setContactPreferences(peer: item.id, muted: !item.preferences.muted, hidden: item.preferences.hidden) }
    }

    private func personaLabel(peer: String) -> String {
        guard let owner = chat.activePersonaID,
              let selected = UserDefaults.standard.string(forKey: SpyderChatStore.chatPersonaKey(owner: owner, peer: peer)),
              let person = chat.personaSummary(selected) else { return chat.myName }
        return person.name
    }

    private func conversationRow(_ item: SpyderConversationSummary) -> some View {
        Button { open(item.peer) } label: {
            HStack(spacing: 13) {
                SpyderProfileAvatarView(motion: item.peer.avatar?.motion ?? .quiet,
                    accent: item.peer.avatar?.color ?? .blue, diameter: 52,
                    animate: motionEnabled && !reduceMotion, seed: item.peer.avatar?.seed ?? item.id)
                    .overlay(alignment: .bottomTrailing) {
                        if item.online { Circle().fill(.green).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(WalletTheme.canvas, lineWidth: 2)) }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.peer.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        Spacer()
                        if let timestamp = item.last_message?.created_at {
                            Text(SpyderConversationClock.text(timestamp)).font(.caption2).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    HStack {
                        if let message = item.last_message, message.sender_id == chat.activePersonaID {
                            SpyderReceiptMark(state: SpyderMessageReceipt(deliveredAt: message.delivered_at,
                                readAt: message.read_at), accent: WalletTheme.ink)
                        }
                        Text(item.typing ? "печатает…" : (chat.conversationPreviews[item.id] ?? "Начать переписку"))
                            .font(.system(size: 13)).foregroundStyle(item.typing ? WalletTheme.ink : WalletTheme.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 3)
                        if item.preferences.muted { Image(systemName: "bell.slash.fill").font(.caption2) }
                        if item.preferences.pinned == true { Image(systemName: "pin.fill").font(.caption2) }
                        if item.unread_count > 0 {
                            Text(item.unread_count > 99 ? "99+" : String(item.unread_count))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .padding(6).background(WalletTheme.ink, in: Capsule())
                        }
                    }
                    Text(personaLabel(peer: item.id)).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WalletTheme.secondary).lineLimit(1)
                }
            }
            .foregroundStyle(WalletTheme.ink).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }

    private var identityCarousel: some View {
        HStack(spacing: 12) {
            Button(action: onProfile) {
                HStack(spacing: 12) {
                    SpyderProfileAvatarView(motion: chat.myAvatar?.motion ?? .quiet,
                        accent: chat.myAvatar?.color ?? .blue, diameter: 48,
                        animate: motionEnabled && isActive, seed: chat.myAvatar?.seed ?? "")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chat.myName.isEmpty ? "Мой профиль" : chat.myName).font(.subheadline.bold())
                        Text(chat.myUsername.isEmpty ? "Spyder ID" : "@" + chat.myUsername)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.foregroundStyle(WalletTheme.ink)
            }.buttonStyle(.plain)
            Spacer(minLength: 4)
            Menu {
                ForEach(chat.personaIDs, id: \.self) { id in
                    if let person = chat.personaSummary(id) {
                        Button(person.name + (id == chat.activePersonaID ? " ✓" : "")) { selectedPersona = id }
                    }
                }
                Button("Управлять личностями") { showPersonas = true }
            } label: {
                Image(systemName: "chevron.up.chevron.down").frame(width: 44, height: 44)
            }.disabled(switchingPersona).accessibilityLabel("Сменить личность")
            if switchingPersona { ProgressView().controlSize(.small) }
        }.padding(.vertical, 4)
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
                    Text("Если включено, другие пользователи Spyder смогут найти твой профиль и сразу начать переписку.")
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
            Text("После создания профиля найди друга по @username. Чат появится сразу после подключения. Никогда не делись фразой восстановления.")
                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
        }.spyderReveal(0.08)
    }

}
