# Статус реализации JOBA

Это отчет о текущем коде ветки, а не утверждение готовности полного первого релиза ТЗ v1.1. Пользователь подтвердил использование предложенных параметров как исходных; реальные платежи, рекламную сеть, Firebase и сервер предоставит позднее.

## Реализованные серверные сценарии

- Регистрация/вход номером и паролем без SMS/email, E.164/country checks, Argon2id, смена телефона/пароля с reauth, ротация и отзыв сессий.
- Доменные роли, object ownership/country scope, версия объекта, idempotency, отдельный staff login с MFA.
- Черновик и публикация заказа, актуальность ревизии отклика, атомарный выбор с assignment snapshot, начало, завершение/доработки, двусторонняя отмена и поправки, приглашения.
- Контекстные чаты, sequence/client-message dedupe, ограниченное редактирование/tombstones, read/delivered acknowledgements, durable notifications и WebSocket events.
- Двусторонние completed-order отзывы, double-blind публикация и окно исправления; отдельные likes/dislikes и organic score.
- Профили и портфолио с clean-upload gates; закрытые файлы, AES-GCM, image sanitization, scoped одноразовые ссылки; ручная ID-проверка с отдельной ролью.
- Поддержка/ограниченный pre-login recovery chat, assignment/status commands, отдельные internal notes. Автоматического сброса по неподтверждённому номеру нет.
- Модерация по версионированным словарям без пользовательского regex, quarantine/case/temporary hold, expiry без автоматического постоянного blacklist; ручные решения и апелляции.
- Append-only audit/финансовые записи, independent ad flags, админские price/config drafts и двойное подтверждение, promo timezone boundary, finite compensation grants.
- Referral attribution/qualification/redeem с бюджетом; boost capacity/reservation/verified purchase/admin provenance и eligibility/expiry.
- Outbox worker, retry/dead-letter, quiet hours и реальные provider send outcomes; export JSON job, reauth deletion request и остановка удаления при отсутствии утверждённого retention policy.

## Проверенное

13 автоматических тестов прошли на этапе проверки доменной реализации. Дополнительно прошёл HTTP/WebSocket smoke на отдельном PostgreSQL 16: auth/envelopes, ETag/304, binary upload, закрытые scanner/payment gates, выбор исполнителя и scoped событие.

Изолированный performance check: 5000 синтетических заказов, 100 последовательных warmed запросов по 20 записей, PostgreSQL 16; p50 2,69 мс, p95 10,49 мс, max 21,95 мс. Это время доменного вызова, без HTTP/сети, параллельной нагрузки, мобильного устройства и внешних API. Оно не является обещанием моментального production ответа.

Сборки API/admin/client/public прошли. Docker backend собран с закреплённым Node image и CA-бандлом TLS-прокси через build secret, запущен с временным PostgreSQL; health/bootstrap HTTP прошли.

## Что ещё требует завершения/подтверждения

- Реальные adapters/credentials и end-to-end provider проверки: платежи, рекламная SSV, Firebase, maintained AV и PDF sanitization. По умолчанию они не включены и не выдают фиктивный успех.
- Утверждённые тексты/legal/country/retention flows и региональная инфраструктура. Локальная PGlite имеет логическую country ACL, но не подтверждает физическую изоляцию четырёх регионов.
- Production hardening: распределённый rate limit, отдельные migration/runtime DB roles, полноценные schema/DTO/FK contracts, нагрузочная/penetration проверка, backup/restore, encrypted-volume/key rotation, exhaustive retention/delete по вложениям и legal holds.
- Расширение OpenAPI из текущего HTTP-инвентаря до строгих DTO всех команд; часть схем пока permissive.
- Продвинутые геофильтры, provider coupons/discount redemption и полные финансовые/аналитические отчеты; не заменять их демонстрационными значениями.
- Полная интеграция каждого экрана, поля и кнопки с API, native PIN/biometry/secure storage, все локали, visual comparison и native builds. Перенесены оригинальные web/mobile prototype sources, шрифты и графика, но это не подтверждает «всё работает» или «1в1» для готового приложения.

Репозиторий не следует объявлять полностью соответствующим ТЗ или готовым к production до закрытия этих пунктов. Пользовательские данные обычного API создаются запросами и сохраняются; тестовые записи изолированы от рабочей базы.
