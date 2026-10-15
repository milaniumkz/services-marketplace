# Initial scaffold verification — 2026-10-12

- Node v24.10.0, npm 11.6.0.
- `npm install --ignore-scripts --no-audit --no-fund`: succeeded; lockfile committed.
- `npm run build`: NestJS TypeScript compilation and admin TypeScript/Vite build succeeded.
- `npm test`: one HTTP integration test passed: health 200 with demo response; unimplemented `/orders` returns 404. Local port requires permission outside filesystem sandbox; server closes after test.
- `git diff --check`: passed; simple secret-pattern scan found no matches in source. This is not a security audit.
- Flutter not found in PATH; Flutter analysis, widget test, iOS/Android runner generation and native builds not performed.
- PostgreSQL/PostGIS migration and compose template not executed. No Docker/Colima, CI runners, production deployment or real integrations started.

## Оставшиеся 28 мобильных состояний, 2026-10-15

Команды: `npm run test --workspace @marketplace/api`, `npm run mobile:test`, `npm run mobile:analyze`, `npm run mobile:verify-api`, `npm run mobile:build:android`, `npm run admin:verify-browser`. Дополнительный целевой файл: `services/api/test/remaining-mobile-states.test.cjs`; мобильный: `apps/mobile/test/remaining_states_test.dart`.

Визуальный прогон: `JOBA_ALL_SCREENS_DIR=/tmp/joba-all115 bash scripts/flutter-mobile.sh test test/visual_inventory_test.dart --reporter expanded`. Сравнение: `python3 scripts/compare-design.py --surface mobile --captures /tmp/joba-all115 --output /tmp/joba-comparison`. Это проверка создания всех 115 снимков без Flutter exceptions/overflow, а не автоматическая визуальная приёмка. 28 ранее отсутствовавших состояний входят в этот прогон. Обновлённый [реестр](design/review/visual-audit.json) сохраняет `pending`; неподключённые сценарии админки не маскируются успешными кадрами.

Итог последнего прогона этого этапа: **58/58 backend**, **54/54 Flutter** (2 опциональных сценария запускаются отдельно), **0 замечаний Flutter analyzer**, **1/1 настоящий HTTP из Flutter**, **115/115 мобильных снимков без Flutter exceptions/overflow**. Debug Android APK собран. Браузерный real-HTTP прогон админки прошёл. Эти числа описывают автоматические проверки; они не заменяют визуальную приёмку, проверку iOS, физических устройств или полную функциональную приёмку всех 2449 контролов макета.

## Продолжение проекта: админские состояния, зона, продвижение, retention

Общий backend-прогон: **62/62**. После исправления дедупликации уведомления об истёкшей проверке повторно прошли оба retention-теста, включая реальные зашифрованные байты, сбой физического удаления и повтор. Общий Flutter-прогон: **58/58**, 2 опциональных сценария отдельно; analyzer — 0 замечаний. Отдельно выполнены native real HTTP, debug Android APK и сборка npm workspaces. Браузерный real-HTTP сценарий проверяет dry-run без публикации, отсутствие выдуманного дохода, языки и массовую паузу/возобновление через отдельные preview и confirmation.

Визуальные прогоны создали 115 мобильных и 72 браузерных кадра. В новом реестре нет сообщения о неподключённом маршруте; все 187 кадров остаются `pending`. Часть административных кадров показывает выбор записи/версию, а не полную исходную форму. Эти снимки нельзя трактовать как 1:1 или приёмку всех контролов. Полный остаток — [готовность проекта](project-readiness.md).
