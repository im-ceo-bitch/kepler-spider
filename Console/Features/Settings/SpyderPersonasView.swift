import SwiftUI

/// Only the active persona owns its contacts, decrypted messages and E2EE keys.
/// The server must not be given a shared device-wide persona identifier.
struct SpyderPersonasView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(chat.personaIDs, id: \.self) { id in
                    if let item = chat.personaSummary(id) {
                        Button {
                            Task { await chat.activatePersona(id); dismiss() }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.privacy.symbol)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(.quaternary, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.headline)
                                    Text(item.privacy.title + (item.username.isEmpty ? " · по приглашению" : " · @" + item.username))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if id == chat.activePersonaID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: { Text("Мои личности") }
            footer: {
                Text("Каждая личность имеет отдельный аккаунт, контакты, историю и E2EE-ключи. Переключение не переносит существующие переписки.")
            }
            Section {
                Button { showCreate = true } label: {
                    Label("Создать приватную личность", systemImage: "plus.circle.fill")
                }
                .disabled(chat.working || chat.personaIDs.count >= 8)
            } footer: {
                Text("Новая личность создаётся в Private; видимость можно изменить в её Spyder ID. Это НЕ гарантия анонимности перед сервером: IP и время запросов могут связывать профили. Push у таких личностей остаётся отключён.")
            }
        }
        .navigationTitle("Мои личности")
        .alert("Новая приватная личность", isPresented: $showCreate) {
            TextField("Имя", text: $newName)
            Button("Отмена", role: .cancel) {}
            Button("Создать") {
                Task {
                    creating = true
                    if await chat.createPrivatePersona(name: newName) { dismiss() }
                    creating = false
                }
            }
        } message: { Text("Новый аккаунт получит собственные ключи и код приглашения. Старые сообщения останутся в исходной личности.") }
        .overlay { if creating { ProgressView("Создание личности...") } }
    }
}
