import SwiftUI

// UI-only preview. No secrets, files, biometrics, clipboard, network or persistent storage.
// All content is fictional; closing the sheet resets presentation state.
private func sidText(_ ru: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "ru" ? ru : en
}

struct SpyderIDPreviewEntry: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Spyder ID").font(.title2.weight(.semibold))
                    Spacer()
                    Text("DEMO").font(.caption.weight(.semibold))
                }
                Text(sidText("Пароли. Документы. Всё важное рядом.", "Passwords. Documents. Your essentials together."))
                    .font(.subheadline)
                HStack {
                    Text(sidText("Посмотреть дизайн сейфа", "Explore the vault preview"))
                    Spacer()
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }.font(.footnote.weight(.medium))
            }
            .padding(20)
            .foregroundStyle(WalletTheme.contrast)
            .background(WalletTheme.ink, in: RoundedRectangle(cornerRadius: WalletTheme.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: WalletTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint(sidText("Открывает демонстрацию. Реальные данные не сохраняются.", "Opens a demo. Real data is not saved."))
    }
}

private enum SIDCategory: Int, CaseIterable, Identifiable {
    case passwords, documents, notes
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .passwords: sidText("Пароли", "Passwords")
        case .documents: sidText("Документы", "Documents")
        case .notes: sidText("Заметки", "Notes")
        }
    }
    var symbol: String {
        switch self {
        case .passwords: "key.horizontal"
        case .documents: "doc.text"
        case .notes: "note.text"
        }
    }
}

private struct SIDExample: Identifiable {
    let id: Int
    let category: SIDCategory
    let title: String
    let subtitle: String
    let symbol: String
    static var samples: [SIDExample] {
        [SIDExample(id: 0, category: .passwords, title: "Resend", subtitle: "alex@example.com", symbol: "key.horizontal"),
         SIDExample(id: 1, category: .passwords, title: "GitHub", subtitle: "alex.dev@example.com", symbol: "chevron.left.forwardslash.chevron.right"),
         SIDExample(id: 2, category: .documents, title: sidText("Страховка автомобиля", "Car insurance"), subtitle: sidText("Автомобиль · Образец PDF", "Car · Sample PDF"), symbol: "car"),
         SIDExample(id: 3, category: .documents, title: sidText("Документы на квартиру", "Property documents"), subtitle: sidText("Недвижимость · Образец PDF", "Property · Sample PDF"), symbol: "house"),
         SIDExample(id: 4, category: .notes, title: sidText("Домашний Wi-Fi", "Home Wi-Fi"), subtitle: sidText("Личная заметка · Образец", "Personal note · Sample"), symbol: "wifi")]
    }
}

private struct SIDPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .padding(WalletTheme.pageInset)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
        .background(WalletTheme.canvas)
        .foregroundStyle(WalletTheme.ink)
    }
}

private struct SIDDemoNotice: View {
    var body: some View {
        Label(sidText("Демо дизайна · Только вымышленные данные", "Design preview · Fictional data only"), systemImage: "rectangle.dashed")
            .font(.footnote).foregroundStyle(WalletTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SpyderIDVisualPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var entered = false
    @State private var category: SIDCategory = .passwords
    @State private var query = ""
    @State private var path = NavigationPath()
    private var examples: [SIDExample] {
        SIDExample.samples.filter {
            $0.category == category && (query.isEmpty || ($0.title + $0.subtitle).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if entered { vault } else { welcome }
            }
            .navigationTitle("Spyder ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(sidText("Закрыть", "Close")) { dismiss() }
                }
                if entered {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { SIDSettingsPreview() } label: {
                            Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel(sidText("Настройки сейфа", "Vault settings"))
                    }
                }
            }
        }
        .tint(WalletTheme.ink)
        .presentationDragIndicator(.visible)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { path = NavigationPath(); entered = false }
        }
    }
    private var welcome: some View {
        SIDPage {
            VStack(spacing: 20) {
                Image(systemName: "faceid").font(.system(size: 56)).accessibilityHidden(true)
                Text(sidText("Личный сейф", "Your personal vault")).font(.largeTitle.weight(.semibold))
                Text(sidText("Пароли, документы и заметки внутри Spyder Wallet.", "Passwords, documents and notes inside Spyder Wallet."))
                    .foregroundStyle(WalletTheme.secondary)
                Button(sidText("Открыть демо сейфа", "Open vault demo")) { entered = true }
                    .buttonStyle(SpyderActionButtonStyle())
                Text(sidText("Face ID пока не подключён. Эта версия показывает только дизайн.", "Face ID is not connected yet. This version previews the design only."))
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            .multilineTextAlignment(.center).padding(.vertical, 36)
            SIDDemoNotice()
        }
    }
    private var vault: some View {
        SIDPage {
            VStack(alignment: .leading, spacing: 8) {
                Text(sidText("Всё важное рядом", "Your essentials, together")).font(.largeTitle.weight(.semibold))
                SIDDemoNotice()
            }
            TextField(sidText("Найти в сейфе", "Search the vault"), text: $query)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
            Picker(sidText("Раздел сейфа", "Vault section"), selection: $category) {
                ForEach(SIDCategory.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            VStack(spacing: 0) {
                ForEach(examples) { item in
                    NavigationLink { SIDDetailPreview(item: item) } label: {
                        SIDExampleRow(item: item)
                    }.buttonStyle(.plain)
                    Divider()
                }
                if examples.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            NavigationLink { SIDAddPreview() } label: {
                Text(sidText("Добавить", "Add"))
            }.buttonStyle(SpyderActionButtonStyle())
        }
    }
}

private struct SIDExampleRow: View {
    let item: SIDExample
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol).font(.title3)
                .frame(width: 44, height: 44)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline)
                Text(item.subtitle).font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.padding(.vertical, 14).contentShape(Rectangle())
    }
}

private struct SIDDetailPreview: View {
    let item: SIDExample
    @State private var reveal = false
    var body: some View {
        SIDPage {
            SIDDemoNotice()
            Label(item.title, systemImage: item.symbol).font(.title.weight(.semibold))
            if item.category == .passwords {
                WalletCard {
                    VStack(alignment: .leading, spacing: 18) {
                        field(sidText("Сайт", "Website"), item.id == 0 ? "resend.com" : "github.com")
                        Divider()
                        field(sidText("Логин", "Username"), item.subtitle)
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sidText("Пароль", "Password")).font(.footnote).foregroundStyle(WalletTheme.secondary)
                            HStack {
                                Text(reveal ? "Demo-password-123" : "••••••••••••").font(.body.monospaced())
                                Spacer()
                                Button { reveal.toggle() } label: {
                                    Image(systemName: reveal ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44)
                                }.accessibilityLabel(sidText("Показать или скрыть пример пароля", "Show or hide the sample password"))
                            }
                        }
                    }
                }
                SIDUnavailableAction(title: sidText("Копировать пароль", "Copy password"))
                Text(sidText("Копирование и автозаполнение появятся на следующем этапе.", "Copying and AutoFill will be added in the next phase."))
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            } else if item.category == .documents {
                WalletCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(sidText("ОБРАЗЕЦ ДОКУМЕНТА", "SAMPLE DOCUMENT")).font(.caption.weight(.semibold))
                        Image(systemName: "doc.richtext").font(.system(size: 48)).accessibilityHidden(true)
                        Text(item.title).font(.title2.weight(.semibold))
                        Text(sidText("Здесь будет предпросмотр вашего PDF или фотографии.", "Your PDF or photo preview will appear here."))
                            .foregroundStyle(WalletTheme.secondary)
                        Text("PDF · DEMO").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                }
                SIDUnavailableAction(title: sidText("Поделиться документом", "Share document"))
            } else {
                WalletCard {
                    VStack(alignment: .leading, spacing: 16) {
                        field(sidText("Сеть", "Network"), "Home Network")
                        field(sidText("Пароль · пример", "Password · sample"), "demo-wifi-123")
                    }
                }
            }
        }.navigationTitle(item.category.title).navigationBarTitleDisplayMode(.inline)
    }
    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.footnote).foregroundStyle(WalletTheme.secondary)
            Text(value)
        }
    }
}

private struct SIDUnavailableAction: View {
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Button(title) {}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(true)
            Text(sidText("Пока только дизайн", "Design preview only"))
                .font(.caption).foregroundStyle(WalletTheme.secondary)
        }
    }
}

private struct SIDAddPreview: View {
    var body: some View {
        SIDPage {
            Text(sidText("Что сохраним?", "What would you like to save?")).font(.largeTitle.weight(.semibold))
            SIDDemoNotice()
            ForEach(SIDCategory.allCases) { category in
                NavigationLink { SIDEditorPreview(category: category) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: category.symbol).frame(width: 32)
                        Text(category.title).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(.vertical, 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }.navigationTitle(sidText("Добавить", "Add"))
    }
}

private struct SIDEditorPreview: View {
    let category: SIDCategory
    @State private var review = false
    var body: some View {
        SIDPage {
            SIDDemoNotice()
            Text(category == .documents ? sidText("Просто отправьте", "Just send it") : sidText("Новая запись", "New entry"))
                .font(.largeTitle.weight(.semibold))
            if category == .documents && !review {
                WalletCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("insurance-demo.pdf", systemImage: "doc.text")
                        Text(sidText("Это страховка моей машины", "This is my car insurance"))
                    }
                }
                Text(sidText("Пример добавления через личный помощник. Файлы и AI пока не подключены.", "Preview of adding via your assistant. Files and AI are not connected yet."))
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                Button(sidText("Посмотреть карточку", "Preview the card")) { review = true }
                    .buttonStyle(SpyderActionButtonStyle())
            } else {
                WalletCard {
                    VStack(alignment: .leading, spacing: 20) {
                        mockField(sidText("Название", "Name"), category == .documents ? sidText("Страховка автомобиля", "Car insurance") : sidText("Личный", "Personal"))
                        if category == .passwords {
                            mockField(sidText("Сайт", "Website"), "example.com")
                            mockField(sidText("Логин", "Username"), "alex@example.com")
                            mockField(sidText("Пароль", "Password"), "••••••••••••")
                        } else if category == .documents {
                            mockField(sidText("Категория", "Category"), sidText("Автомобиль", "Car"))
                            mockField(sidText("Файл", "File"), "insurance-demo.pdf")
                        } else {
                            mockField(sidText("Текст заметки", "Note text"), sidText("Важная информация…", "Important information…"))
                        }
                    }
                }
                Text(sidText("Поля показаны как образец. Ввод и хранение реальных данных пока недоступны.", "These are sample fields. Real input and storage are not available yet."))
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                SIDUnavailableAction(title: sidText("Сохранить", "Save"))
            }
        }.navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
    }
    private func mockField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(WalletTheme.secondary)
            Text(value).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct SIDSettingsPreview: View {
    var body: some View {
        SIDPage {
            Text(sidText("Защита и доступ", "Protection and access")).font(.largeTitle.weight(.semibold))
            SIDDemoNotice()
            WalletCard {
                VStack(spacing: 18) {
                    setting("Face ID", sidText("Не подключено", "Not connected"))
                    Divider()
                    setting(sidText("Автоблокировка", "Auto-lock"), sidText("На следующем этапе", "Next phase"))
                    Divider()
                    setting(sidText("Резервная копия", "Backup"), sidText("Не настроена", "Not configured"))
                }
            }
            NavigationLink { SIDConnectionPreview() } label: {
                HStack {
                    Text(sidText("Автозаполнение и Safari", "AutoFill and Safari"))
                    Spacer()
                    Image(systemName: "chevron.right")
                }.frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text(sidText("Демо не защищает и не сохраняет секреты. Настоящие пароли пока не добавляйте.", "This demo does not protect or save secrets. Do not add real passwords yet."))
                .font(.footnote).foregroundStyle(WalletTheme.secondary)
        }.navigationTitle(sidText("Настройки", "Settings"))
    }
    private func setting(_ name: String, _ status: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.headline)
            Text(status).font(.footnote).foregroundStyle(WalletTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SIDConnectionPreview: View {
    var body: some View {
        SIDPage {
            SIDDemoNotice()
            Text(sidText("Spyder на сайтах", "Spyder on websites")).font(.largeTitle.weight(.semibold))
            WalletCard {
                VStack(alignment: .leading, spacing: 20) {
                    Label(sidText("Вызвать Spyder в меню Safari", "Open Spyder from the Safari menu"), systemImage: "puzzlepiece.extension")
                    Text(sidText("Создать пароль → заполнить поля → подтвердить сохранение.", "Create a password → fill the fields → confirm saving."))
                    Divider()
                    Text(sidText("При следующем входе: выбрать аккаунт → Face ID → поля заполнены.", "Next sign-in: select the account → Face ID → fields filled."))
                }
            }
            Text(sidText("Это план подключения. Расширение Safari и системное автозаполнение ещё не установлены этой версией.", "This is the planned integration. This version does not install a Safari extension or system AutoFill."))
                .font(.footnote).foregroundStyle(WalletTheme.secondary)
        }.navigationTitle("Safari").navigationBarTitleDisplayMode(.inline)
    }
}
