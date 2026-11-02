import SwiftUI

/// An independent chat account context. The home carousel remains untouched.
@MainActor
struct SpyderConversationSession: View {
    @State private var showingContact = false
    @StateObject private var session: SpyderChatStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spyderChatSectionActive) private var sectionActive
    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void

    init(contact: WalletContact, ownerPersonaID: String?, onBack: @escaping () -> Void,
         onAction: @escaping (WalletModal) -> Void, onOpenActivity: @escaping () -> Void) {
        self.contact = contact
        self.onBack = onBack
        self.onAction = onAction
        self.onOpenActivity = onOpenActivity
        let chosen = ownerPersonaID.flatMap {
            UserDefaults.standard.string(forKey: SpyderChatStore.chatPersonaKey(owner: $0, peer: contact.id))
        } ?? ownerPersonaID
        _session = StateObject(wrappedValue: SpyderChatStore(personaID: chosen,
            persistsSelection: false, conversationOwnerID: ownerPersonaID))
    }

    var body: some View {
        SpyderTerminalChatContainer(contact: contact, onBack: onBack,
            onAction: onAction, onOpenActivity: onOpenActivity, onOpenContact: { showingContact = true })
            .id(session.activePersonaID ?? "")
            .environmentObject(session)
            .navigationDestination(isPresented: $showingContact) {
                SpyderContactProfilePage(contact: contact,
                    onOpenChat: { showingContact = false }, onBlocked: onBack)
                    .environmentObject(session)
            }
            .task { await session.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    session.clearDecryptedCache()
                    Task { await session.updatePresence(active: false) }
                }
            }
            .onChange(of: sectionActive) { _, active in
                if !active { session.clearDecryptedCache() }
            }
            .onDisappear { session.clearDecryptedCache() }
    }
}
