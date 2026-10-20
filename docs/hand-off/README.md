# Передача заказчику

[Подробная инструкция по Google и Яндексу — PDF](JOBA-advertising-owner-guide.ru.pdf) · [HTML](JOBA-advertising-owner-guide.ru.html) · [исходник Markdown](JOBA-advertising-owner-guide.ru.md). Сверено с официальной справкой 19.10.2026.

Инструкция различает монетизацию (AdMob/РСЯ), рекламу на сайте и покупку трафика (Google Ads/Директ), содержит создание блоков, список передаваемых идентификаторов и шаги серверной проверки награды. Создание кабинетов само по себе не подключает SDK.

Тестовая Android-сборка собирается скриптом `bash scripts/build-testing-apk.sh`, с release-оптимизацией и Android test/debug-подписью. Она не предназначена для публикации в магазине. Конечные файлы и build manifest помещаются в игнорируемый `release/testing/<commit>/`; приватные ключи не публикуются.

Обновление сервера запускается только по отдельной deploy-ветке. Рабочий HTTPS-адрес: https://joba.com.kz/ . Наличие ответа /health не доказывает, что новый commit уже развёрнут. Результат текущего обновления: https://github.com/milaniumkz/services-marketplace/actions/runs/39400714400 .

20.10.2026: сервер обновлён до `fbf457d`, HTTPS joba.com.kz и браузерные переходы проверены. Реальный вход владельца и сохранение базовых цен Стандарта/Премиума через админку проверены. Внешние платёжные/рекламные/push-провайдеры ещё не подключены.


## Готовые файлы для тестирования

- [APK: Android 7.0+, ARM64, debug](https://raw.githubusercontent.com/milaniumkz/services-marketplace/refs/heads/testing/android-fbf457d/JOBA-testing-arm64-debug.apk)
- [PDF-инструкция, 10 страниц](https://raw.githubusercontent.com/milaniumkz/services-marketplace/refs/heads/testing/android-375e587/JOBA-advertising-owner-guide.ru.pdf)
- [Установка, SHA-256 и build manifest](https://github.com/milaniumkz/services-marketplace/tree/testing/android-fbf457d)
- [Страница тестовой версии](https://github.com/milaniumkz/services-marketplace/releases/tag/testing-2026-10-19-375e587)

APK: 82 182 180 байт (около 79 МиБ), SHA-256 `7c6ef972f2d16294e385c4137fd1286fbe9814bd80b440260dfe14ca2528bdb8`. Источник мобильного приложения — `fbf457d`. Проверены подпись, zip alignment 16 KiB, package `kz.joba.services_marketplace`, единственная ABI arm64-v8a, Android API 24+, INTERNET и HTTPS URL внутри kernel blob. Публичное скачивание вернуло 200, SHA-256 повторно совпал. APK не запускалась на физическом устройстве.

Успешно собрана универсальная debug-APK; для передачи из неё удалены неиспользуемые ABI, после чего файл выровнен и заново подписан тем же Android test-ключом. Подготовка оптимизированной release-APK остановлена на длительной стадии R8; она не объявляется собранной. Выданная debug-APK предназначена для функционального теста, не измерения производительности.

Прямая загрузка Release assets из этой интеграции вернула 401 на uploads.github.com; APK опубликована отдельной Git-веткой testing/android-375e587, чтобы не включать бинарник в основную ветку исходников. Страница Release содержит рабочие прямые ссылки. Ни пароль сервера, ни приватные ключи в Git не помещались.

Backend обновлён: Кыргызстан активен. В PostgreSQL загружено 5915 населённых пунктов четырёх стран и по 933 категории на страну; выдача реального API и дерево админки проверены. В новом APK список городов строит только видимые строки.

## Инструкция администратору

`JOBA-admin-manual.template.ru.md` — исходник подробной инструкции с 37 разделами. Логин и пароль в публичном исходнике заменены плейсхолдерами. Персональная PDF/Word-версия с реальными данными входа передаётся владельцу отдельными файлами и не публикуется в GitHub. Основной адрес панели: https://joba.com.kz/admin/ .
