import SwiftUI

// Advanced diagnostics only; normal users never enter a server URL.
struct SpyderChatConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chat: SpyderChatStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Spyder Chat Server") {
                    TextField("https://your-worker.workers.dev", text: $chat.serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(chat.checkingServer ? "Проверяем…" : "Проверить HTTPS") {
                        Task { await chat.probeServer() }
                    }
                    .disabled(chat.checkingServer)
                    if let status = chat.serverStatus { Text(status).font(.footnote) }
                }
                Section {
                    Text("URL настраивается владельцем сети через GitHub Actions. Не используйте неизвестные серверы: текущие сообщения не имеют сквозного шифрования.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Диагностика чата")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
    }
}
