# Административная push-рассылка — pending implementation

Источник: [ТЗ JOBA v1.1](spec/services-marketplace-spec-v1.ru.md), раздел 23А FR-035, API раздела 31, A17 и T20.

Сегменты страна/язык/роль; локализованные title/body; preview/test/schedule/cancel; send_at/time zone/deadline; аудит. Marketing требует действующего consent и повторной проверки suppression/quiet hours/канала на момент отправки. Отмена прекращает будущие отправки, уже принятые провайдером сообщения нельзя обещать отозвать.

Allowlist экранов: order, offer, conversation, profile, notification, subscription, help. При открытии проверяются auth, region, object access и entitlement; deep link не выдаёт права. Payload не содержит чувствительный текст/точный адрес/документы. Campaign/recipient event key обеспечивает dedupe; delivered не равно read.

Push endpoints, device tokens, scheduler, campaign UI и провайдеры не реализованы. Реальных уведомлений и сбора персональных данных нет. Частотные лимиты, предложенные в ТЗ, требуют утверждения владельца.
