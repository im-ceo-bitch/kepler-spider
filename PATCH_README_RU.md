SPYDER WALLET v0.5.2 — BUILD FIX

Проблема: `ci/verify_repo.py` отклонял SecureField с `axis: .vertical`.
Исправление: обычный однострочный SecureField; ввод сид-фразы остаётся замаскированным.

Установка: загрузить ZIP в корень `kepler-spider`; `Console — Auto Unpack Update` распакует его и удалит ZIP.
Повторно запускать `Build / Sign / TestFlight (Intel macOS)` после коммита распаковщика.

НЕ обновляет `.github/workflows`, Apple signing, seed-storage, сервер, `project.yml`.
НЕ является подтверждением полноценной Xcode-сборки.

Проверено локально: синтаксис 17 Swift файлов через `swiftc -frontend -parse`,
зеркальные проверки `ci/verify_repo.py`, `node --check`, тест сервера,
корректное наложение ZIP без потери путей, CRC архива.

