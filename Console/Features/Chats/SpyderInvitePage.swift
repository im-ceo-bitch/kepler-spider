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
    @State private var showingTouch = false
    @State private var showMyInvite = false
    @State private var showCodeEntry = false
    @State private var showRecentConnections = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Найти человека")
                            .font(.title3.bold())
                        Text("Найди друга по @username или подключись по приглашению.")
                            .font(.subheadline)
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(WalletTheme.secondary)
                        TextField("Имя пользователя (@username)", text: $lookup)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .task(id: lookup) {
                                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                                guard !Task.isCancelled else { return }
                                await chat.searchUsers(lookup)
                            }
                        if !lookup.isEmpty {
                            Button { lookup = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Очистить поиск")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    if chat.searching { ProgressView("Ищем пользователей…") }
                    ForEach(chat.searchResults) { person in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.name).font(.headline)
                                Text("@" + (person.username ?? ""))
                                    .font(.subheadline)
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer(minLength: 5)
                            Button(chat.contacts.contains(where: { $0.id == person.id }) ? "Открыть" : "Написать") {
                                if chat.contacts.contains(where: { $0.id == person.id }) { open(person) }
                                else { connectUsername(person) }
                            }
                            .buttonStyle(SpyderActionButtonStyle(.tertiary))
                            .disabled(busy)
                        }
                    }
                    if let person = connectedPeer {
                        Button { open(person) } label: {
                            Label("Открыть чат с " + person.name, systemImage: "message.fill")
                        }
                        .buttonStyle(SpyderActionButtonStyle(.primary))
                    }
                    Divider()
                    Text("Другие способы")
                        .font(.headline)
                    Button { showingTouch = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Spyder Touch").font(.subheadline.bold())
                                Text("Подключиться к человеку рядом")
                                    .font(.caption).foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .frame(minHeight: 54)
                    }
                    .buttonStyle(SpyderActionButtonStyle(.secondary))
                    .disabled(!chat.hasIdentity)

                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Считать QR с фотографии", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SpyderActionButtonStyle(.secondary))
                    .disabled(busy)

                    DisclosureGroup(isExpanded: $showCodeEntry) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Ссылка Spyder или код", text: $input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("Подключиться по коду") { connectCode() }
                                .buttonStyle(SpyderActionButtonStyle(.primary))
                                .disabled(busy || SpyderInviteLink.code(from: input) == nil)
                                .accessibilityHint(SpyderInviteLink.code(from: input) == nil
                                    ? Text("Введите действительную ссылку или код приглашения")
                                    : Text("Подключить контакт из приглашения"))
                        }
                        .padding(.top, 12)
                    } label: {
                        Label("Ввести код приглашения", systemImage: "number")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(15)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))

                    DisclosureGroup(isExpanded: $showMyInvite) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Приглашение от личности: " + chat.myName)
                                .font(.subheadline)
                                .foregroundStyle(WalletTheme.secondary)
                            if let image = qrImage {
                                Image(uiImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 195, height: 195)
                                    .padding(16)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel("QR моего приглашения")
                            }
                            if let url = SpyderInviteLink.url(code: chat.inviteCode) {
                                ShareLink(item: url) {
                                    Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(SpyderActionButtonStyle(.secondary))
                            }
                            Button {
                                UIPasteboard.general.string = chat.inviteCode
                                notice = "Код приглашения скопирован"
                            } label: {
                                Label("Скопировать код", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(SpyderActionButtonStyle(.tertiary))
                            Text("Отправляй приглашение только тем, с кем хочешь общаться.")
                                .font(.footnote)
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .padding(.top, 12)
                    } label: {
                        Label("Мой QR и приглашение", systemImage: "qrcode")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(15)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    if !chat.inviteHistory.isEmpty {
                        DisclosureGroup(isExpanded: $showRecentConnections) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(chat.inviteHistory) { event in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chat.contacts.first(where: { $0.id == event.peer_id })?.name ?? "Контакт")
                                            .font(.subheadline.weight(.medium))
                                        Text(event.direction == "incoming" ? "Входящее приглашение" : "Исходящее приглашение")
                                            .font(.caption)
                                            .foregroundStyle(WalletTheme.secondary)
                                        if let date = eventDate(event.at) {
                                            Text(date, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(WalletTheme.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            Label("Недавние подключения", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    if busy { ProgressView("Подключение…") }
                    if let notice {
                        Text(notice)
                            .font(.subheadline)
                            .foregroundStyle(WalletTheme.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Новый чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .fullScreenCover(isPresented: $showingTouch) {
                WalletTouchView { contact in
                    showingTouch = false
                    onOpen(contact)
                }.environmentObject(chat)
            }
            .task {
                if let code = chat.pendingInviteCode {
                    input = code
                    showCodeEntry = true
                    chat.pendingInviteCode = nil
                }
                makeQR()
                await chat.loadInviteSettings()
            }
            .onChange(of: chat.pendingInviteCode) { _, code in
                if let code {
                    input = code
                    showCodeEntry = true
                    chat.pendingInviteCode = nil
                }
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
                        let codes = detector.features(in: image)
                            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                            .compactMap { SpyderInviteLink.code(from: $0) }
                        guard let code = codes.first, Set(codes).count == 1 else {
                            notice = "Выбери изображение с одним QR приглашения Spyder"; return
                        }
                        input = code
                        showCodeEntry = true
                        notice = "QR прочитан. Проверь приглашение и нажми «Подключиться по коду»."
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
