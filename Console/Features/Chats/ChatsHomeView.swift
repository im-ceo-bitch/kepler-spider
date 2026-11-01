import SwiftUI
import UIKit

struct SpyderDevnetChatsHomeView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    @State private var search = ""
    @State private var name = ""
    @State private var username = ""
    @State private var lookup = ""
    @State private var claim = ""
    @State private var invitation = ""
    @State private var adding = false
    @State private var inviteSent = false
    @State private var showingPrivacy = false

    private var filtered: [SpyderChatPerson] {
        search.isEmpty ? chat.contacts : chat.contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    Text("Сеть").font(.system(size: 34, weight: .bold)).foregroundStyle(WalletTheme.ink)
                    Spacer()
                    if chat.hasIdentity {
                        Button { showingPrivacy = true } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 19))
                                .foregroundStyle(WalletTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(WalletTheme.surface, in: Circle())
                        }
                        .accessibilityLabel("Публичный профиль и приватность")
                        Button { adding = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(WalletTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(WalletTheme.surface, in: Circle())
                        }
                        .accessibilityLabel("Добавить контакт")
                    }
                }.spyderReveal(0.03)

                if !chat.hasIdentity { setup }
                else {
                    HStack(spacing: 8) {
                        Circle().fill(chat.connected ? Color.green : WalletTheme.secondary).frame(width: 7, height: 7)
                        Text(chat.connected ? "Spyder Chat · @\(chat.myUsername.isEmpty ? "username" : chat.myUsername)" : "Нет подключения к серверу")
                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        Spacer()
                        Button { Task { await chat.refresh() } } label: {
                            Image(systemName: "arrow.clockwise").foregroundStyle(WalletTheme.ink)
                        }.accessibilityLabel("Обновить чаты")
                    }.spyderReveal(0.08)

                    if !chat.connected {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 19))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Нет связи со Spyder Chat").font(.system(size: 15, weight: .semibold))
                                Text("Проверь интернет и повтори подключение. Сообщения на устройстве не затронуты.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                Button("Повторить") { Task { await chat.refresh() } }
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if chat.myUsername.isEmpty {
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
                                avatar(peer.name)
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
                                Text("Обменяйтесь кодами приглашения и начните общение один на один.")
                                    .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                                Button("Добавить контакт") { adding = true }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(WalletTheme.ink)
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filtered) { person in
                                Button { onOpen(WalletContact(id: person.id, name: person.name, handle: person.username.map { "@" + $0 } ?? "Spyder Chat", letter: String(person.name.prefix(1)).uppercased(), preview: "Открыть переписку", time: "")) } label: {
                                    HStack(spacing: 14) {
                                        avatar(person.name)
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
        .task {
            guard chat.hasIdentity else {
                if chat.hasConfiguredServer { await chat.probeServer() }
                return
            }
            await chat.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await chat.refresh()
            }
        }
        .sheet(isPresented: $adding) { inviteSheet }
        .sheet(isPresented: $showingPrivacy) { privacySheet }
        .alert("Spyder Chat", isPresented: Binding(get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
    }

    private var privacySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Spyder Identity", systemImage: "person.crop.circle")
                        .font(.system(size: 28, weight: .semibold))
                    WalletCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text(chat.myName).font(.title3.weight(.semibold))
                            Text(chat.myUsername.isEmpty ? "Без публичного username" : "@" + chat.myUsername)
                                .foregroundStyle(WalletTheme.secondary)
                            Label("Ключи чата не связаны с фразой восстановления кошелька", systemImage: "lock.shield")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: Binding(get: { chat.discoverable }, set: { value in
                                Task { await chat.updateDiscovery(value) }
                            })) {
                                Label("Показывать профиль в поиске", systemImage: "magnifyingglass")
                            }
                            Text("По умолчанию профиль скрыт. Даже при выключенном поиске Вы можете приглашать контакты по личному коду.")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Text("E2EE v2: сквозное шифрование при проверке ключей. Это предварительный криптографический протокол для одного устройства; он не имеет аудита и не поддерживает восстановление чатов через seed-фразу. Серверу видны участники, время и длина сообщений.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }.padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { showingPrivacy = false } } }
        }
    }

    private func avatar(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 21, weight: .semibold)).foregroundStyle(WalletTheme.ink)
            .frame(width: 50, height: 50).background(WalletTheme.divider, in: Circle())
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Твоя сеть. Твои контакты.")
                .font(.system(size: 25, weight: .bold)).foregroundStyle(WalletTheme.ink)
            Text("Выбери имя и уникальный @username. Найди друзей и общайся напрямую — адрес кошелька не нужен.")
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
                }
            }
            if let status = chat.serverStatus, chat.hasConfiguredServer {
                Label(status, systemImage: "network")
                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
            }
            Button {
                Task { await chat.register(name: name, username: username) }
            } label: {
                Text(chat.working ? "Подключаем…" : "Начать общение").spyderPrimaryButton()
            }.buttonStyle(.plain).disabled(!chat.hasConfiguredServer || chat.working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.count < 3)
            Text("Сообщения требуют сервер Chat v2 и проверки ключей контактов. Никогда не отправляйте сид-фразы, пароли или приватные ключи.")
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
                Text("Найти человека по username")
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
                        avatar(person.name)
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
                if inviteSent { Label("Запрос отправлен. Друг должен принять его в Chats.", systemImage: "checkmark.circle")
                    .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary) }
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(22)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible).presentationCornerRadius(30)
    }
}
