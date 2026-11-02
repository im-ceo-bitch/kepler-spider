import Foundation
import SwiftUI

struct SpyderConversationSummary: Decodable, Identifiable {
    let peer: SpyderChatPerson
    let preferences: SpyderContactPreferences
    let last_message: SpyderEncryptedMessage?
    let unread_count: Int
    let online: Bool
    let typing: Bool
    var id: String { peer.id }
}

enum SpyderMessageReceipt: String {
    case sent, delivered, read
    init(deliveredAt: String?, readAt: String?) {
        self = readAt != nil ? .read : (deliveredAt != nil ? .delivered : .sent)
    }
    var title: String {
        switch self {
        case .sent: "Отправлено"
        case .delivered: "Доставлено"
        case .read: "Прочитано"
        }
    }
}

enum SpyderConversationClock {
    static func text(_ input: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: input) else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        formatter.timeStyle = Calendar.current.isDateInToday(date) ? .short : .none
        return formatter.string(from: date)
    }
}

/// Read acknowledgements require a visible portion of a verified incoming row.
enum SpyderReadViewport {
    static func visibleIDs(frames: [String: CGRect], viewport: CGRect) -> Set<String> {
        guard !viewport.isEmpty else { return [] }
        return Set(frames.compactMap { id, rect -> String? in
            guard !rect.isEmpty else { return nil }
            let intersection = viewport.intersection(rect)
            return !intersection.isNull && intersection.width > 0 &&
                intersection.height >= min(24, rect.height * 0.5) ? id : nil
        })
    }
}

private struct SpyderChatSectionActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var spyderChatSectionActive: Bool {
        get { self[SpyderChatSectionActiveKey.self] }
        set { self[SpyderChatSectionActiveKey.self] = newValue }
    }
}

struct SpyderReceiptMark: View {
    let state: SpyderMessageReceipt
    let accent: Color
    var body: some View {
        HStack(spacing: -5) {
            Image(systemName: "checkmark")
            if state != .sent { Image(systemName: "checkmark") }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(state == .read ? accent : WalletTheme.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.title)
    }
}
