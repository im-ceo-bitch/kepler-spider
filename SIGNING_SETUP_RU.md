# Spyder Wallet — подпись нового Apple аккаунта

Это актуальная инструкция для `com.spyder.wallet`. Не используй старые профили `com.console.beta`.

Полный порядок действий: [SPYDER_NEW_APPLE_V060_README_RU.md](SPYDER_NEW_APPLE_V060_README_RU.md).

1. Создать App Store Connect App Record c Bundle ID `com.spyder.wallet`.
2. Создать в **новой Apple Team** Apple Distribution certificate с приватным ключом и экспортировать `.p12`.
3. Создать App Store Connect provisioning profile для `com.spyder.wallet`, используя **тот же сертификат**.
4. Создать App Store Connect Team API Key с правами загрузки сборок.
5. Записать в GitHub Actions Secrets семь значений: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`, `APPLE_DISTRIBUTION_P12_BASE64`, `APPLE_DISTRIBUTION_P12_PASSWORD`, `APPLE_APPSTORE_PROFILE_BASE64`.
6. Удалить старые `spyder-wallet-testflight-v1 2.yml` и `spyder-wallet-testflight-v2.yml` вручную из `.github/workflows/`.
7. Добавить единственный `.github/workflows/spyder-wallet-testflight.yml` вручную: ZIP-распаковщик защищает workflows от изменений.
8. Залить `console-update-spyder-testflight-ready.zip` в корень репозитория и дождаться зелёной Auto Unpack Update.
9. Запустить `Spyder Wallet - TestFlight Release` через Actions → Run workflow. Режима build-only нет: успешный запуск отправляет архив Apple на обработку.

Версия меняется **только** в `project.yml` (`MARKETING_VERSION: "1.0"`). Номер сборки берётся из `github.run_number`, начиная с 1 для нового workflow; при повторном запуске неудачной попытки выбирай `Run workflow`, а не `Re-run jobs`. Номер автоматически увеличивается при новом запуске, включая неудачные.

После выполнения `Upload` Apple может ещё обрабатывать сборку, поэтому её появление во вкладке TestFlight не мгновенное. Требуется действующий App Store Connect App Record и корректные права ключа.

Никогда не коммить ключи и сертификаты, и не передавай содержимое Secrets в переписке.
