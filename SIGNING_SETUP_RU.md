# Spyder Wallet — подпись нового Apple аккаунта

Это актуальная инструкция для `com.spyder.wallet`. Не используй старые профили `com.console.beta`.

Полный порядок действий: [SPYDER_NEW_APPLE_V060_README_RU.md](SPYDER_NEW_APPLE_V060_README_RU.md).

1. Создать App Store Connect App Record c Bundle ID `com.spyder.wallet`.
2. Создать в **новой Apple Team** Apple Distribution certificate с приватным ключом и экспортировать `.p12`.
3. Создать App Store Connect provisioning profile для `com.spyder.wallet`, используя **тот же сертификат**.
4. Создать App Store Connect Team API Key с правами загрузки сборок.
5. Записать в GitHub Actions Secrets семь значений: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`, `APPLE_DISTRIBUTION_P12_BASE64`, `APPLE_DISTRIBUTION_P12_PASSWORD`, `APPLE_APPSTORE_PROFILE_BASE64`.
6. Заменить `.github/workflows/testflight.yml` отдельно; ZIP-распаковщик не меняет workflows.
7. Запустить Build-only, потом подписанную сборку.

Никогда не коммить ключи и сертификаты, и не передавай содержимое Secrets в переписке.
