# Передача заказчику

[Подробная инструкция по Google и Яндексу — PDF](JOBA-advertising-owner-guide.ru.pdf) · [HTML](JOBA-advertising-owner-guide.ru.html) · [исходник Markdown](JOBA-advertising-owner-guide.ru.md). Сверено с официальной справкой 19.10.2026.

Инструкция различает монетизацию (AdMob/РСЯ), рекламу на сайте и покупку трафика (Google Ads/Директ), содержит создание блоков, список передаваемых идентификаторов и шаги серверной проверки награды. Создание кабинетов само по себе не подключает SDK.

Тестовая Android-сборка собирается скриптом `bash scripts/build-testing-apk.sh`, с release-оптимизацией и Android test/debug-подписью. Она не предназначена для публикации в магазине. Конечные файлы и build manifest помещаются в игнорируемый `release/testing/<commit>/`; приватные ключи не публикуются.

Обновление сервера запускается только по отдельной deploy-ветке. Рабочий HTTPS-адрес: https://188-241-217-228.sslip.io/ . Наличие ответа /health не доказывает, что новый commit уже развёрнут. Результат текущего обновления: https://github.com/milaniumkz/services-marketplace/actions/runs/39263762618 .

19.10.2026: сборка и проверки Actions завершились успешно. Развёртывание было остановлено до SSH-входа, потому что Actions не получил SSH credential. Попытки чтения public key Actions Secrets через REST и GitHub CLI вернули HTTP 403 `Resource not accessible by integration`; самостоятельно добавить repository secret из этой интеграции нельзя. Для следующего запуска владелец сохраняет `JOBA_SSH_PASSWORD` или `JOBA_SSH_PRIVATE_KEY` в Settings → Secrets and variables → Actions. Значение не передаётся в чат и не коммитится. Пока успешное обновление сервера не подтверждено.


## Готовые файлы для тестирования

- [APK: Android 7.0+, ARM64, debug](https://raw.githubusercontent.com/milaniumkz/services-marketplace/refs/heads/testing/android-375e587/JOBA-testing-arm64-debug.apk)
- [PDF-инструкция, 10 страниц](https://raw.githubusercontent.com/milaniumkz/services-marketplace/refs/heads/testing/android-375e587/JOBA-advertising-owner-guide.ru.pdf)
- [Установка, SHA-256 и build manifest](https://github.com/milaniumkz/services-marketplace/tree/testing/android-375e587)
- [Страница тестовой версии](https://github.com/milaniumkz/services-marketplace/releases/tag/testing-2026-10-19-375e587)

APK: 82 186 276 байт (около 79 МиБ), SHA-256 `38d0505e5254374f41537baab7a0b79b20e6341262a048e10f2f19cec15d6c91`. Источник мобильного приложения — `375e587`. Проверены подпись, zip alignment 16 KiB, package `kz.joba.services_marketplace`, единственная ABI arm64-v8a, Android API 24+, INTERNET и HTTPS URL внутри kernel blob. Публичное скачивание вернуло 200, SHA-256 повторно совпал. APK не запускалась на физическом устройстве.

Успешно собрана универсальная debug-APK; для передачи из неё удалены неиспользуемые ABI, после чего файл выровнен и заново подписан тем же Android test-ключом. Подготовка оптимизированной release-APK остановлена на длительной стадии R8; она не объявляется собранной. Выданная debug-APK предназначена для функционального теста, не измерения производительности.

Прямая загрузка Release assets из этой интеграции вернула 401 на uploads.github.com; APK опубликована отдельной Git-веткой testing/android-375e587, чтобы не включать бинарник в основную ветку исходников. Страница Release содержит рабочие прямые ссылки. Ни пароль сервера, ни приватные ключи в Git не помещались.

До обновления backend новые сценарии и Кыргызстан могут быть недоступны: live-конфиг ещё содержит RS. Полноценное сквозное тестирование последней версии требует сначала завершить deploy с сохранённым владельцем SSH credential.

## Инструкция администратору

`JOBA-admin-manual.template.ru.md` — исходник подробной инструкции с 37 разделами. Логин и пароль в публичном исходнике заменены плейсхолдерами. Персональная PDF/Word-версия с реальными данными входа передаётся владельцу отдельными файлами и не публикуется в GitHub. Основной адрес панели: https://joba.com.kz/admin/ .
