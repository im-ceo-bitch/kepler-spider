# Spyder Wallet — исправленная сборка GitHub Actions / TestFlight

## Что реально показал последний лог

`logs_110350534552.zip` (28.10.2026): шаг `Compile Spyder Wallet (without signing)` завершился успешно; на шаге `Archive for iOS with automatic Apple signing` возникли ошибки:

- `Revoke certificate: Your account already has an Apple Development signing certificate for this machine, but its private key is not installed in your keychain.`
- `No profiles for 'com.console.beta' were found`.

`exit code 65` на **подписании**, а не на компиляции Swift. Не нужно отзывать Apple Development certificate или менять Bundle ID ради этой ошибки. Изменённый workflow использует детерминированную ручную подпись **Apple Distribution** для TestFlight, не требует private key от чужого Apple Development certificate и заранее проверяет входные материалы.

## Для полностью подписанной сборки нужны 7 секретов GitHub

Открой репозиторий -> Settings -> Secrets and variables -> Actions -> Repository secrets. Первые четыре у тебя уже должны быть из предыдущей сборки:

| GitHub secret | Значение |
| --- | --- |
| `APPLE_TEAM_ID` | 10-символьный Apple Developer Team ID |
| `APP_STORE_CONNECT_KEY_ID` | Key ID App Store Connect Team API Key |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID этого ключа |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Содержимое `.p8` ключа в base64 **или** исходный PEM-текст |
| `APPLE_DISTRIBUTION_P12_BASE64` | Файл **Apple Distribution** `.p12` в base64, включая private key |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | Пароль от `.p12` |
| `APPLE_APPSTORE_PROFILE_BASE64` | Файл **iOS App Store Connect** `.mobileprovision` в base64 |

**Три последние секрета — новые.** Если их нет, загрузка TestFlight физически невозможна с надёжной локальной подписью. Workflow останавливается сразу с конкретным сообщением, а не после длительной компиляции. Base64 **не является шифрованием**: никогда не коммить `.p12`, `.mobileprovision`, `.p8` и base64 секретов в исходники/ZIP и не пересылай их в чат.

## Как получить необходимые файлы один раз

1. В Apple Developer -> Certificates, Identifiers & Profiles проверь, что App ID `com.console.beta` существует в нужной Team, а в App Store Connect существует соответствующая запись приложения.
2. На доверенном Mac с Xcode и Keychain Access создай/экспортируй **Apple Distribution certificate** вместе с **private key** в файл `.p12` и установи пароль. Если сертификат уже создан на другом Mac, потребуется экспорт именно с того Mac, где хранится private key. Просто скачать `.cer` недостаточно. Создание нового сертификата возможно через Apple Developer после генерации CSR. Не отзывай существующие сертификаты без понимания последствий для других приложений.
3. На сайте Apple Developer -> Profiles -> `+` -> **App Store Connect** -> выбери App ID `com.console.beta` -> выбери **этот же Apple Distribution certificate** -> Generate -> скачай `.mobileprovision`.
4. На Mac получи текст каждого base64 значения в терминале (выполнять локально, в безопасной среде):

   ```sh
   base64 -i /path/to/AppleDistribution.p12 | tr -d '\n'
   base64 -i /path/to/SpyderWallet.mobileprovision | tr -d '\n'
   ```

5. Создай/обнови три новых GitHub secrets. Их содержимое нельзя сохранять в `README` или workflow. Пользователю с одним iPhone потребуется доверенный Mac/разработчик для подготовки сертификата и ключа один раз; сами следующие сборки могут полностью запускаться из GitHub Actions на iPhone.

Проверь полномочия используемого **Team API Key**: доступ к App Store Connect для загрузки бинарника и нужной Apple Developer Team. Разработчик без требуемых полномочий не сможет отправить сборку независимо от исходников.

## Установка исправлений

**Важно:** существующий `.github/workflows/console-auto-unpack.yml` намеренно **не разрешает** изменение файлов `.github/workflows/` из `console-update*.zip`. Это ограничение безопасности, а не ошибка. Если просто загрузить ZIP-патч, он обновит только Swift, `project.yml`, `ci/`, документацию, но **не** `testflight-ios.yml`.

**Вариант А (через имеющийся ZIP-бот + замена одного файла)**:

1. Загрузи архив `console-update-spyder-complete-fix.zip` в корень GitHub-репозитория и дождись успешного `Console — Auto Unpack Update`.
2. Открой в GitHub `.github/workflows/testflight-ios.yml`, замени **весь** файл содержимым `testflight-ios.yml` из комплекта; сделай Commit. Не добавляй его рядом под другим названием: нужен именно путь `.github/workflows/testflight-ios.yml`.
3. Настрой 3 новых секрета Apple Distribution (см. выше).
4. Actions -> `Spyder Wallet - Intel TestFlight (Verified Signing)` -> `Run workflow`, `build_only = false`. Для отдельной проверки исходников без подписи поставь `build_only = true`.

**Вариант Б (полная замена исходников)**: распакуй `spyder-wallet-complete-fixed-repository.zip`, синхронизируй все файлы с GitHub, сохрани существующие GitHub Secrets и историю git. В архиве есть уже исправленный workflow.

## Что проверено

- Swift parser на 13 Swift-файлах, структурная проверка SwiftUI исходников.
- Компиляция Debug iOS Simulator в последнем GitHub Actions логе — **успешная** (подтверждено исходным логом).
- Исправлен неподдерживаемый `SecureField(..., axis: .vertical)`.
- Проверены 46 PNG, 6 asset-манифестов, Info.plist и `server/src/index.js` (Node syntax check).
- 7 автоматизированных тестов проверки provisioning profile (team, bundle ID, сертификат, срок, тип).
- Workflow YAML и `project.yml` проверены синтаксически.

**Не проверено здесь**: Release сборка через настоящий Xcode 26 на macOS, реальное наличие / права сертификатов в твоём Apple аккаунте, загрузка в App Store Connect. Эти операции могут проверить только GitHub Actions и Apple. Обещать 100% успешный upload без этих условий некорректно.
