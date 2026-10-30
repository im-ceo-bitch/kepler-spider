import SwiftUI

// One source of truth: the existing Console identity, contact and WebSocket protocol.
// Iumrah supplies interaction patterns only; its booking-specific API is not used here.
struct ChatsHomeView: View {
    @EnvironmentObject private var legacy: LegacyConsoleChatStore
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void

    var body: some View {
        LegacyConsoleChatsView()
            .task { await legacy.bootstrap() }
    }
}
