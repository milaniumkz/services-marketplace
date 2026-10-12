# Локальный запуск

Node.js 22+ и npm. В корне: `npm ci`, `npm run build`, `npm test`. API: `npm run dev:api`, затем `curl http://127.0.0.1:3000/health`; админка: `npm run dev:admin`, адрес выводит Vite. Для собственного окружения скопируйте `.env.example` в `.env`, замените placeholders. API сам .env не читает: используйте `node --env-file=.env services/api/dist/main.js` после сборки. База не нужна для health.

Flutter SDK не устанавливается этим проектом. При наличии Flutter в `apps/mobile`: `flutter create --platforms=ios,android --project-name services_marketplace .`, проверьте diff сгенерированных файлов, затем `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`. iOS требует Xcode, Android — Android SDK. Нативные runner-проекты пока не сгенерированы и мобильная сборка не подтверждена.

Шаблон `infra/compose.yaml` не запущен; Docker/Colima и новые SDK требуют отдельного согласования. Никаких CI workflows или self-hosted runners нет.
