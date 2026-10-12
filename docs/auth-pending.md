# Авторизация — pending implementation

Источник: [ТЗ v1](spec/services-marketplace-spec-v1.ru.md), разделы 06–08, 24, 28, FR-006–009, T01/T15 и D17.

Целевой вход — телефон + пароль без SMS/телефонных OTP вообще, включая восстановление. Phone status unverified; формат E.164 не доказывает владение. До отправки credentials выбирается регион, автоматический поиск номера по всем базам запрещён. Google/Apple OAuth не обязательны для P1. Пароли — Argon2id, session refresh rotation/revoke и защита от перебора определены в ТЗ; предложенные параметры требуют утверждения.

Сохранённая сессия требует локального PIN или поддерживаемой FaceID/TouchID/Android biometric. Если безопасный механизм недоступен или настройка отклонена, нужен полный вход. PIN/биометрия не выдаёт серверную сессию, не обходит её expiry/revoke или отказ в доступе. Токены требуют OS secure storage; PIN/биометрические шаблоны не отправляются серверу. Проверка личности отдельна.

D17 recovery остаётся открытым: email или recovery codes только предложены, обязательная почта не согласована; reset по одному неподтверждённому номеру и SMS запрещены. Это release gate, а не ожидание самого ТЗ.

Реализованы только demo policy/state contracts и display guard в `packages/contracts/src/auth.ts`. Они не заменяют серверную авторизацию и не реализуют учетные записи, credentials, region-first, secure storage или PIN/биометрию. Register/login/recovery endpoints отсутствуют. [Поддержка и апелляции](moderation-pending.md) при санкции должны оставаться доступны — этот механизм также not_started.
