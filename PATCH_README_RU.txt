Spyder Wallet v0.5.3 — Xcode SwiftCompile hotfix

Причина: Swift compiler failed in Console/SpiderDevnet/SpiderProtocolV1.swift:214.
В catch системная константа error была ошибочно использована как изменяемое свойство класса.
Исправлено: self.error = error.localizedDescription.

УСТАНОВКА
1. Загрузить ZIP console-update-spyder-wallet-buildfix-v053.zip в корень репозитория kepler-spider.
2. Убедиться, что Auto Unpack Update завершился успешно.
3. Проверить в GitHub, что Console/SpiderDevnet/SpiderProtocolV1.swift содержит self.error.
4. Запустить имеющийся TestFlight workflow сначала с build_only=true.

Проверки: извлечены v0.5 + v0.5.2, наложен этот файл; swiftc -frontend -parse по 17 Swift-файлам; изолированный Swift typecheck и запуск ветки catch; npm run check чата; ZIP CRC.
Полная Xcode сборка недоступна из Linux; результат всей iOS сборки не гарантирован.
Никакие файлы workflows, Bundle ID, Apple Secrets или блокчейн-репозиторий не меняются.
