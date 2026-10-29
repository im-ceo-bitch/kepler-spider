# Spyder Wallet — возврат ранее работающего Console Chat

Это исправление сохраняет `com.console.beta`, Xcode scheme, Wallet и Apple TestFlight workflow без изменений.

- Возвращены API-модели старого Console, старый Console WebSocket, хранение истории сообщений и Keychain identity.
- Использует тот же `console.server.endpoint` в UserDefaults и тот же Keychain service `com.console.beta.identity`, без замены ключей.
- Если Console ранее использовался как обновляемое приложение, и данные приложения не были стерты, экран Chats автоматически находит сохранённый профиль и подключается к прежнему серверу.
- В старом Console адрес мог попадать только в `Info.plist` при CI-сборке, а не сохраняться в UserDefaults. В таком случае после замены приложения URL нужно ввести один раз (из старого Actions Deploy/Cloudflare Dashboard). Публичный адрес нельзя достоверно вывести из ZIP репозитория.
- Старый сервер доступен только если Worker `console-realtime` продолжает работать в Cloudflare.
- Новый Spyder Chat Devnet не удалён. В новых установках доступна кнопка возврата к Console Chat.
- Никакие секреты BIP-39 не передаются на сервер мессенджера.
- Старый сервер не имеет E2E-шифрования; сообщения может читать оператор сервера. Не считайте его готовым защищённым мессенджером.
- Проект требует фактической сборки Xcode и проверки переписки между двумя iPhone. Linux swiftc -frontend -parse проверяет только синтаксис, не семантическую корректность SwiftUI/iOS.

Установи `console-update-spyder-wallet-legacy-chat-restore-v055.zip` в корень текущего репозитория (если распаковщик всё ещё использует шаблон `console-update*.zip`). При обновлении поверх текущего TestFlight-билда с тем же Bundle ID не удаляй приложение: это может очистить его UserDefaults.
