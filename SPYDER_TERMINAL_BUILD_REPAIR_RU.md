# Spyder CI / Terminal integration hotfix (2026-11-01)

Основание: лог `logs_111983998579.zip`, шаг `Verify source and run unit tests`, 9 FAIL из 84. Код Xcode не компилировался.

## Исправления
- `WalletRootView.swift`: сохраняются маршруты Control Center, Security Center, Address Book, Spyder ID, Wallet Home и Chat v2 с Terminal UI. Переходы из Control Center выполняются после dismiss, чтобы не конфликтовали два modal presentation. Push deep-link сохранён.
- `server/src/chat.mjs` и `apns.mjs`: восстановлены авторизованные настройки фирменных APNs-звуков, тестовый push и изменение имени; не меняются `wrangler.toml`, классы Durable Objects или ключи.
- `ci/tests/*`: синхронизированы устаревшие статические проверки с текущим UI: Control Center может заменять аватар в шапке кошелька, при этом анимация сохраняется в Spyder ID; отсутствие прямого вызова звука в ChatDetail допускается только при наличии явного успешного haptic. Проверки auth, ciphertext-only и наличия звуковых CAF остаются.

## Ограничения
Нет подтверждённого полного `xcodebuild` на macOS. Не следует считать релиз проверенным до build-only CI и TestFlight. Не применяйте старые конфликтующие ZIP после этого патча.

## Установка
Сохранить `console-update-spyder-terminal-ci-merge-fix-20261101.zip` в корне `main`, выполнить распаковку, затем запустить НОВЫЙ build-only workflow, а после успешной сборки TestFlight.
