import SwiftUI

// Advanced diagnostics only; normal users never enter a server URL.
struct SpyderChatConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chat: SpyderChatStore

    var body: some View {
        Form {
                Section("Spyder Chat Server") {
                    Text(chat.serverAddress.isEmpty ? "Адрес не задан" : chat.serverAddress)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                    Button(chat.checkingServer ? "Проверяем…" : "Проверить HTTPS") {
                        Task { await chat.probeServer() }
                    }
                    .disabled(chat.checkingServer)
                    if let status = chat.serverStatus { Text(status).font(.footnote) }
                }
                Section {
                    Text("Адрес встроен в приложение при сборке или берётся из сохранённого Spyder ID. Не меняй сервер без миграции идентичности: Chat v2 использует отдельные ключи сквозного шифрования.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Диагностика чата")
    }
}
