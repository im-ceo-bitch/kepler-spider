import SwiftUI
import UIKit

struct SpyderDevnetChatsHomeView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.scenePhase) private var scenePhase
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    let onProfile: () -> Void
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var archived = false
    @State private var showingContacts = false
    @State private var showHidden = false
    @State private var pendingDelete: SpyderChatPerson?
    @State private var pendingBlock: SpyderChatPerson?
    @State private var search = ""
    @State private var name = ""
    @State private var username = ""
    @State private var visibleInSearch = true
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true

    private var visibleContacts: [SpyderChatPerson] {
        chat.contacts.filter { person in
            (showHidden || chat.contactPreferences[person.id]?.hidden != true) &&
            (search.isEmpty || person.name.localizedCaseInsensitiveContains(search) ||
             (person.username ?? "").localizedCaseInsensitiveContains(search))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

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
            inboxHeader
            if chat.hasIdentity {
                if showingContacts { contactsSection } else { conversationsSection }

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

    /// The inbox is for finding conversations; identities and preferences live in Spyder ID.
    private var inboxHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Чаты")
                        .font(.largeTitle.bold())
                    Spacer(minLength: 4)
                    if chat.refreshing { ProgressView().controlSize(.small) }
                    if chat.hasIdentity {
                        Button(action: onProfile) {
                            SpyderProfileAvatarView(motion: chat.myAvatar?.motion ?? .quiet,
                                accent: chat.myAvatar?.color ?? .blue, diameter: 40,
                                animate: false, seed: chat.myAvatar?.seed ?? "")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Мой Spyder ID и настройки")
                        Button(action: onAdd) {
                            Image(systemName: "square.and.pencil")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(WalletTheme.canvas)
                                .background(WalletTheme.ink, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Новый чат")
                    }
                }
                if !chat.hasIdentity {
                    setup
                } else {
                    if !chat.connected {
                        Label("Нет соединения. Переписки обновятся после подключения.", systemImage: "wifi.slash")
                            .font(.footnote)
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    if let status = chat.serverStatus, !status.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Text(status).font(.footnote).foregroundStyle(WalletTheme.secondary)
                            Spacer(minLength: 4)
                            Button("Повторить") { Task { await chat.refresh() } }
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(WalletTheme.secondary)
                        TextField(showingContacts ? "Поиск контактов" : "Поиск переписок", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Очистить поиск")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    HStack(spacing: 10) {
                        Picker("Раздел", selection: $showingContacts) {
                            Text("Переписки").tag(false)
                            Text("Контакты").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if !showingContacts || chat.contactPreferences.values.contains(where: { $0.hidden }) {
                            Menu {
                                if !showingContacts {
                                    Button {
                                        archived.toggle()
                                    } label: {
                                        Label(archived ? "Все переписки" : "Открыть архив",
                                              systemImage: archived ? "tray" : "archivebox")
                                    }
                                }
                                if chat.contactPreferences.values.contains(where: { $0.hidden }) {
                                    Button {
                                        showHidden.toggle()
                                    } label: {
                                        Label(showHidden ? "Скрыть скрытые" : "Показать скрытые",
                                              systemImage: showHidden ? "eye.slash" : "eye")
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .accessibilityLabel("Фильтры переписок")
                            .accessibilityValue(archived && !showingContacts ? "Архив" : showHidden ? "Включены скрытые чаты" : "Без фильтров")
                        }
                    }
                    if archived && !showingContacts {
                        Label("Архив переписок", systemImage: "archivebox")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                }
            }
            .foregroundStyle(WalletTheme.ink)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var contactsSection: some View {
        Section {
            if visibleContacts.isEmpty {
                Text(search.isEmpty ? "Пока нет контактов" : "Контакты не найдены")
                    .foregroundStyle(WalletTheme.secondary).font(.subheadline)
                    .listRowSeparator(.hidden)
            }
            ForEach(visibleContacts, id: \.id) { person in
                Button { open(person) } label: {
                    HStack(spacing: 12) {
                        SpyderProfileAvatarView(motion: person.avatar?.motion ?? .quiet,
                            accent: person.avatar?.color ?? .blue, diameter: 44,
                            animate: false, seed: person.avatar?.seed ?? person.id)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.name).font(.headline)
                            if let username = person.username, !username.isEmpty {
                                Text("@" + username).font(.caption).foregroundStyle(WalletTheme.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(WalletTheme.secondary)
                    }.padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var conversationsSection: some View {
        Section {
            if filtered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(!search.isEmpty ? "Переписки не найдены" : archived ? "Архив пуст" : "Пока нет переписок").font(.headline)
                    Text(!search.isEmpty ? "Попробуй другое имя или username." : archived ? "Здесь появятся архивированные чаты." : "Пригласи контакт, чтобы начать общение.")
                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                    if !archived && search.isEmpty {
                        Button("Новый чат", action: onAdd)
                            .buttonStyle(SpyderActionButtonStyle(.secondary))
                    }
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
        }
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
                        Text(item.peer.name).font(.headline).lineLimit(1)
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
                            .font(.subheadline).foregroundStyle(item.typing ? WalletTheme.ink : WalletTheme.secondary)
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
                    if chat.personaIDs.count > 1 {
                        Label(personaLabel(peer: item.id), systemImage: "person.crop.circle")
                            .font(.caption2).foregroundStyle(WalletTheme.secondary).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(WalletTheme.ink).padding(.vertical, 8)
        }.buttonStyle(.plain)
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
