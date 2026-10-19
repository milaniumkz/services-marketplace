# Передача заказчику

[Подробная инструкция по Google и Яндексу — PDF](JOBA-advertising-owner-guide.ru.pdf) · [HTML](JOBA-advertising-owner-guide.ru.html) · [исходник Markdown](JOBA-advertising-owner-guide.ru.md). Сверено с официальной справкой 19.10.2026.

Инструкция различает монетизацию (AdMob/РСЯ), рекламу на сайте и покупку трафика (Google Ads/Директ), содержит создание блоков, список передаваемых идентификаторов и шаги серверной проверки награды. Создание кабинетов само по себе не подключает SDK.

Тестовая Android-сборка собирается скриптом `bash scripts/build-testing-apk.sh`, с release-оптимизацией и Android test/debug-подписью. Она не предназначена для публикации в магазине. Конечные файлы и build manifest помещаются в игнорируемый `release/testing/<commit>/`; приватные ключи не публикуются.

Обновление сервера запускается только по отдельной deploy-ветке. Рабочий HTTPS-адрес: https://188-241-217-228.sslip.io/ . Наличие ответа /health не доказывает, что новый commit уже развёрнут. Результат текущего обновления: https://github.com/milaniumkz/services-marketplace/actions/runs/39263762618 .

19.10.2026: сборка и проверки Actions завершились успешно. Развёртывание было остановлено до SSH-входа, потому что Actions не получил SSH credential. Попытки чтения public key Actions Secrets через REST и GitHub CLI вернули HTTP 403 `Resource not accessible by integration`; самостоятельно добавить repository secret из этой интеграции нельзя. Для следующего запуска владелец сохраняет `JOBA_SSH_PASSWORD` или `JOBA_SSH_PRIVATE_KEY` в Settings → Secrets and variables → Actions. Значение не передаётся в чат и не коммитится. Пока успешное обновление сервера не подтверждено.
