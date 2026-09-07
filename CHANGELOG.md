# Changelog OrexRay

Здесь собрана история пользовательских изменений OrexRay по старым milestone/hotfix-документам, GitHub Releases и истории коммитов. Внутренние коммиты вида `fix`/`work` отдельно не перечисляются, если они не образуют самостоятельную пользовательскую версию.

## [0.7.0+11] — в разработке

Потребительская ветка после публикации `0.6.7+10`.

### Добавлено

- HTTP(S)-подписки: обычные share-links, Base64-списки, JSON Xray и массивы JSON.
- Сохранение исходного URL подписки, ручное обновление и экспорт исходной ссылки/серверов.
- Стандартные metadata подписки: `subscription-userinfo`, `profile-title`, `profile-update-interval`, `support-url`, `profile-web-page-url`, `announce`.
- Лёгкое обновление metadata через `HEAD` отдельно от полного обновления серверов.
- Отдельные интервалы автообновления серверов и metadata без постоянного background polling.
- Legacy informational nodes (`localhost`/loopback) распознаются как сведения подписки, а не как реальные серверы.
- Подписки и пользовательские папки как раскрываемые группы; группированный quick picker.
- Балансировщики могут состоять из одного сервера или динамически включать целую папку/подписку.
- Массовое выделение, групповые операции и перестановка профилей/групп.
- Страновые флаги для маршрутов и отдельный Cloudflare/WARP badge.
- Унифицированные debug/release build tools и ADB-сбор диагностики.

### Изменено

- Профиль можно переключать прямо из списка при активном VPN; UI выбирает новый маршрут сразу, а reconnect выполняется безопасной последовательностью stop/start.
- `timeout` и прочие ошибки route-check сведены к понятным пользовательским состояниям `Нет ответа` / `Ошибка соединения`, при этом техническая причина сохраняется для диагностики.
- Runtime-интервалы stats/ping применяются без переподключения там, где платформа это поддерживает безопасно.
- Подписочные metadata и служебные ссылки больше не угадываются по брендам клиентов; OrexRay работает с общими форматами подписок.
- Интерфейс профилей, drag-and-drop, мобильные статусы, action-панели и desktop navigation последовательно адаптированы под узкие и широкие окна.

### Исправлено

- Гонки Android `STOP → START` при быстрой смене профиля и зависшие промежуточные состояния подключения.
- Отмена `connecting` повторным нажатием на кнопку без отдельной кнопки-крестика.
- Lifecycle/dispose races в `TunnelController` и фоновых latency probes.
- Ряд widget-test regressions после перехода на группировку и новый Flutter reorder API.

## [0.6.7+10] — 2026-09-05

- Android VPN вынесен в отдельный `:vpn` process и продолжает работу независимо от Flutter UI.
- Stats/ping выполняются только при наличии реального consumer; интервалы UI-статистики, notification-статистики и ping разделены.
- Xray JSON импортируется объектом или массивом из файла, буфера обмена и HTTP(S) URL.
- Экспорт умеет сохранять `.json`, копировать один объект или массив выбранных профилей.
- Добавлен long-press selection с массовым ping/export/delete и reorder профилей.
- Health-state больше не считается успешным до подтверждённого route ping; timeout/unavailable показываются как проблема маршрута.
- Обновлены release-инструкции и PowerShell build tools.

## [0.6.6+9] — 2026-08-15

- Импорт расширен с VLESS до VMess, Trojan, Shadowsocks, SOCKS5 и HTTP(S).
- Усилена валидация профилей и идентичности соединений для разных протоколов.
- Добавлена event-driven проверка активного маршрута при открытии приложения без периодического фонового probe.
- Диагностический sanitizer начал скрывать секреты во всех поддерживаемых proxy-link схемах.
- Android перестал считать скрытые/запрещённые уведомления активным consumer статистики.

## [0.6.5+8] — 2026-07-07

- Исправлен self-triggered recovery-loop Windows TUN.
- Сетевые события собственного TUN отфильтрованы; reconnect выполняется только при реальном изменении физического outbound.
- Перед состоянием `Подключено` Windows проверяет реальные публичные IPv4/IPv6 маршруты.
- Диагностика расширена фактическим TUN-маршрутом и объединённым журналом OrexRay/Xray.
- Уровень логов перенесён в экран диагностики и снабжён предупреждением для подробных сетевых логов.

## [0.6.5+7] — 2026-07-07

- Добавлены автозапуск и auto-connect, Windows recovery после resume/смены сети и ограниченный Xray watchdog.
- Android получил восстановление VPN после reboot (опционально) и core-watchdog.
- Добавлен экран диагностики с безопасным копируемым отчётом и редактированием секретов.
- Появилась проверка страны выхода/WARP после подключения.
- DNS по умолчанию переведён на явный путь через VPN.

## [0.6.4+5] — 2026-07-07

- Снижена лишняя частота обновления Android notification и Quick Settings tile.
- Android TUN получил IPv6 address/default route и более строгую проверку per-app `only` режима.
- GeoData updater получил timeouts, лимиты размера, throttled progress, checksum-before-replace и пропуск уже актуальных файлов.
- Усилена миграция профилей в защищённое Android storage.

## [0.6.4+4] — 2026-07-06

- Windows traffic statistics переведены с `Get-NetAdapterStatistics` на Xray Stats API.
- Stats API поднимается только на loopback и используется во всех Windows-режимах подключения.
- Добавлен monochrome branding asset.

## [0.6.3] — 2026-07-06

- Добавлена Android Quick Settings плитка `OrexRay VPN` для запуска последнего VPN и отключения без открытия Flutter UI.
- Состояние повторного запуска хранится в Keystore-backed storage.
- Release signing Android сделан обязательным для release-сборки.
- Добавлен Windows installer на Inno Setup и унифицирована release-документация.

### 0.6.3+2 / 0.6.3+3

Небольшие исправления и стабилизация ветки `0.6.3` перед переходом к Windows stats/recovery работе.

## [0.6.2] — 2026-07-06

- Корень репозитория очищен от временных milestone/hotfix/update заметок; актуальная документация сведена в README/docs.
- Release-артефакты вынесены в `dist/`, secrets/keystores исключены из репозитория.
- README переписан как актуальная продуктовая и архитектурная документация.

## [0.6.1+9] — 2026-07-06

- Исправлен custom GeoData import на актуальном Dart/Flutter.
- Исправлена race в тестах `TunnelController` после awaited start/stop.

## [0.6.0] — 2026-07-06

- Android VPN стал долгоживущим foreground service, независимым от Flutter Activity.
- Добавлены live traffic counters, скорость, duration и настройка частоты статистики.
- Добавлены автоматические/ручные latency probes и сохранение ping в профиле.
- Появился GeoData экран с обновлением `geoip.dat`/`geosite.dat` и SHA-256 проверкой.
- Добавлен Android per-app VPN routing: все / исключить выбранные / только выбранные.
- Появились балансировщики Random, Round Robin и Least Ping.
- Добавлено полноценное редактирование VLESS-профиля.

## [0.5.1] — 2026-07-06

- Исправлен конфликт имени `AboutScreen.build`; build number переименован в `buildNumber`.

## [0.5.0] — 2026-07-06

- Исправлен Android crash из-за неверного XUDP base key; ключ стал стабильным URL-safe Base64 значением нужной длины.
- Добавлен полноценный Orex startup/bootstrap screen.
- Desktop navigation разбита на отдельные Connection, Network, Interface и About.
- Добавлены persistent ports, LAN binding, MTU, DNS presets/custom DNS, private-network bypass, sniffing и Xray log level.

## [0.4.1] — 2026-07-06

- Исправлена совместимость с актуальным Flutter `RadioGroup`; переключатели корректно блокируются во время активного соединения.

## [0.4.0] — 2026-07-06

- Windows получил три режима: System Proxy, VPN/TUN и Local Proxy.
- Системный proxy Windows сохраняется и восстанавливается после disconnect/abnormal exit.
- Android получил VPN и Local Proxy как отдельные режимы.
- Foreground notification запускается до тяжёлой инициализации Xray.
- Усилена устойчивость загрузки/валидации сохранённых профилей.
- Утверждённый OrexRay branding применён в UI, Android launcher и Windows application icon.

## [0.3.1] — 2026-07-06

- Windows manifest переведён на `asInvoker`, поэтому debug build можно запускать из обычного терминала; отдельный helper оставлен для elevated TUN теста.

## [0.3.0] — 2026-07-06

- Добавлен Android `VpnService`, системный permission flow и foreground service.
- Создаётся Android TUN с передачей file descriptor в Xray Core.
- Подключён pinned `AndroidLibXrayLite` AAR с SHA-256 проверкой.
- Добавлены MethodChannel/EventChannel и live status/traffic/duration.
- Исправлена Windows manifest/linker интеграция (`LNK1327`, `RT_MANIFEST`, `/MANIFEST:NO`).

## Ранние milestones — до 0.3.0

### Milestone 02 — реальное подключение Windows

- Импорт `vless://`, сохранение и выбор профилей.
- Генерация Xray `config.json`, Windows TUN backend и загрузка официального Xray Core с SHA-256 проверкой.
- Проверка конфига перед запуском, реальное connect/disconnect и первые unit/widget tests.

### Milestone 01 — UI foundation

- Перенесена Orex design-system из Orex Messenger.
- Созданы адаптивный Android/Windows shell, главный экран, профили, настройки и темы.
- Заложены `TunnelEngine`/`TunnelController` и платформенные Android/Windows engine abstractions.

---

Исторические разделы выше восстановлены из файлов `MILESTONE_*`, `HOTFIX_*`, `UPDATE_*`, GitHub Releases и versioned commits репозитория. Для старых промежуточных build-коммитов без самостоятельных release notes перечислены только подтверждённые пользовательские изменения.
