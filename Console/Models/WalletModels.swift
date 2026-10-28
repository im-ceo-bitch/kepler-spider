import Foundation

// Static demo entities. None of these amounts, contacts or payments are real.
struct WalletContact: Identifiable, Hashable {
    let id: String
    let name: String
    let handle: String
    let letter: String
    let preview: String
    let time: String

    static let samples: [WalletContact] = [
        .init(id: "alex", name: "Alex", handle: "@alex", letter: "A", preview: "Получил, спасибо!", time: "9:38"),
        .init(id: "maya", name: "Maya", handle: "@maya", letter: "M", preview: "Отправишь 25 SPD?", time: "Вчера")
    ]
}

struct WalletChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let outgoing: Bool
}

enum WalletTab: Hashable { case wallet, chats }
enum WalletRoute: Hashable { case chat(WalletContact), activity }
enum WalletModal: String, Identifiable {
    case send, receive, touch, profile, request
    var id: String { rawValue }
}
