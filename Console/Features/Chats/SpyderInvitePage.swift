import SwiftUI
import UIKit
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct SpyderInviteEvent: Decodable, Identifiable {
    let peer_id: String
    let direction: String
    let source: String
    let at: String
    var id: String { peer_id + direction + at }
}

/// Only a contact capability is encoded. Never accepts a remote server URL or credentials.
enum SpyderInviteLink {
    static func code(from input: String) -> String? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.range(of: "^[A-Fa-f0-9]{24}$", options: .regularExpression) != nil {
            return cleaned.uppercased()
        }
        guard let parts = URLComponents(string: cleaned), parts.scheme?.lowercased() == "spyder",
              parts.host?.lowercased() == "invite", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.path.isEmpty, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              items[0].name == "code", let code = items[0].value,
              code.range(of: "^[A-Fa-f0-9]{24}$", options: .regularExpression) != nil else { return nil }
        return code.uppercased()
    }

    static func url(code: String) -> URL? {
        guard let value = Self.code(from: code) else { return nil }
        var parts = URLComponents()
        parts.scheme = "spyder"
        parts.host = "invite"
        parts.queryItems = [URLQueryItem(name: "code", value: value)]
        return parts.url
    }
}

struct SpyderInvitePage: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (WalletContact) -> Void
    @State private var lookup = ""
    @State private var input = ""
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var notice: String?
    @State private var connectedPeer: SpyderChatPerson?
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Приглашение от текущей личности")
                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                    Text(chat.myName).font(.title2.bold())
                    if let image = qrImage {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 24))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("QR приглашения Spyder")
                    }
                    Text("QR и ссылка дают доступ к подключению этой личности. Отправляй их тем, с кем хочешь общаться.")
                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                    if let url = SpyderInviteLink.url(code: chat.inviteCode) {
                        ShareLink(item: url) { Label("Поделиться ссылкой", systemImage: "square.and.arrow.up") }
                        Text("Ссылка открывается при установленном Spyder Wallet.")
                            .font(.caption).foregroundStyle(WalletTheme.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = chat.inviteCode
                        notice = "Код скопирован"
                    } label: { Label("Скопировать код Spyder ID", systemImage: "doc.on.doc") }
                    Divider()
                    Text("Подключить по QR, ссылке или коду").font(.headline)
                    TextField("Ссылка Spyder или код", text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Считать QR с изображения", systemImage: "qrcode.viewfinder")
                    }
                    Button("Подключить") { connectCode() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || SpyderInviteLink.code(from: input) == nil)
                    Divider()
                    Text("Найти по @username").font(.headline)
                    TextField("@username", text: $lookup)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .task(id: lookup) {
                            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                            guard !Task.isCancelled else { return }
                            await chat.searchUsers(lookup)
                        }
                    if chat.searching { ProgressView() }
                    ForEach(chat.searchResults) { person in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.name).font(.headline)
                                Text("@" + (person.username ?? "")).font(.caption).foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer()
                            Button(chat.contacts.contains(where: { $0.id == person.id }) ? "Открыть" : "Написать") {
                                if chat.contacts.contains(where: { $0.id == person.id }) { open(person) }
                                else { connectUsername(person) }
                            }.disabled(busy)
                        }
                    }
                    if let person = connectedPeer {
                        Button { open(person) } label: {
                            Label("Открыть чат: " + person.name, systemImage: "message.fill")
                        }.buttonStyle(.borderedProminent)
                    }
                    if busy { ProgressView("Подключение…") }
                    if let notice { Text(notice).font(.callout) }
                    Divider()
                    Toggle("Ограничить неизвестных", isOn: Binding(
                        get: { chat.limitUnknownContacts },
                        set: { enabled in Task { await chat.setLimitUnknownContacts(enabled) } }
                    ))
                    Text("При включении новые контакты смогут подключиться только по твоему коду, QR или ссылке. Поиск по имени не даёт разрешения на подключение.")
                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                    if !chat.inviteHistory.isEmpty {
                        Text("Недавние подключения").font(.headline)
                        ForEach(chat.inviteHistory) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chat.contacts.first(where: { $0.id == event.peer_id })?.name ?? "Контакт")
                                Text((event.direction == "incoming" ? "Входящее" : "Исходящее") +
                                     (event.source == "username" ? " · @username" : " · приглашение"))
                                    .font(.caption).foregroundStyle(WalletTheme.secondary)
                                if let date = eventDate(event.at) {
                                    Text(date, style: .date).font(.caption2).foregroundStyle(WalletTheme.secondary)
                                }
                            }
                        }
                    }
                }
                .foregroundStyle(WalletTheme.ink).padding(22)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Пригласить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task {
                if let code = chat.pendingInviteCode { input = code; chat.pendingInviteCode = nil }
                makeQR()
                await chat.loadInviteSettings()
            }
            .onChange(of: chat.pendingInviteCode) { _, code in
                if let code { input = code; chat.pendingInviteCode = nil }
            }
            .onChange(of: photo) { _, item in
                Task {
                    guard let item else { return }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
                              let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
                            notice = "Не удалось прочитать изображение"; return
                        }
                        let codes = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                            .compactMap { SpyderInviteLink.code(from: $0) }
                        guard let code = codes.first, Set(codes).count == 1 else {
                            notice = "Выбери изображение с одним QR приглашения Spyder"; return
                        }
                        input = code
                        notice = "QR прочитан. Нажми «Подключить» от имени текущей личности."
                    } catch { notice = "Не удалось загрузить изображение" }
                }
            }
            .alert("Spyder Chat", isPresented: Binding(
                get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } }
            )) { Button("Понятно", role: .cancel) { chat.errorMessage = nil } }
                message: { Text(chat.errorMessage ?? "") }
        }
    }

    private func eventDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func makeQR() {
        guard let url = SpyderInviteLink.url(code: chat.inviteCode) else { return }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return }
        qrImage = UIImage(cgImage: image)
    }

    private func connectCode() {
        busy = true
        Task {
            if await chat.invite(input) {
                notice = "Контакт подключён. Чат доступен в списке переписок."
                input = ""
                connectedPeer = chat.lastConnectedPerson
                await chat.loadInviteSettings()
            }
            busy = false
        }
    }

    private func connectUsername(_ person: SpyderChatPerson) {
        busy = true
        Task {
            if await chat.inviteUsername(person.username ?? "") {
                connectedPeer = person
                notice = "Контакт подключён"
                await chat.loadInviteSettings()
            }
            busy = false
        }
    }

    private func open(_ person: SpyderChatPerson) {
        onOpen(WalletContact(id: person.id, name: person.name,
            handle: person.username.map { "@" + $0 } ?? "", letter: String(person.name.prefix(1)), preview: "", time: ""))
    }
}
