# STATUS — 2026-10-12

Источник: [полное ТЗ JOBA v1.1](spec/services-marketplace-spec-v1.ru.md). Это статус scaffold в feature/mobile-native-scaffold/draft PR #1, не приемка P1. Код проверен на `d5a5d18885797ecfd9aea333189ccc896093da7e`; после него до импорта ТЗ были только docs commits. Последующая branding-only правка меняет display names на JOBA; бизнес-функции не расширяет. Текущий импорт MD v1.1: `4eaede3f988b4e5a82dafa2f4fb67735d3b7411f`; branding проверен на `15401235ecbb4246ee5512f0c1acd53c99857fae`. `main` остаётся initial scaffold `5e2f4de23127e1dec9366817e2174bbdd9667bfc` до отдельного разрешённого merge.

implemented = готова указанная узкая техническая часть; partial = только модель/template/demo, бизнес-приёмка не пройдена; not_started = реализации нет. Ни один полный бизнес-FR сейчас не принимается как implemented.

| Область / FR | Статус | Фактическая граница |
|---|---|---|
| Выбранный бренд JOBA | implemented | Display name Flutter/iOS/Android и admin demo; repo/package/application IDs и signing не менялись |
| Полный исходный Markdown ТЗ JOBA v1.1 | implemented | 272305 байт; SHA256 точно совпал; текст неизменён. PDF/DOCX переданы отдельно, импорт не требуется |
| Monorepo, env placeholders, lockfiles и инструкции | implemented | npm workspace API/admin/contracts и Flutter sources; полный local stack не готов |
| API health / сборки | implemented | Только GET /health, process liveness; /orders возвращает 404; нет DB readiness |
| Mobile iOS/Android / FR-030 | partial | Native templates и demo-screen; analyze + 1 widget test прошли; native builds/signing не проверены |
| Admin / FR-027–028, FR-030 | partial | Статичный TypeScript/Vite demo; нет Next.js, employee auth/MFA, RBAC или audit |
| Contracts / FR-029 | partial | Health/country и demo auth/monetization; нет полного OpenAPI 3.1, generated clients и compatibility CI |
| Локали/страны / FR-004 | partial | Коды стран в типах/документации; нет i18n, legal versioning, справочников/вычитки |
| Auth / FR-006–008 | partial | Policy/state/display guard, тесты expiry/revoke; нет phone-password endpoints, Argon2id, region-first, session persistence, secure storage, PIN/biometric implementation |
| Монетизация / FR-031–032 | partial | Неизменяемые demo flags и shape validator, scope country/role, версия и reward examples; нет platform/placement/TTL, persistence, admin publish/rollback или entitlement engine |
| PostgreSQL/PostGIS foundation | partial | Compose template + SQL extension; не запускались, нет business tables/runner/history/integration tests |
| Портфолио исполнителя / FR-040 | not_started | Pending implementation: фото работ, название/описание проекта, категория услуги, редактирование/удаление, просмотр заказчиком в профиле, модерация материалов; требования получены в v1.1, реализации нет |
| Заказ/исполнитель/профили/поиск/отклик/invite/чат/завершение/спор/репутация / FR-001–002, FR-011–020 | not_started | Нет вертикального бизнес-сценария, данных или endpoints |
| Server roles/object access и региональная изоляция / FR-003/005 | not_started | Нет enforcement или регионального data plane |
| Подробная admin-карточка / FR-041 | not_started | Pending implementation: профиль/телефон/указанный город и страна, полный IP, UTC-входы с зоной, устройства/сессии, заказы, обращения/жалобы, блокировки; только уполномоченные MFA/RBAC, IP location approximate |
| Почта исключена; recovery без SMS/email (v1.1) | not_started | Почта не собирается и не используется для reset/support. Резервное/ручное доказательство требует решения; unverified phone не доказательство; endpoints отсутствуют |
| Чёрный список / FR-042 | not_started | Причины/evidence/scope/сроки, ручное решение и пересмотр; account deletion отдельно от санкции и законного хранения конкретных материалов спора |
| In-app support / FR-043 | not_started | Без email; доступ к поддержке/апелляциям сохраняется при ограничении/без оплаты |
| Обязательный ID исполнителя / FR-009 | not_started | Удостоверение/паспорт по стране + ручная/провайдерская проверка перед допуском; upload не означает verified identity |
| Закрытое document vault (v1.1) | not_started | MFA/RBAC, ключи/права, журнал чтения, конечная retention/legal holds; нет публичных документов/PII в логах |
| ID/consent/privacy/export/delete / FR-009–010 | not_started | Только требования, нет обработки реальных данных |
| Pair block/санкции/жалобы/словари / FR-021–022/037 | not_started | Нет matcher, registry, quarantine/hold/case/notification/human workflow |
| Два Топ-100 и реакции / FR-044 | not_started | Eligible orders/service cards, like/dislike/undo/change, no self/duplicate votes; stars только completed reviews, нет автобана за dislikes; algorithm/version/antiabuse не реализованы |
| Paid/admin boost и все цены из админки / FR-045 | not_started | Week/month/year либо бесплатный grant с причиной/сроком, marked placement отдельно от organic score; capacity/ledger/IAP/provider/admin price catalog отсутствуют; пример 200 ₸ не тариф |
| Entitlement, billing, rewards / FR-023–026 | not_started | Нет ledger/grants/SSV/purchases/restore/reconciliation; все demo-платежи unverified |
| Рекламный доход/inline banners/push/promotions / FR-033–036 | not_started | Нет integrations, campaign UI/scheduler или promo grants |
| Launcher-иконка / FR-038 | not_started | Есть стандартные Flutter template assets, но нет admin upload/crop/approval/generate/build workflow |
| Рефералы / FR-039 | not_started | Нет attribution/campaign/benefit/reward ledger/budget reservation |
| Public adaptive web / FR-030 W01–W05 | not_started | apps/web отсутствует; полнофункциональный web-кабинет предложен как P2 |
| CI/CD, security, restore/load/operations / NFR-01–12 | not_started | Нет workflow/runners/deploy; показатели не измерены; локальные unit/widget/health проверки не заменяют приёмку |

Проверенное: npm build API/admin/contracts, npm test (1 API + 5 contracts), Flutter analyze без замечаний и 1 widget test. [Подробные проверки](verification.md). Для docs-only обновления проверяются хеш/читабельность MD, ссылки, whitespace и секреты; повторная сборка не требуется.

Открытые launch gates раздела 41: D01 домен/оператор/support contact; D02/D03 regions и межрегиональная уникальность; D04 платежные каналы/SKU/Россия; D05 rewarded core policy; D06/D07 цены/сроки/модель награды; D08 subscriber banner policy; D09 законный country ID flow (обязательность документа уже зафиксирована, liveness не обязательна); D10 retention; D11 geo provider; D12 возраст/категории; D13 support SLA; D14 сербский алфавит; D15 web scope/license; D17 recovery без SMS/email; D19 referral terms; D20 Top formula/window/capacity/boost policy. Числа и примеры требуют утверждения, не становятся тарифами или обещанными SLA.

ТЗ JOBA v1.1 получено и прочитано; файл сохранён byte-for-byte с SHA256 `e8e99bcdac970ead71d0faef79d237ae625c014906ee96337439be3f019ae5fb`. Его получение не подтверждает business implementation. Native builds/PostgreSQL ещё не проверены. Реальные SDK, платежи/реклама, Actions, Docker/Colima, runners и production не включались.

Название JOBA выбрано; домен/юридическое лицо ещё не утверждены. Чат заказа/отклика FR-016 существовал в прежнем ТЗ и не изменён; support FR-043 — отдельный сценарий. Пользовательского email нет, SMS нет; неподтверждённый номер не даёт reset, PIN не восстанавливает server revoke. Все новые FR-040–045 и обязательный ID остаются pending implementation. [Пояснения admin/trust](admin-trust-pending.md).
