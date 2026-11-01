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
    @State private var error: String?

    private var filtered: [WalletAddressEntry] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return addressBook.entries
            .filter { term.isEmpty || $0.name.localizedStandardContains(term) || $0.address.localizedCaseInsensitiveContains(term) || $0.chain.ticker.localizedCaseInsensitiveContains(term) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                        TextField("Имя, адрес или сеть", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(15)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Поиск получателя")
                    if let error = addressBook.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    if filtered.isEmpty {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 28))
                                Text(search.isEmpty ? "Нет сохранённых получателей" : "Совпадений нет")
                                    .font(.headline)
                                Text("Сохраняйте проверенные публичные адреса получателей отдельно для каждого кошелька.")
                                    .font(.footnote)
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.chain.symbol)
                                        .font(.system(size: 19))
                                        .frame(width: 42, height: 42)
                                        .background(WalletTheme.canvas, in: Circle())
                                    Button {
                                        if let onSelect {
                                            onSelect(item)
                                            dismiss()
                                        } else {
                                            UIPasteboard.general.string = item.address
                                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.name).font(.system(size: 16, weight: .semibold))
                                            Text("\(item.chain.ticker) · \(item.address.prefix(10))…\(item.address.suffix(7))")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(WalletTheme.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Button { pendingDelete = item } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 15))
                                            .foregroundStyle(.red)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Удалить получателя \(item.name)")
                                }
                                .padding(14)
                                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 21))
                            }
                        }
                    }
                    Text("Адресная книга хранится только в Keychain этого iPhone. Адрес может быть корректным, но принадлежать мошеннику — проверяйте получателя перед отправкой.")
                        .font(.system(size: 12))
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
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(addressBook.errorMessage != nil)
                        .accessibilityLabel("Добавить получателя")
                }
            }
            .sheet(isPresented: $showAdd) { WalletAddressBookAddView() }
            .confirmationDialog("Удалить получателя?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    guard let target = pendingDelete else { return }
                    do { try addressBook.remove(target) }
                    catch { error = error.localizedDescription }
                    pendingDelete = nil
                }
                Button("Отмена", role: .cancel) { pendingDelete = nil }
            } message: { Text("Удаление адреса не влияет на блокчейн и средства.") }
            .alert("Не удалось изменить адресную книгу", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

struct WalletAddressBookAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var addressBook: WalletAddressBookStore
    @State private var name = ""
    @State private var chain: SpyderChain = .ethereum
    @State private var address = ""
    @State private var error: String?

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
                Section("Получатель") {
                    TextField("Имя или название", text: $name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { _, newValue in if newValue.count > 48 { name = String(newValue.prefix(48)) } }
                    Picker("Сеть", selection: $chain) {
                        ForEach(SpyderChain.allCases) { item in Text(item.name).tag(item) }
                    }
                    TextField("Публичный адрес", text: $address, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(2...4)
                    Button("Вставить из буфера") {
                        if let value = UIPasteboard.general.string { address = value.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                }
                Section {
                    if case .invalid(let reason) = WalletAddressValidator.check(address, for: chain), !address.isEmpty {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text("Проверяется контрольная сумма адреса Bitcoin и длина ключа Solana. Для Ethereum проверяется формат, но не EIP-55 checksum. Это не подтверждает владельца.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Новый получатель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        do { try addressBook.add(name: name, chain: chain, address: address); dismiss() }
                        catch { error = error.localizedDescription }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
