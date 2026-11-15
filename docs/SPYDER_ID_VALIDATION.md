# Проверки ZIP с Passkeys

Выполнено в Linux:
- Swift grammar parsing: 14 файлов, без синтаксических ошибок. Это не typecheck.
- JavaScript syntax check: успешно.
- Safari DOM regression tests: 9/9 успешно.
- Plist/entitlements/JSON/YAML parsing: успешно.
- Shared/SpyderID включён во все четыре target; ProvidesPasskeys включён в приложение и расширение.
- ZIP: относительные пути, без .github/workflows, CRC проверены.

Добавлены, но НЕ запущены XCTest проверки криптографии/формата WebAuthn и сейфа.
Xcode build/typecheck, Simulator, signing, реальный iPhone, серверный WebAuthn roundtrip: НЕ выполнялись (нет Xcode/iPhone в среде).
Gemini API: живой запрос не выполнялся, пользовательский API-ключ не предоставлен.

Перед использованием выполнить checklist в SPYDER_ID_INSTALL_RU.md.
