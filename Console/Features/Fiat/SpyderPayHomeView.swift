import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import SpyderPayKit

@MainActor
struct SpyderPayHomeView: View {
    @ObservedObject var model:SpyderPayModel
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden=false
    @State private var qr=""
    @State private var photo:PhotosPickerItem?
    @State private var inputNotice:String?
    @State private var camera=false
    private enum Confirmation {
        case pay, revoke(String), transfer(String, Int64), cancelTransfer
        var title:String {switch self {case .pay:return "Подтвердить тестовую оплату?";case .revoke:return "Отозвать тестовую карту?";case .transfer:return "Подтвердить тестовый перевод?";case .cancelTransfer:return "Отменить неопределённый перевод?"}}
    }
    @State private var confirmation:Confirmation?
    @State private var transferTarget=""
    @State private var transferAmount=""
    @State private var copied=false
    @ScaledMetric(relativeTo:.largeTitle) private var balanceSize:CGFloat=42
    private let corner=WalletTheme.cornerRadius

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:20) {
                header
                if !model.configured {unconfigured}
                else if !model.connected {login}
                else {
                    if let notice=model.notice {noticeView(notice)}
                    if model.storageBlocked {noticeView("Не удалось проверить сохранённые операции. Новые платежи заблокированы до восстановления данных.")}
                    if model.pendingElsewhere {noticeView("Есть незавершённая оплата на другом счёте. Выберите его и проверьте результат.")}
                    if let pending=model.pending {pendingView(pending)}
                    if let pending=model.pendingTransfer {pendingTransferView(pending)}
                    switch model.page {
                    case .home: home
                    case .payment: payment
                    case .transfer: transferPage
                    case .history: history
                    case .card: card
                    }
                }
                if model.busy {ProgressView("Выполняется защищённый запрос…").frame(maxWidth:.infinity).padding(.vertical,12)}
            }
            .padding(.horizontal,WalletTheme.pageInset)
            .padding(.top,8).padding(.bottom,24)
            .frame(maxWidth:700)
            .frame(maxWidth:.infinity)
        }
        .background(WalletTheme.canvas)
        .refreshable {if model.connected {model.refresh()}}
        .confirmationDialog(LocalizedStringKey(confirmation?.title ?? "Подтверждение"),isPresented:Binding(get:{confirmation != nil},set:{if !$0 {confirmation=nil}}),titleVisibility:.visible,presenting:confirmation) { item in
            switch item {
            case .pay: Button("Подтвердить и пройти MFA") {model.pay()}
            case .revoke(let id): Button("Отозвать карту",role:.destructive) {model.revoke(id)}
            case .transfer(let target,let amount): Button("Подтвердить и пройти MFA") {model.transfer(target:target,amount:amount)}
            case .cancelTransfer: Button("Отменить исходный перевод",role:.destructive) {model.recoverTransfer(cancel:true)}
            }
            Button("Закрыть",role:.cancel){}
        } message: {item in
            switch item {
            case .pay:
                if let p=model.preview {Text("\(p.amount.formatted()) UZS · получатель \(p.merchant_account). Это тестовая операция без реальных денег.")}
            case .revoke: Text("Для отзыва потребуется повторная аутентификация. Это не блокирует криптовалютный кошелёк и не меняет его ключи.")
            case .transfer(let target,let amount):Text("\(amount.formatted()) UZS на счёт \(target). Проверьте идентификатор получателя. Только тестовые UZS.")
            case .cancelTransfer:Text("Если списание уже совершено, сервер вернёт подтверждённую проводку. Если нет, он заблокирует выполнение исходного запроса. Это не возврат средств.")
            }
        }
        .onChange(of:photo) {_,item in
            guard let item else {return}
            Task { @MainActor in
                defer {photo=nil}
                do {
                    guard let data=try await item.loadTransferable(type:Data.self),let token=SpyderPayQRInput.fromPhoto(data) else {inputNotice="На фото не найден один корректный QR-счёт SpyderPay.";return}
                    qr=token;inputNotice=nil
                } catch {inputNotice="Не удалось прочитать фотографию."}
            }
        }
        #if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
        .sheet(isPresented:$camera) {
            NavigationStack {
                SpyderPayCameraScanner(onToken:{value in qr=value;camera=false;inputNotice=nil},onFailure:{camera=false;inputNotice="Камера недоступна. Используйте фото или введите код."})
                    .navigationTitle("QR-счёт")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {ToolbarItem(placement:.cancellationAction){Button("Закрыть"){camera=false}}}
            }
        }
        #endif
        .onChange(of:model.connected) {_,connected in if !connected {qr="";photo=nil;camera=false;inputNotice=nil;confirmation=nil;transferTarget="";transferAmount="";copied=false}}
    }
    private var header:some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:5) {
                Text("SpyderPay").font(.largeTitle.bold()).foregroundStyle(WalletTheme.ink)
                Label("Тестовая среда · UZS",systemImage:"shield.lefthalf.filled").font(.subheadline).foregroundStyle(WalletTheme.secondary)
            }
            Spacer()
            if model.connected {
                Button {model.lock()} label:{Image(systemName:"rectangle.portrait.and.arrow.right").font(.title3).frame(width:44,height:44).background(WalletTheme.surface,in:Circle())}
                    .accessibilityLabel("Выйти из SpyderPay")
                    .disabled(model.busy)
            }
        }
    }
    private var unconfigured:some View {
        VStack(alignment:.leading,spacing:16) {
            Image(systemName:"lock.shield").font(.system(size:33,weight:.medium)).foregroundStyle(WalletTheme.ink)
            Text("Платёжный контур не подключён").font(.title2.bold())
            Text("В этой сборке не настроены защищённый адрес API и провайдер идентификации SpyderPay. Балансы и операции не имитируются. Криптокошелёк продолжает работать независимо.").font(.body).foregroundStyle(WalletTheme.secondary)
            Divider()
            Label("Никаких реальных сумовых платежей",systemImage:"checkmark.shield").font(.subheadline)
            Label("Ключи криптокошелька не передаются",systemImage:"key").font(.subheadline)
            Divider()
            Text("Возможности после подключения тестового контура").font(.headline)
            Label("Сумовый счёт и история проводок",systemImage:"wallet.pass")
            Label("QR-счёт, MFA и восстановление чека",systemImage:"qrcode.viewfinder")
            Label("Регистрация и отзыв тестовой Spider Card",systemImage:"creditcard")
        }.padding(20).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
    }
    private var login:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Войти в платёжный счёт").font(.title2.bold())
            Text("Используется отдельная идентификация SpyderPay. Seed-фраза и приватные ключи не нужны. Все денежные операции в этой версии тестовые.").foregroundStyle(WalletTheme.secondary)
            if let notice=model.notice {noticeView(notice)}
            Button {model.login()} label:{Label("Войти безопасно",systemImage:"lock.shield").frame(maxWidth:.infinity)}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(model.busy)
        }.padding(20).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
    }
    private func noticeView(_ text:String)->some View {
        Label(LocalizedStringKey(text),systemImage:"info.circle").font(.subheadline).foregroundStyle(WalletTheme.ink).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
    }
    private func money(_ amount:Int64)->String {privacyHidden ? "•••• UZS" : amount.formatted()+" UZS"}
    private func accountLabel(_ id:String)->String {String(id.prefix(8))+"…"+String(id.suffix(4))}
    private func status(_ raw:String)->String {switch raw {case "active":return "Активен";case "frozen":return "Заморожен";case "closed":return "Закрыт";default:return "Недоступен"}}
    @ViewBuilder private var accountPicker:some View {
        if !model.accounts.isEmpty {
            Menu {
                ForEach(model.accounts,id:\.id) {account in Button {model.select(account.id)} label:{if account.id==model.selectedID {Label(accountLabel(account.id)+" · "+status(account.status),systemImage:"checkmark")} else {Text(accountLabel(account.id)+" · "+status(account.status))}}}
            } label: {
                HStack {Image(systemName:"wallet.pass");Text(model.selected.map{accountLabel($0.id)} ?? "Выбрать счёт").monospacedDigit();Spacer();Image(systemName:"chevron.down").font(.caption.bold())}
                    .foregroundStyle(WalletTheme.ink).padding(14).frame(minHeight:44).background(WalletTheme.canvas,in:RoundedRectangle(cornerRadius:12))
            }.disabled(model.busy).accessibilityLabel("Выбрать сумовый счёт")
        }
    }
    private var home:some View {
        VStack(alignment:.leading,spacing:20) {
            if let a=model.selected {
                VStack(alignment:.leading,spacing:14) {
                    HStack {Text("Тестовый баланс").font(.subheadline).foregroundStyle(WalletTheme.secondary);Spacer();Button{privacyHidden.toggle()}label:{Image(systemName:privacyHidden ? "eye.slash":"eye").frame(width:44,height:44)}.accessibilityLabel(privacyHidden ? "Показать баланс":"Скрыть баланс")}
                    Text(money(a.balance)).font(.system(size:balanceSize,weight:.semibold)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                    Text(LocalizedStringKey(status(a.status))).font(.footnote).foregroundStyle(WalletTheme.secondary)
                    if !model.accountsFresh {Text("Баланс не обновлён. Новые операции недоступны.").font(.footnote).foregroundStyle(.red)}
                    accountPicker
                }.padding(18).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    action("Оплатить QR",symbol:"qrcode.viewfinder",page:.payment)
                    action("Перевести",symbol:"arrow.left.arrow.right",page:.transfer)
                    action("История",symbol:"clock",page:.history)
                    action("Spider Card",symbol:"creditcard",page:.card)
                }
                VStack(alignment:.leading,spacing:8) {
                    Text("Получить тестовый перевод").font(.headline)
                    Text(a.id).font(.footnote.monospaced()).textSelection(.enabled)
                    Button {UIPasteboard.general.string=a.id;copied=true} label:{Label(copied ? "Скопировано":"Скопировать ID счёта",systemImage:copied ? "checkmark":"doc.on.doc").frame(maxWidth:.infinity)}.buttonStyle(SpyderActionButtonStyle(.secondary))
                    Text("Внутренний идентификатор SpyderPay, не номер банковской карты.").font(.footnote).foregroundStyle(WalletTheme.secondary)
                }.padding(16).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
                VStack(alignment:.leading,spacing:10) {
                    Text("Последние операции").font(.title3.bold())
                    if let activity=model.activity {
                        if activity.activity.isEmpty {Text("Проводок пока нет.").foregroundStyle(WalletTheme.secondary)}
                        ForEach(Array(activity.activity.prefix(4))) {item in activityRow(item)}
                        if activity.activity.count>4 {Button("Все последние операции"){model.open(.history)}.buttonStyle(SpyderActionButtonStyle(.secondary))}
                    } else {Text("История ещё не загружена.").font(.subheadline).foregroundStyle(WalletTheme.secondary)}
                }
            } else {
                Text("Сумовый счёт ещё не создан").font(.title2.bold())
                Text("В тестовой среде счета открывает уполномоченный оператор. Приложение не создаёт деньги и не подставляет тестовый баланс.").foregroundStyle(WalletTheme.secondary)
                action("Spider Card",symbol:"creditcard",page:.card)
            }
            Button {model.refresh()}label:{Label("Обновить данные",systemImage:"arrow.clockwise").frame(maxWidth:.infinity)}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(model.busy)
            Text("Пополнение и внешние банковские переводы и коммерческий приём платежей недоступны до подключения разрешённой инфраструктуры. Криптоактивы не конвертируются в UZS автоматически.").font(.footnote).foregroundStyle(WalletTheme.secondary)
        }
    }
    private func action(_ title:String,symbol:String,page:SpyderPayModel.Page)->some View {
        Button {model.open(page)} label:{VStack(spacing:8){Image(systemName:symbol).font(.title2);Text(LocalizedStringKey(title)).font(.footnote.weight(.medium)).multilineTextAlignment(.center)}.frame(maxWidth:.infinity,minHeight:80).padding(.horizontal,4).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))}.buttonStyle(.plain).disabled(model.busy)
    }
    private func sectionTitle(_ title:String)->some View {
        HStack {Button{model.open(.home)}label:{Image(systemName:"chevron.left").font(.headline).frame(width:44,height:44).background(WalletTheme.surface,in:Circle())}.accessibilityLabel("На главную SpyderPay").disabled(model.busy);Text(LocalizedStringKey(title)).font(.title2.bold());Spacer()}
    }
    private func pendingView(_ pending:PaymentIntent)->some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Проверка незавершённой оплаты",systemImage:"clock.badge.exclamationmark").font(.headline)
            Text(money(pending.amount)).font(.title2.bold())
            Text("Исходный счёт: "+accountLabel(pending.invoice)).font(.footnote).foregroundStyle(WalletTheme.secondary)
            Text("Не оплачивайте повторно, пока сервер не подтвердит итог.").font(.subheadline)
            Button("Проверить результат"){model.recover()}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(model.busy)
        }.padding(16).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
    }
    private var payment:some View {
        VStack(alignment:.leading,spacing:16) {
            sectionTitle("Оплата")
            if let receipt=model.receipt {receiptView(receipt)}
            else if model.pendingOperation==nil && !model.pendingElsewhere && !model.storageBlocked {
                if let p=model.preview {
                    VStack(alignment:.leading,spacing:12) {
                        Label("Счёт проверен сервером",systemImage:"checkmark.shield").font(.subheadline)
                        Text(p.amount.formatted()+" UZS").font(.largeTitle.bold()).monospacedDigit()
                        Text("Получатель (ID счёта продавца)").font(.caption).foregroundStyle(WalletTheme.secondary)
                        Text(p.merchant_account).font(.footnote.monospaced()).textSelection(.enabled)
                        Text("Номер счёта: "+p.id).font(.footnote).textSelection(.enabled)
                        Text("Действует до: "+formatDate(p.expires_at)).font(.footnote).foregroundStyle(WalletTheme.secondary)
                        Text("Счёт списания").font(.subheadline.bold());accountPicker
                        Text("Подтверждение через MFA. Оплата только тестовыми UZS.").font(.subheadline).foregroundStyle(WalletTheme.secondary)
                        if !model.paymentReady && !model.busy {Text("Оплата недоступна: проверьте баланс, статус счёта и срок действия.").font(.footnote).foregroundStyle(.red)}
                        Button("Подтвердить оплату"){confirmation = .pay}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(!model.paymentReady)
                        Button("Отмена"){model.clearPreview();qr=""}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(model.busy)
                    }.padding(16).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
                } else {
                    Text("Сканируйте QR продавца или загрузите фотографию. Сумма и получатель будут проверены платёжным сервером.").foregroundStyle(WalletTheme.secondary)
                    #if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
                    if SpyderPayCameraScanner.supported {
                        Button {openCamera()} label:{Label("Сканировать камерой",systemImage:"qrcode.viewfinder").frame(maxWidth:.infinity)}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(model.busy)
                    }
                    #endif
                    PhotosPicker(selection:$photo,matching:.images) {Label("QR из фотографии",systemImage:"photo").frame(maxWidth:.infinity)}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(model.busy)
                    TextField("Код подписанного QR-счёта",text:$qr,axis:.vertical).lineLimit(2...4).font(.footnote.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never).padding(14).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner)).disabled(model.busy)
                    if let inputNotice {noticeView(inputNotice)}
                    Button("Проверить счёт"){if let token=SpyderPayQRInput.token(qr){inputNotice=nil;model.previewQR(token)} else {inputNotice="Введите подписанный QR-код SpyderPay."}}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(model.busy || SpyderPayQRInput.token(qr)==nil || model.selected==nil)
                }
            }
        }
    }
    private func receiptView(_ r:Receipt)->some View {
        VStack(alignment:.leading,spacing:12) {
            Label(r.state=="refunded" ? "Возврат подтверждён":"Проводка подтверждена",systemImage:r.state=="refunded" ? "arrow.uturn.backward.circle":"checkmark.circle").font(.headline).foregroundStyle(.green)
            Text(money(r.amount)).font(.largeTitle.bold())
            if let refunded=r.refunded_total,refunded>0 {Text("Возвращено: "+money(refunded)).font(.subheadline)}
            Text("Получатель: "+r.merchant_account).font(.footnote).textSelection(.enabled)
            Text("Счёт: "+r.id).font(.footnote).textSelection(.enabled)
            Text("Проводка: "+r.payment_journal).font(.footnote).textSelection(.enabled)
            Text("Тестовый чек. Не подтверждает движение реальных средств.").font(.footnote).foregroundStyle(WalletTheme.secondary)
            Button("Готово"){model.clearPreview();qr="";model.open(.home)}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(model.busy)
        }.padding(16).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
    }
    private func pendingTransferView(_ intent:TransferIntent)->some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Неопределённый перевод",systemImage:"clock.badge.exclamationmark").font(.headline)
            Text(money(intent.amount)).font(.title2.bold())
            Text("Получатель: "+intent.target).font(.footnote.monospaced()).textSelection(.enabled)
            Text("Пока результат неизвестен, повторная отправка запрещена. Проверьте исходный запрос или отмените его на сервере.").font(.subheadline)
            Button("Проверить перевод"){model.recoverTransfer()}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(model.busy)
            Button("Отменить исходный запрос"){confirmation = .cancelTransfer}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(model.busy)
        }.padding(16).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
    }
    private var transferCandidate:(String,Int64)? {
        guard model.canTransfer,let account=model.selected,
              let amount=Int64(transferAmount.trimmingCharacters(in:.whitespacesAndNewlines)),amount>0,amount<=100_000_000,amount<=account.balance,
              let target=UUID(uuidString:transferTarget.trimmingCharacters(in:.whitespacesAndNewlines)),target.uuidString.lowercased() != account.id.lowercased() else {return nil}
        return (target.uuidString.lowercased(),amount)
    }
    private var transferPage:some View {
        VStack(alignment:.leading,spacing:16) {
            sectionTitle("Переводы")
            if let result=model.transferReceipt {
                VStack(alignment:.leading,spacing:12) {
                    Label(result.state=="committed" ? "Перевод подтверждён":"Перевод отменён",systemImage:result.state=="committed" ? "checkmark.circle":"xmark.circle").font(.headline)
                    Text(money(result.amount)).font(.largeTitle.bold())
                    Text("Получатель: "+result.target).font(.footnote.monospaced()).textSelection(.enabled)
                    if let journal=result.journal_id {Text("Проводка: "+journal).font(.footnote).textSelection(.enabled)}
                    Text("Только тестовые средства.").font(.footnote).foregroundStyle(WalletTheme.secondary)
                    Button("Готово"){model.clearTransferReceipt();transferTarget="";transferAmount="";model.open(.home)}.buttonStyle(SpyderActionButtonStyle(.primary))
                }.padding(16).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
            } else if model.pendingOperation==nil && !model.pendingElsewhere && !model.storageBlocked {
                Text("Перевод между тестовыми сумовыми счетами SpyderPay. Получатель должен находиться в том же платёжном контуре.").foregroundStyle(WalletTheme.secondary)
                Text("Счёт списания").font(.headline);accountPicker
                Text("ID счёта получателя").font(.subheadline.weight(.medium))
                TextField("UUID счёта",text:$transferTarget,axis:.vertical).font(.footnote.monospaced()).lineLimit(2...3).autocorrectionDisabled().textInputAutocapitalization(.never).padding(14).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner)).disabled(model.busy)
                Text("Сумма в UZS").font(.subheadline.weight(.medium))
                TextField("0",text:$transferAmount).font(.title2.monospacedDigit()).keyboardType(.numberPad).padding(14).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner)).disabled(model.busy)
                if let a=model.selected {Text("Доступно: "+money(a.balance)).font(.footnote).foregroundStyle(WalletTheme.secondary)}
                if transferCandidate==nil && !model.busy {Text("Укажите корректный ID другого счёта и целую сумму в пределах доступного баланса.").font(.footnote).foregroundStyle(WalletTheme.secondary)}
                Button("Проверить и подтвердить"){if let c=transferCandidate {confirmation = .transfer(c.0,c.1)}}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(transferCandidate==nil)
            }
        }
    }
    private var history:some View {
        VStack(alignment:.leading,spacing:14) {
            sectionTitle("История операций")
            accountPicker
            if let page=model.activity {
                if page.activity.isEmpty {Text("Операций нет.").foregroundStyle(WalletTheme.secondary)}
                ForEach(page.activity){item in activityRow(item)}
                if page.has_more {Text("Показаны последние 50 проводок. Более ранние записи пока доступны через операционную систему.").font(.footnote).foregroundStyle(WalletTheme.secondary)}
            } else {Text("История недоступна. Обновите данные.").foregroundStyle(WalletTheme.secondary)}
            Button("Обновить историю"){model.refresh()}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(model.busy)
        }
    }
    private func activityName(_ kind:String)->String {
        switch kind {case "merchant_payment":return "Оплата продавцу";case "merchant_refund":return "Возврат";case "transfer":return "Перевод";case "sandbox_credit":return "Тестовое пополнение";case "bank_reserve":return "Резерв средств";case "bank_release":return "Освобождение резерва";default:return "Бухгалтерская проводка"}
    }
    private func activityRow(_ item:LedgerActivity)->some View {
        Button {if let invoice=item.invoice_id {model.loadReceipt(invoice)}} label:{
            HStack(spacing:12) {
                Image(systemName:item.amount>0 ? "arrow.down.left":"arrow.up.right").font(.headline).frame(width:42,height:42).background(WalletTheme.surface,in:Circle())
                VStack(alignment:.leading,spacing:4){Text(LocalizedStringKey(activityName(item.kind))).font(.subheadline.weight(.medium));Text(formatDate(item.created_at)).font(.caption).foregroundStyle(WalletTheme.secondary)}
                Spacer()
                VStack(alignment:.trailing,spacing:3){Text(money(item.amount)).font(.subheadline.weight(.semibold)).monospacedDigit();if item.invoice_id != nil {Text("Чек").font(.caption).foregroundStyle(WalletTheme.secondary)}}
                if item.invoice_id != nil {Image(systemName:"chevron.right").font(.caption).foregroundStyle(WalletTheme.secondary)}
            }.frame(minHeight:54).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(item.invoice_id==nil || model.busy).accessibilityLabel(activityName(item.kind)+", "+money(item.amount))
    }
    private var card:some View {
        VStack(alignment:.leading,spacing:16) {
            sectionTitle("Spider Card")
            VStack(alignment:.leading,spacing:18) {
                HStack {Text("SPIDER CARD").font(.headline);Spacer();Image(systemName:"wave.3.right").font(.title2)}
                Spacer(minLength:14)
                Image(systemName:"cpu").font(.title)
                Text("NFC · TEST ONLY").font(.caption.weight(.medium))
            }.foregroundStyle(WalletTheme.contrast).padding(20).frame(maxWidth:.infinity,minHeight:155,alignment:.leading).background(WalletTheme.ink,in:RoundedRectangle(cornerRadius:corner))
            Text("Тестовая регистрация и отзыв карты. Даже подтверждённое владение картой не разрешает списание и не подтверждает аппаратную аттестацию.").font(.subheadline).foregroundStyle(WalletTheme.secondary)
            if model.cardsLoaded {
                if model.cards.isEmpty {Text("Нет зарегистрированных карт.").foregroundStyle(WalletTheme.secondary)}
                ForEach(model.cards){card in
                    VStack(alignment:.leading,spacing:8){HStack{Image(systemName:"creditcard");Text(accountLabel(card.id)).font(.headline);Spacer();Text(card.revoked_at==nil ? "Зарегистрирована":"Отозвана").font(.caption).foregroundStyle(WalletTheme.secondary)};Text(formatDate(card.created_at)).font(.caption).foregroundStyle(WalletTheme.secondary);if card.revoked_at==nil {Button("Отозвать карту",role:.destructive){confirmation = .revoke(card.id)}.frame(minHeight:44).disabled(model.busy)}}.padding(14).background(WalletTheme.surface,in:RoundedRectangle(cornerRadius:corner))
                }
            }
            Button("Привязать тестовую NFC-карту"){model.enrollCard()}.buttonStyle(SpyderActionButtonStyle(.primary)).disabled(!model.cardAvailable || model.busy)
            if !model.cardAvailable {Text("Для NFC необходимы совместимый Secure Element, зарегистрированный AID и разрешение Apple. В этой сборке аппаратный режим не активирован.").font(.footnote).foregroundStyle(WalletTheme.secondary)}
            Button("Обновить список карт"){model.loadCards()}.buttonStyle(SpyderActionButtonStyle(.secondary)).disabled(model.busy)
        }
    }
    private func formatDate(_ raw:String)->String {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        if let d=f.date(from:raw) ?? ISO8601DateFormatter().date(from:raw) {return d.formatted(date:.abbreviated,time:.shortened)}
        return "Дата недоступна"
    }
    private func openCamera() {
        Task { @MainActor in
            let authorized:Bool
            switch AVCaptureDevice.authorizationStatus(for:.video) {
            case .authorized:authorized=true
            case .notDetermined:authorized=await AVCaptureDevice.requestAccess(for:.video)
            default:authorized=false
            }
            if authorized {camera=true} else {inputNotice="Доступ к камере не разрешён. Используйте фото или введите код."}
        }
    }
}
