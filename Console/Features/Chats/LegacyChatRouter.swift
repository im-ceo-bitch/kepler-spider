import SwiftUI

struct ChatsHomeView: View {
    @EnvironmentObject private var legacy: LegacyConsoleChatStore
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    @State private var chooseOriginal = false

    var body: some View {
        Group {
            if legacy.hasSavedData || chooseOriginal {
                LegacyConsoleChatsView()
            } else {
                VStack(spacing: 0) {
                    Button {
                        legacy.enableLegacy()
                        chooseOriginal = true
                    } label: {
                        Label("Подключить прежний чат Console", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WalletTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    SpyderDevnetChatsHomeView(onOpen: onOpen, onAdd: onAdd)
                }
            }
        }
        .task { await legacy.bootstrap() }
    }
}
