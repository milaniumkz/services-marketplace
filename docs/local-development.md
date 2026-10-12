# Локальный запуск

Node.js 22+ и npm. В корне: `npm ci`, `npm run build`, `npm test`. API: `npm run dev:api`, затем `curl http://127.0.0.1:3000/health`; админка: `npm run dev:admin`, адрес выводит Vite. Для собственного окружения скопируйте `.env.example` в `.env`, замените placeholders. API сам .env не читает: используйте `node --env-file=.env services/api/dist/main.js` после сборки. База не нужна для health.

При наличии Flutter SDK в `apps/mobile`: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`. Native iOS/Android runners уже в репозитории. Проверено Flutter 3.41.1 / Dart 3.11.0; если SDK отсутствует в PATH, вызывайте его через абсолютный путь. iOS требует Xcode, Android — Android SDK. Перед подписанием iOS выберите собственную development team локально; signing identity в проекте не сохранена. `com.example.services_marketplace` — временный application identifier до выбора бренда. Нативные сборки на этом этапе не запускались.

Шаблон `infra/compose.yaml` не запущен; Docker/Colima и новые SDK требуют отдельного согласования. Никаких CI workflows или self-hosted runners нет.
