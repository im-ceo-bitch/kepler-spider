SPYDER WALLET — Hotfix v0.4.1

Исправлена ошибка Intel GitHub Actions (Xcode 26.6) из logs_110368738587.zip:
WalletCore.swiftinterface: unable to resolve module dependency 'SwiftProtobuf'.

Причина: в project.yml у target Console отсутствовала зависимость от второго бинарного продукта
Trust Wallet Core (WalletCoreSwiftProtobuf).

Изменение: к Console > dependencies добавлена строка
- package: WalletCore
  product: WalletCoreSwiftProtobuf

Эта зависимость является обязательной в официальном iOS integration guide Trust Wallet Core.

Сохранено: com.console.beta, Console scheme, CI workflow, Apple Secrets, весь SwiftUI-дизайн.

Применение: загрузить console-update-spyder-wallet-hotfix-v041.zip в корень GitHub репозитория,
дождаться Console — Auto Unpack Update, затем запустить существующий Intel TestFlight workflow.

Не загружать одновременно два console-update*.zip.

Проверка на Linux: валидность project.yml, корректная зависимость в package manifest,
Swift syntax parse и тест наложения архива. Полный Xcode compile / TestFlight требует macOS GitHub Actions.
