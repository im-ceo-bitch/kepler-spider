import SwiftUI
import UIKit

/// Saved recipients are PUBLIC blockchain addresses, isolated per local wallet.
struct WalletAddressBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var addressBook: WalletAddressBookStore
    var onSelect: ((WalletAddressEntry) -> Void)? = nil
    @State private var search = ""
    @State private var showAdd = false
    @State private var pendingDelete: WalletAddressEntry?
    @State private var errorMessage: String?

    private var filtered: [WalletAddressEntry] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return addressBook.entries.filter { entry in
            if term.isEmpty { return true }
            return entry.name.localizedStandardContains(term)
                || entry.address.localizedCaseInsensitiveContains(term)
                || entry.chain.ticker.localizedCaseInsensitiveContains(term)
        }.sorted { first, second in
            first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchField
                    if let storeError = addressBook.errorMessage {
                        Label(storeError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    recipientList
                    Text("Адресная книга хранится только в Keychain этого iPhone. Адрес может быть корректным, но принадлежать мошеннику — проверяйте получателя перед отправкой.")
                        .font(.footnote)
                        .foregroundStyle(WalletTheme.secondary)
                }
                .padding(20)
                .frame(maxWidth: 700)
            }
            .foregroundStyle(WalletTheme.ink)
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Адресная книга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(addressBook.errorMessage != nil)
                        .accessibilityLabel("Добавить получателя")
                }
            }
            .sheet(isPresented: $showAdd) { WalletAddressBookAddView() }
            .confirmationDialog("Удалить получателя?", isPresented: deleteDialogPresented, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { deletePendingRecipient() }
                Button("Отмена", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Удаление адреса не влияет на блокчейн и средства.")
            }
            .alert("Не удалось изменить адресную книгу", isPresented: errorAlertPresented) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("Имя, адрес или сеть", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(15)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Поиск получателя")
    }

    @ViewBuilder private var recipientList: some View {
        if filtered.isEmpty {
            WalletCard {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 28))
                    Text(search.isEmpty ? "Нет сохранённых получателей" : "Совпадений нет")
                        .font(.headline)
                    Text("Сохраняйте проверенные публичные адреса получателей отдельно для каждого кошелька.")
                        .font(.footnote)
                        .foregroundStyle(WalletTheme.secondary)
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filtered) { entry in recipientRow(entry) }
            }
        }
    }

    private func recipientRow(_ entry: WalletAddressEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.chain.symbol)
                .font(.system(size: 19))
                .frame(width: 42, height: 42)
                .background(WalletTheme.canvas, in: Circle())
            Button { selectRecipient(entry) } label: { recipientLabel(entry) }
                .buttonStyle(.plain)
            Button { pendingDelete = entry } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Удалить получателя \(entry.name)")
        }
        .padding(14)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 21))
    }

    private func recipientLabel(_ entry: WalletAddressEntry) -> some View {
        let shortAddress = String(entry.address.prefix(10)) + "…" + String(entry.address.suffix(7))
        let subtitle = entry.chain.ticker + " · " + shortAddress
        return VStack(alignment: .leading, spacing: 5) {
            Text(entry.name)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(WalletTheme.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func selectRecipient(_ entry: WalletAddressEntry) {
        if let onSelect {
            onSelect(entry)
            dismiss()
        } else {
            UIPasteboard.general.string = entry.address
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
    private var errorAlertPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private func deletePendingRecipient() {
        guard let target = pendingDelete else { return }
        defer { pendingDelete = nil }
        do {
            try addressBook.remove(target)
        } catch let caughtError {
            self.errorMessage = caughtError.localizedDescription
        }
    }
}

struct WalletAddressBookAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var addressBook: WalletAddressBookStore
    @State private var name = ""
    @State private var chain: SpyderChain = .ethereum
    @State private var address = ""
    @State private var errorMessage: String?

    init(chain: SpyderChain = .ethereum, address: String = "") {
        _chain = State(initialValue: chain)
        _address = State(initialValue: address)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        WalletAddressValidator.check(address, for: chain) == .valid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Получатель") { recipientFields }
                Section { validationNotes }
            }
            .navigationTitle("Новый получатель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { saveRecipient() }.disabled(!canSave)
                }
            }
            .alert("Не удалось сохранить", isPresented: errorAlertPresented) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var recipientFields: some View {
        Group {
            TextField("Имя или название", text: $name)
                .textInputAutocapitalization(.words)
                .onChange(of: name) { _, newValue in
                    if newValue.count > 48 { name = String(newValue.prefix(48)) }
                }
            Picker("Сеть", selection: $chain) {
                ForEach(SpyderChain.allCases) { item in
                    Text(item.name).tag(item)
                }
            }
            TextField("Публичный адрес", text: $address, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(2...4)
            Button("Вставить из буфера") {
                if let value = UIPasteboard.general.string {
                    address = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    private var validationNotes: some View {
        Group {
            if case .invalid(let reason) = WalletAddressValidator.check(address, for: chain), !address.isEmpty {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text("Проверяется контрольная сумма адреса Bitcoin и длина ключа Solana. Для Ethereum проверяется формат, но не EIP-55 checksum. Это не подтверждает владельца.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func saveRecipient() {
        do {
            try addressBook.add(name: name, chain: chain, address: address)
            dismiss()
        } catch let caughtError {
            self.errorMessage = caughtError.localizedDescription
        }
    }
}
