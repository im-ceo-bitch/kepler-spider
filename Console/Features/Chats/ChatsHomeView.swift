import SwiftUI
import UIKit

struct ChatsHomeView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    @State private var search = ""
    @State private var name = ""
    @State private var invitation = ""
    @State private var adding = false
    @State private var inviteSent = false

    private var filtered: [SpyderChatPerson] {
        search.isEmpty ? chat.contacts : chat.contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    Text("Chats").font(.system(size: 34, weight: .bold)).foregroundStyle(WalletTheme.ink)
                    Spacer()
                    if chat.hasIdentity {
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
                        Text(chat.connected ? "Spyder Chat · Devnet" : "Нет подключения к серверу")
                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        Spacer()
                        Button { Task { await chat.refresh() } } label: {
                            Image(systemName: "arrow.clockwise").foregroundStyle(WalletTheme.ink)
                        }.accessibilityLabel("Обновить чаты")
                    }.spyderReveal(0.08)

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
                                Button { onOpen(WalletContact(id: person.id, name: person.name, handle: "Spyder Chat", letter: String(person.name.prefix(1)).uppercased(), preview: "Открыть переписку", time: "")) } label: {
                                    HStack(spacing: 14) {
                                        avatar(person.name)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(person.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(WalletTheme.ink)
                                            Text("Открыть переписку").font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
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
                    Label("Тестовый чат. Сообщения пока не имеют сквозного шифрования.", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 25)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .task {
            guard chat.hasIdentity else { return }
            await chat.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await chat.refresh()
            }
        }
        .sheet(isPresented: $adding) { inviteSheet }
        .alert("Spyder Chat", isPresented: Binding(get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
    }

    private func avatar(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 21, weight: .semibold)).foregroundStyle(WalletTheme.ink)
            .frame(width: 50, height: 50).background(WalletTheme.divider, in: Circle())
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Общение без адресов кошельков")
                .font(.system(size: 23, weight: .bold)).foregroundStyle(WalletTheme.ink)
            Text("Подключи свой сервер Spyder Chat и создай отдельный профиль для переписок. Сид-фраза не используется.")
                .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
            WalletCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Адрес сервера (HTTPS)").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    TextField("https://spyder-chat-devnet…workers.dev", text: $chat.serverAddress)
                        .font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .foregroundStyle(WalletTheme.ink)
                    Divider()
                    Text("Имя для чата").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    TextField("Как тебя зовут?", text: $name).font(.system(size: 16))
                        .foregroundStyle(WalletTheme.ink)
                }
            }
            Button {
                Task { await chat.register(name: name) }
            } label: {
                Text(chat.working ? "Подключаем…" : "Начать общение").spyderPrimaryButton()
            }.buttonStyle(.plain).disabled(chat.working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Devnet: сервер может читать сообщения. Не отправляй пароли, сид-фразы и приватные ключи.")
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
                Text("Твой код приглашения")
                    .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
                Text(chat.inviteCode)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Button { UIPasteboard.general.string = chat.inviteCode } label: {
                    Label("Скопировать мой код", systemImage: "doc.on.doc").spyderPrimaryButton()
                }.buttonStyle(.plain)
                Divider()
                Text("Добавить человека").font(.system(size: 20, weight: .semibold))
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
