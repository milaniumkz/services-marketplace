# STATUS — 2026-10-12

Источник: [полное ТЗ v1.0](spec/services-marketplace-spec-v1.ru.md). Это статус scaffold в feature/mobile-native-scaffold/draft PR #1, не приемка P1. Код проверен на `d5a5d18885797ecfd9aea333189ccc896093da7e`; после него до импорта ТЗ были только docs commits. Последующая branding-only правка меняет display names на JOBA; бизнес-функции не расширяет. Исходный импорт MD: `92c5d9568d208f6e7459be741ae4e2544f9aad9d`. `main` остаётся initial scaffold `5e2f4de23127e1dec9366817e2174bbdd9667bfc` до отдельного разрешённого merge.

implemented = готова указанная узкая техническая часть; partial = только модель/template/demo, бизнес-приёмка не пройдена; not_started = реализации нет. Ни один полный бизнес-FR сейчас не принимается как implemented.

| Область / FR | Статус | Фактическая граница |
|---|---|---|
| Выбранный бренд JOBA | implemented | Display name Flutter/iOS/Android и admin demo; repo/package/application IDs и signing не менялись |
| Полный исходный Markdown ТЗ v1 | implemented | 229868 байт; SHA256 точно совпал; текст неизменён. PDF/DOCX переданы отдельно, импорт не требуется |
| Monorepo, env placeholders, lockfiles и инструкции | implemented | npm workspace API/admin/contracts и Flutter sources; полный local stack не готов |
| API health / сборки | implemented | Только GET /health, process liveness; /orders возвращает 404; нет DB readiness |
| Mobile iOS/Android / FR-030 | partial | Native templates и demo-screen; analyze + 1 widget test прошли; native builds/signing не проверены |
| Admin / FR-027–028, FR-030 | partial | Статичный TypeScript/Vite demo; нет Next.js, employee auth/MFA, RBAC или audit |
| Contracts / FR-029 | partial | Health/country и demo auth/monetization; нет полного OpenAPI 3.1, generated clients и compatibility CI |
| Локали/страны / FR-004 | partial | Коды стран в типах/документации; нет i18n, legal versioning, справочников/вычитки |
| Auth / FR-006–008 | partial | Policy/state/display guard, тесты expiry/revoke; нет phone-password endpoints, Argon2id, region-first, session persistence, secure storage, PIN/biometric implementation |
| Монетизация / FR-031–032 | partial | Неизменяемые demo flags и shape validator, scope country/role, версия и reward examples; нет platform/placement/TTL, persistence, admin publish/rollback или entitlement engine |
| PostgreSQL/PostGIS foundation | partial | Compose template + SQL extension; не запускались, нет business tables/runner/history/integration tests |
| Заказ/исполнитель/профили/поиск/отклик/invite/чат/завершение/спор/репутация / FR-001–002, FR-011–020 | not_started | Нет вертикального бизнес-сценария, данных или endpoints |
| Server roles/object access и региональная изоляция / FR-003/005 | not_started | Нет enforcement или регионального data plane |
| ID/consent/privacy/export/delete / FR-009–010 | not_started | Только требования, нет обработки реальных данных |
| Pair block/санкции/жалобы/словари / FR-021–022/037 | not_started | Нет matcher, registry, quarantine/hold/case/notification/human workflow |
| Entitlement, billing, rewards / FR-023–026 | not_started | Нет ledger/grants/SSV/purchases/restore/reconciliation; все demo-платежи unverified |
| Рекламный доход/inline banners/push/promotions / FR-033–036 | not_started | Нет integrations, campaign UI/scheduler или promo grants |
| Launcher-иконка / FR-038 | not_started | Есть стандартные Flutter template assets, но нет admin upload/crop/approval/generate/build workflow |
| Рефералы / FR-039 | not_started | Нет attribution/campaign/benefit/reward ledger/budget reservation |
| Public adaptive web / FR-030 W01–W05 | not_started | apps/web отсутствует; полнофункциональный web-кабинет предложен как P2 |
| CI/CD, security, restore/load/operations / NFR-01–12 | not_started | Нет workflow/runners/deploy; показатели не измерены; локальные unit/widget/health проверки не заменяют приёмку |

Проверенное: npm build API/admin/contracts, npm test (1 API + 5 contracts), Flutter analyze без замечаний и 1 widget test. [Подробные проверки](verification.md). Для docs-only обновления проверяются хеш/читабельность MD, ссылки, whitespace и секреты; повторная сборка не требуется.

Открытые gates: решения раздела 41, особенно D02/D03 regions, D04 payment channels, D05 rewarded policy, D07 reward model, D10 retention, D17 recovery, D19 referral terms. Получение ТЗ не означает согласование всех предложенных чисел/стека/интервалов. Native builds и PostgreSQL пока не проверены. Реальные SDK, платежи/реклама, Actions, Docker/Colima, runners и production не включались.

Бренд выбран: **JOBA**. Домен/юридическое лицо не утверждены. Исходный ТЗ v1 в docs/spec сохранён неизменённым; автор готовит v1.0.1 branding-only с точными новыми байтами для отдельной синхронизации.
