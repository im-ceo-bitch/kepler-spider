# SpyderPay Fiat / Crypto — интеграция в Console

Существующая навигация, криптографические ключи и чаты сохраняются. Fiat — отдельный режим общего WalletRootView; по умолчанию Crypto. Балансы и история загружаются только из совместимого sandbox API, без вымышленных остатков. При отсутствии конфигурации Fiat явно недоступен.

## Установка
1. В kepler-pay установить spyderpay-core-update-v012.zip, дождаться успешного Verify/Apply.
2. В kepler-spider загрузить только console-update-spyderpay-v012.zip в корень. Постоянный console-auto-unpack.yml неизменен. Для появления функции в установленном приложении потребуется обычная сборка Xcode/TestFlight.

## Staging-конфигурация
Значения SPYDERPAY_API_ORIGIN, SPYDERPAY_OIDC_ISSUER, SPYDERPAY_OIDC_AUTHORIZATION_ENDPOINT, SPYDERPAY_OIDC_TOKEN_ENDPOINT, SPYDERPAY_OIDC_CLIENT_ID, SPYDERPAY_OIDC_MFA_ACR, SPYDERPAY_OIDC_SCOPE, SPYDERPAY_OIDC_AUDIENCE задаются доверенной подписанной конфигурацией сборки. Не передавать серверные HMAC-ключи или клиентский секрет на телефон. Здесь адресов и credentials нет. При настройке они могут поставляться следующим ZIP без редактирования исходников пользователем.

IdP должен поддерживать public native client Authorization Code + PKCE S256, redirect com.spyder.wallet.pay://oauth/callback, короткоживущие подписанные RFC9068 access tokens, issuer/audience/client_id/sid, MFA acr, auth_time, уникальный jti и новый MFA token в той же сессии. Параметр audience зависит от IdP; необходимо проверить совместимость на staging. Backend валидирует подпись и права; клиентские проверки claims не заменяют серверную авторизацию. Access tokens только в памяти. При блокировке, уходе с режима и фоне они сбрасываются. Pending ID в отдельном device-only Keychain; seed/private keys не переносятся.

## Функции
Сумовые счета, история проводок, QR preview (камера/фото/ввод), проверка суммы и получателя, MFA, оплата и восстановление чека. Внутренние переводы UZS по идентификатору счёта, одноразовое подтверждение, восстановление и безопасная отмена неопределённой операции. QR не открывает URL. Запись pending до запроса; неизвестный результат блокирует новые операции на том же счёте. Карта: список и отзыв; условный Core NFC-транспорт для доказательства владения тестовой картой, не списания.

## Не активировано
Внешние банковские переводы, реальное пополнение, коммерческие QR/NFC-платежи, fiat↔crypto обмен. Для NFC необходимы зарегистрированный AID (SPYDERPAY_CARD_AID и список ISO7816 identifiers), NFCReaderUsageDescription, соответствующие entitlement и provisioning profile, реальный Secure Element и applet. Не добавлять capability до выбора карты и проверки Apple-профиля. Xcode, iPhone, реальный IdP и PostgreSQL CI обязательны для приёмки. Не готово к реальным деньгам.
