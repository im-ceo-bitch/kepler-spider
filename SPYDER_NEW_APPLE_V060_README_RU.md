# Spyder Wallet — новый Apple Developer аккаунт / TestFlight

## Что сделано

- Bundle ID iOS target: `com.spyder.wallet` (ранее `com.console.beta`).
- Отображаемое имя: `Spyder Wallet` (не менялось).
- `Console` остаётся **внутренним Xcode target / scheme / executable**, чтобы не ломать ресурсы и CI. App Store Connect определяет приложение по Bundle ID, а не по Xcode scheme.
- Базовый CURRENT_PROJECT_VERSION: `200`; workflow рассчитывает уникальный build number на каждом запуске.
- Новый неймспейс Keychain service для **нового Bundle ID**. Ключи/кошелёк старого приложения автоматически не переносятся.
- Пустых или выдуманных Apple Team ID, сертификатов и адресов доменов в проект не добавлено.
- Удалён `ITSAppUsesNonExemptEncryption=false`: для криптомессенджера и криптокошелька нельзя заранее заявлять исключение без определения Export Compliance. Ответь на вопросы Apple в App Store Connect.

## Установка — два отдельных действия

1. Загрузи `console-update-spyder-new-apple-v060.zip` **в корень** GitHub-репозитория `kepler-spider`, дождись завершения `Console — Auto Unpack Update`. ZIP содержит **только изменённые исходники и тесты**; MessageChain/Chats/Wallet API не заменяет.
2. В GitHub вручную замени **весь файл** `.github/workflows/testflight.yml` содержимым отдельного `spyder-wallet-new-apple-testflight.yml`. Защитный ZIP-распаковщик **пропускает `.github/workflows`**. Не копируй workflow в корень репозитория.

## Секреты GitHub Actions — только из НОВОГО Apple Developer аккаунта

Открой GitHub → Settings → Secrets and variables → Actions.

- `APPLE_TEAM_ID`: новый 10-символьный Team ID.
- `APP_STORE_CONNECT_KEY_ID`: Key ID **нового** App Store Connect API Key.
- `APP_STORE_CONNECT_ISSUER_ID`: Issuer ID нового ключа.
- `APP_STORE_CONNECT_API_KEY_BASE64`: .p8 в base64 (или PEM-текст).
- `APPLE_DISTRIBUTION_P12_BASE64`: новый Apple Distribution сертификат **с приватным ключом** в base64.
- `APPLE_DISTRIBUTION_P12_PASSWORD`: пароль .p12.
- `APPLE_APPSTORE_PROFILE_BASE64`: App Store Connect provisioning profile, скачанный для `com.spyder.wallet`, в base64.

Профиль должен соответствовать **именно** .p12 и новому Team ID. Секреты и .p8/.p12/.mobileprovision **никогда** не добавляй в ZIP, коммиты или сообщения чата. Экспорт старого Apple ID не подходит.

## Как запустить

1. GitHub Actions → `Spyder Wallet — New Apple ID TestFlight (Intel)` → Run workflow → `build_only = true`.
2. Только если зелёная Debug+Release iOS Simulator сборка: `build_only = false`.
3. Workflow проверит новый профиль, сертификат, подпишет архив Apple Distribution и загрузит через App Store Connect API.
4. В App Store Connect → Spyder Wallet → TestFlight проверь обработку билда; наличие Build-only зелёной галочки **не означает** TestFlight upload.

Если App Store Connect не принимает приложение, проверь App record с Bundle ID `com.spyder.wallet`, актуальные соглашения, роль/доступ API, регистрацию App ID и Export Compliance.

## Apple Capabilities

Приоритет первой отправки — сборка, подпись и регистрация под новым идентификатором. Никаких фальшивых `aps-environment`, `com.apple.developer.associated-domains`, `App Groups` или NFC/PTT entitlements только для галочки не добавлено: это требует реальных доменов, App Groups, отдельных targets и валидного provisioning profile. Capabilities, включённые на портале Apple, могут оставаться неиспользуемыми в первой TestFlight сборке.

## Безопасность

Текущие чаты НЕ имеют подтверждённого аудированного E2E, а экспериментальный MessageChain Relay ещё не заменяет их. Не позиционируй эту сборку как защищённую для секретов. Wallet seed не логируется и не переносится между разными Bundle IDs. Перед переходом убедись, что recovery phrase сохранена офлайн. 
