import SwiftUI

struct ChatsHomeView: View {
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    @State private var query = ""

    private var filtered: [WalletContact] {
        guard !query.isEmpty else { return WalletContact.samples }
        return WalletContact.samples.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.handle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Chats")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(WalletTheme.ink)
                    Spacer()
                    Button(action: onAdd) {
                        Label("Контакт", systemImage: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WalletTheme.ink)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .overlay(Capsule().stroke(WalletTheme.divider, lineWidth: 1))
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(WalletTheme.secondary)
                    TextField("Поиск по контактам", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .frame(height: 47)
                .background(WalletTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(WalletTheme.divider, lineWidth: 1))

                VStack(spacing: 0) {
                    ForEach(filtered) { contact in
                        Button { onOpen(contact) } label: {
                            contactRow(contact)
                        }
                        .buttonStyle(.plain)
                        if contact.id != filtered.last?.id {
                            Rectangle()
                                .fill(WalletTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 63)
                        }
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                WalletCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Private by design", systemImage: "lock.shield")
                            .font(.system(size: 16, weight: .semibold))
                        Text("В будущем сообщения будут зашифрованы. Каждый перевод подтверждается отдельно.")
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    .foregroundStyle(WalletTheme.ink)
                }
                WalletDemoLabel().frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
    }

    private func contactRow(_ contact: WalletContact) -> some View {
        HStack(spacing: 15) {
            Text(contact.letter)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(WalletTheme.ink)
                .frame(width: 52, height: 52)
                .background(WalletTheme.divider, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(contact.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WalletTheme.ink)
                    Spacer()
                    Text(contact.time)
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                HStack {
                    Text(contact.preview)
                        .font(.system(size: 14))
                        .foregroundStyle(WalletTheme.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WalletTheme.secondary)
                }
            }
        }
        .frame(minHeight: 85)
        .contentShape(Rectangle())
    }
}
