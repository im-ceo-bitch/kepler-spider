import SwiftUI
import UIKit

/// Peer metadata comes from Chat v3; fingerprints remain independent E2EE trust data.
/// Neither fabricated presence nor unimplemented media galleries are displayed.
struct SpyderContactProfilePage: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.blue.rawValue
    let contact: WalletContact
    let onOpenChat: () -> Void
    let onBlocked: () -> Void
    @State private var confirmBlock = false
    @State private var loadingKey = false

    private var peer: SpyderChatPerson? { chat.contacts.first(where: { $0.id == contact.id }) }
    private var accent: Color {
        (SpyderSignalAccent(rawValue: accentValue) ?? .blue).color
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    SpyderProfileAvatarView(motion: peer?.avatar?.motion ?? .quiet,
                        accent: peer?.avatar?.color ?? .blue, diameter: 116,
                        seed: peer?.avatar?.seed ?? "")
                    Text(contact.name)
                        .font(.system(size: 30, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(contact.handle.isEmpty ? "Username не опубликован" : contact.handle)
                        .font(.system(size: 15))
                        .foregroundStyle(WalletTheme.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)

                Button(action: onOpenChat) {
                    Label("Написать сообщение", systemImage: "message")
                        .spyderPrimaryButton()
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 13) {
                    Label("Spyder Network", systemImage: "person.crop.circle")
                        .font(.headline)
                    infoRow("Отображаемое имя", text: contact.name)
                    Divider()
                    infoRow("Username", text: contact.handle.isEmpty ? "Не указан" : contact.handle)
                }
                .padding(19)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))

                if let bio = peer?.bio, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("О себе", systemImage: "text.alignleft").font(.headline)
                        Text(bio).font(.subheadline)
                    }
                    .padding(19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))
                }
                if let status = peer?.status, !status.isEmpty {
                    Text(status).font(.subheadline).foregroundStyle(WalletTheme.secondary)
                }
                VStack(alignment: .leading, spacing: 15) {
                    Label("Безопасность переписки", systemImage: "lock.shield")
                        .font(.headline)
                    if let fingerprint = chat.peerFingerprints[contact.id] {
                        Text("Отпечаток криптографического ключа")
                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        Text(fingerprint)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Отпечаток пока не загружен. Открой чат для получения ключей и сравни отпечаток с собеседником лично.")
                            .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    }
                    Text("Шифрование само по себе не подтверждает личность человека.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .padding(19)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))

                NavigationLink {
                    SpyderChatAppearanceSettingsView(peerID: contact.id)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "paintpalette").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Оформление этого чата").font(.headline)
                            Text("Фон, сообщения и движение")
                                .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(WalletTheme.secondary)
                    }
                    .padding(19)
                    .foregroundStyle(WalletTheme.ink)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))
                }
                .buttonStyle(.plain)

                Button(role: .destructive) { confirmBlock = true } label: {
                    Label("Заблокировать контакт", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                Text("Медиа появятся после реализации зашифрованных вложений. Данные профиля предоставляются сервером и не заменяют проверку ключей.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            .padding(20)
        }
        .foregroundStyle(WalletTheme.ink)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Профиль контакта")
        .confirmationDialog("Заблокировать контакт?", isPresented: $confirmBlock) {
            Button("Заблокировать", role: .destructive) {
                Task { if await chat.block(contact.id) { onBlocked() } }
            }
        } message: {
            Text("Контакт будет удалён из доступных переписок. Криптографические ключи кошелька не изменятся.")
        }
    }

    private func infoRow(_ title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(WalletTheme.secondary)
            Spacer(minLength: 8)
            Text(text).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.subheadline)
    }
}
