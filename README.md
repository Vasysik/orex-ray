# OrexRay

Тёплый Xray-клиент на **Flutter** для **Android** и **Windows**. OrexRay
объединяет системный VPN, системный прокси, локальные SOCKS5/HTTP-прокси,
профили VLESS/VMess/Trojan/Shadowsocks/SOCKS/HTTP, балансировщики и per-app маршрутизацию в одном интерфейсе в
визуальном стиле Orex.

Текущая версия задаётся только в `pubspec.yaml` в поле `version`.

Текущая сборка находится в стадии private beta / dogfood, но фокус уже не на добавлении базовых режимов, а на надёжности long-running VPN. Android VPN уже
пропускает реальный TCP/UDP-трафик через Xray, работает в фоне и может
одновременно поднимать локальные SOCKS5/HTTP-прокси. Windows-часть поддерживает
системный прокси, локальный прокси и отдельный TUN-режим. Это уже рабочий
клиент, но перед широкой раздачей ещё нужны длительные тесты на разных
прошивках, сетях и профилях.

## 1. Продуктовый фокус

OrexRay не строится как «одна большая кнопка TUN». Режим подключения является
отдельной частью продукта, потому что разным приложениям и платформам нужны
разные способы маршрутизации.

Главные принципы:

- единая Flutter-кодовая база для Android и Windows;
- нативный Android `VpnService` для полного системного VPN;
- системный прокси как основной мягкий режим Windows;
- локальные SOCKS5 и HTTP-прокси для ручной настройки приложений;
- VLESS/REALITY и другие параметры Xray-профиля без искусственного упрощения;
- честное разделение UI, профилей, Xray-конфига и платформенных движков;
- Orex UX: тёплые стеклянные панели, медные акценты и белочка в защитной
  скорлупе на фоне мировой сети.

## 2. Режимы подключения

### Android

Поддерживаются два пользовательских режима:

- **VPN** — весь выбранный трафик проходит через Android `VpnService` и TUN;
- **Локальный прокси** — Xray поднимает SOCKS5/HTTP без системного VPN.

В VPN-режиме OrexRay по умолчанию также поднимает локальные прокси. Это нужно,
например, когда приложение исключено из TUN, но настроено на локальный SOCKS5
вручную.

Плитка **OrexRay VPN** в быстрых настройках Android хранит состояние вне
Flutter-процесса. Поэтому после закрытия интерфейса она умеет и остановить VPN,
и снова запустить последнее успешное VPN-подключение без открытия приложения.

```text
Android apps
    │
    ├── VpnService / TUN ──────────┐
    │                              │
    ├── SOCKS5 127.0.0.1:20808 ───┤
    └── HTTP   127.0.0.1:20809 ───┤
                                   ▼
                               Xray Core
                                   │
                              VLESS / TLS /
                                 REALITY
```

### Windows

Поддерживаются три режима:

- **Системный прокси** — OrexRay поднимает локальный HTTP proxy и подключает к
  нему настройки Windows;
- **VPN / TUN** — режим для полного трафика;
- **Локальный прокси** — SOCKS5/HTTP без изменения системных настроек.

Системный прокси остаётся самым лёгким режимом Windows: он не требует TUN для
приложений, которые умеют использовать системные proxy-настройки.

На Windows OrexRay запускается в одном экземпляре. Крестик по умолчанию скрывает
окно в системный трей; это поведение отключается на экране **Фон**. Там же можно
включить запуск вместе с Windows и отдельное автоматическое подключение выбранного
профиля. Автозапуск стартует скрыто в трее.

Команда **Выход** в трее сначала останавливает туннель и восстанавливает системный
прокси, а уже затем завершает приложение. Запущенный Xray привязывается к процессу
OrexRay на уровне Windows, поэтому не должен оставаться сиротой после аварийного
завершения клиента.

Windows TUN перед каждым стартом определяет активный физический интерфейс и явно
привязывает к нему outbound Xray. OrexRay игнорирует уведомления от собственного
TUN и не пересобирает соединение, если Windows сообщила об изменении сети, но
физический outbound фактически остался прежним. После реальной смены
Wi‑Fi/Ethernet/точки доступа TUN пересобирается с новым интерфейсом.

Windows TUN использует возможности Xray Core 26.4.13 для настройки gateway,
DNS, системной таблицы маршрутов и явной привязки outbound к физическому
интерфейсу. Диагностика best-route Windows остаётся advisory-сигналом: она не
останавливает уже работающий TUN только потому, что `GetBestInterface` вернул имя
физического адаптера. Реальный acceptance test для TUN — сменившийся внешний IP и
проходящий IPv4/IPv6-трафик.


## Надёжность long-running подключения

В текущей ветке доработан recovery-контур для сценария «забыл, что VPN существует»:

- Windows получает события resume и изменения IP-интерфейсов от ОС;
- события собственного интерфейса `OrexRay` отфильтровываются нативно;
- шумные уведомления, не изменившие физический outbound, не перезапускают Xray;
- активный TUN после реальной смены физической сети пересобирается с новой
  outbound-привязкой;
- если сеть меняется повторно прямо во время recovery, событие не теряется и
  переоценивается после короткого cooldown;
- диагностируется лучший публичный IPv4/IPv6-маршрут, но advisory-проверка не убивает рабочий TUN;
- Xray watchdog классифицирует неожиданный exit и не перезапускает фатальные ошибки
  конфигурации, занятые порты и Access Denied;
- безопасные crash/transient exits перезапускаются с backoff;
- лимит watchdog — 3 автоматических рестарта за 60 секунд;
- перед каждым Windows-стартом удаляются только orphan-процессы с точным путём к
  управляемому `xray.exe`;
- system proxy восстанавливается после stop/crash и не затирает чужое изменение;
- Android foreground service остаётся `START_STICKY`, а отдельный core-watchdog
  поднимает Xray при неожиданной остановке;
- опциональное auto-connect на Android умеет восстановить последний успешный VPN
  после reboot, если разрешение VPN уже было выдано.

Для максимально жёсткого always-on сценария Android всё равно лучше дополнительно
включать системную функцию **Always-on VPN**: её жизненным циклом управляет сама ОС.

## Диагностика

Экран **Диагностика** показывает:

- версии OrexRay и Xray;
- режим, профиль и runtime-state;
- PID и локальные порты;
- состояние системного proxy Windows;
- физический outbound-интерфейс и advisory-снимок лучшего IPv4/IPv6-маршрута Windows TUN;
- watchdog/restart budget, последнюю ошибку и exit code;
- до 100 строк объединённого журнала `[OrexRay]` + `[Xray]`.

Настройка уровня логов Xray находится на этом же экране. При `debug` шумные строки
Xray вытесняются раньше служебных записей OrexRay, поэтому решения recovery и
watchdog остаются видимыми в отчёте.

Кнопка **Скопировать отчёт** повторно редактирует UUID, `vless://` ссылки и типичные
secret-поля. Отчёт предназначен для bug report без публикации конфигурации доступа.

На Windows обслуживание движка вынесено в **О приложении → Движок**. Кнопка
**Переустановить Xray Core** работает только при отключённом туннеле,
восстанавливает закреплённую версию Core и проверяет архив по встроенному SHA-256.
Для установки в Program Files нужны права администратора; portable/debug-сборки
ремонтируются в своём каталоге без переустановки всего OrexRay.

## Флаги выхода и WARP

После успешного подключения OrexRay может проверить выход через локальный HTTP
proxy самого Xray. Из ответа Cloudflare trace сохраняются только код страны,
признак WARP и время проверки — выходной IP не сохраняется. На карточке профиля показывается флаг страны выхода, а WARP отмечается
компактным фирменным значком Cloudflare.

## 3. Профили и импорт Xray

Профили можно:

- импортировать из proxy-ссылок и Xray JSON;
- импортировать JSON как объект `{...}` или массив `[...]`;
- читать JSON из локального `.json` и HTTP(S)-ссылки;
- экспортировать один профиль как JSON-объект или выбранные профили массивом;
- копировать JSON прямо в буфер обмена без промежуточного файла;
- создать и редактировать вручную;
- выделять долгим нажатием несколько серверов для mass ping/export/delete;
- менять порядок серверов drag-and-drop;
- быстро выбирать маршрут с главной страницы;
- менять активный маршрут и с главной, и прямо из списка профилей; выбор
  отображается сразу, а stop/start выполняется последовательно без блокировки UI.

Редактор поддерживает основные параметры, которые уже используются текущим
Xray config builder:

- адрес, порт и UUID;
- flow;
- security: `none`, `tls`, `reality`;
- transport: RAW/TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade;
- SNI, fingerprint, ALPN;
- REALITY public key/password и short ID;
- path, host и gRPC service name;

Добавление нового профиля **не переключает активный маршрут автоматически**.
При первом профиле он становится выбранным, потому что другого маршрута ещё
нет.

## 4. Быстрая смена маршрута

Название активного маршрута на главной открывает Orex choice sheet — ту же
визуальную модель, что быстрый выбор аудиоустройств в Orex Messenger.

Во время активного соединения смена профиля разрешена. OrexRay выполняет
контролируемое переподключение:

```text
активный профиль A
        ↓
выбор профиля B
        ↓
остановка текущего core
        ↓
сохранение B как активного
        ↓
запуск в том же режиме
        ↓
активный профиль B
```

Режим подключения при этом сохраняется: VPN остаётся VPN, локальный proxy —
локальным proxy.

## 5. Балансировщики

Балансировщик создаётся прямо в OrexRay и используется как обычный маршрут.
Можно выбрать минимум два профиля и одну из стратегий:

- Random;
- Round Robin;
- Least Ping.

Для наблюдения за доступностью настраиваются probe URL и интервал проверки.

Поддерживается fallback:

- без fallback;
- `direct`;
- `block`;
- отдельный VLESS-профиль.

Fallback-профиль не включается в основной selector балансировщика. Он получает
отдельный outbound и используется только как запасной маршрут.

## 6. Ping и статистика

Ping можно обновить:

- для всех профилей на странице профилей;
- для одного профиля;
- нажатием прямо на показатель ping на главной.

Текущая проверка измеряет TCP latency до адреса и порта сервера. Это быстрый
показатель доступности, а не полный VLESS/REALITY handshake.

Во время соединения UI показывает:

- текущую скорость скачивания;
- текущую скорость отдачи;
- ping активного маршрута;
- общий входящий и исходящий трафик;
- длительность соединения.

Интервалы разделены: частота UI-статистики и частота обновления Android
notification настраиваются независимо, а ping имеет свой интервал. На Windows
этот интервал управляет периодической end-to-end проверкой активного маршрута;
на Android её выполняет foreground VPN-service. Если UI закрыт и соответствующий
показатель notification выключен, его periodic task полностью останавливается.

В Android foreground notification отображаются профиль, скорости и задержка в
компактном виде, например:

```text
↓ 4.8 MB/s · ↑ 620 KB/s · 52 мс
```

## 7. Split tunneling Android

OrexRay умеет строить per-app VPN в трёх режимах:

- все приложения;
- все, кроме выбранных;
- только выбранные.

Список приложений поддерживает:

- поиск по названию и package name;
- фильтр системных приложений;
- фильтр только выбранных;
- иконки приложений.

Чтобы не блокировать интерфейс на устройствах с большим количеством пакетов,
метаданные и иконки разделены: список загружается без огромного batch из
bitmap-данных, а иконки запрашиваются лениво для видимых строк.

## 8. Фоновая работа Android

Android разделяет UI и VPN по процессам: Flutter работает в `ru.orex.ray`, а
foreground `VpnService`, Xray, TUN и Quick Settings — в `ru.orex.ray:vpn`.
Поэтому выгрузка тяжёлого UI-процесса при memory pressure не обязана уничтожать
туннель. Package-level force-stop со стороны прошивки всё равно останавливает
оба процесса.

Фоновая часть отвечает за:

- жизненный цикл Xray core;
- TUN file descriptor;
- статистику трафика;
- обновление уведомления;
- кнопку отключения из уведомления;
- восстановление последнего соединения после пересоздания service.

Частота UI-статистики, notification-статистики и ping настраивается отдельно.
В фоне stats-loop и ping-loop существуют только при реально активном consumer:
если показатель выключен либо Android запретил notification channel, лишний
polling прекращается. OrexRay не держит постоянный wake lock только ради
счётчиков.

На Android 7+ доступна системная плитка **OrexRay VPN** для панели быстрых
настроек рядом с Bluetooth и фонариком. Она включает последний VPN, который
успешно запускался из приложения, и отключает активный VPN без открытия Flutter
UI. Конфиг для повторного запуска хранится в том же Keystore-backed encrypted
storage, что и restart state. Если VPN ещё ни разу не запускался или системе
нужно первое разрешение, плитка открывает только необходимый системный flow.

## 9. DNS, маршрутизация и GeoData

Для новой установки DNS по умолчанию задаётся как **DNS через VPN**: `1.1.1.1` и `8.8.8.8` попадают в TUN и идут через Xray. Системный DNS остаётся отдельным осознанным вариантом; также доступны готовые пресеты и пользовательский список серверов.

Маршрутизация поддерживает:

- private networks напрямую;
- protocol sniffing;
- GeoData rules для `direct`, `proxy` и `block`.

GeoData-раздел умеет:

- показывать состояние `geoip.dat` и `geosite.dat`;
- обновлять официальные файлы;
- проверять SHA-256 перед заменой;
- импортировать собственный `geoip.dat` или `geosite.dat`;
- включать автообновление.

Пользовательские `.dat` считаются доверенным вводом пользователя: OrexRay не
пытается «исправлять» их содержимое и передаёт их Xray при следующем запуске
core.

## 10. Безопасность и границы private beta

В Android-подготовке к первой раздаче сделаны базовые защитные меры:

- release-сборка не должна молча подписываться debug-ключом;
- VLESS/REALITY-профили на Android сохраняются через Keystore-backed encrypted
  storage;
- restart state foreground service хранится зашифрованно;
- Android backup для чувствительных app data отключён;
- cleartext traffic для сетевого стека приложения запрещён;
- VPN service не экспортируется;
- release-логи OrexRay сокращены;
- локальные прокси слушают `127.0.0.1` по умолчанию.

Остаточные границы:

- режим LAN proxy открывает порт на `0.0.0.0` и требует осознанного включения;
- пользовательская GeoData доверяется Xray parser;
- сторонний Xray core остаётся частью доверенной вычислительной базы;
- Windows release устанавливается в Program Files; bundled `xray.exe`,
  `wintun.dll` и GeoData перепроверяются по закреплённому архиву перед запуском;
- автозапуск с повышенными правами является opt-in и разрешён только для
  Program Files-установки;
- Windows-профили ещё требуют отдельного прохода по защищённому локальному
  хранению перед более широкой desktop-раздачей.

## 11. Архитектура

```text
lib/
  app/                  bootstrap и корневое приложение
  core/
    apps/               per-app routing state
    geodata/            обновление и импорт GeoData
    profiles/           профили, persistence, ping
    settings/           режимы, DNS, proxy и background settings
    tunnel/             модели и интерфейсы движка
    xray/               генератор Xray JSON
  features/
    home/               подключение, статистика, быстрый выбор
    profiles/           профили и балансировщики
    connection/         режимы и порты
    apps/               split tunneling
    network/            DNS и routing
    geodata/            GeoData UI
    background/         startup, foreground-service и recovery settings
    diagnostics/        runtime-диагностика и безопасный отчёт
    appearance/         тема
    about/              информация о сборке
  platform/
    android/            Flutter ↔ Android engine bridge
    windows/            Xray process и Windows modes
  shared/
    theme/              Orex glass UI
    widgets/            reusable Orex components

android/app/src/main/kotlin/ru/orex/ray/
  MainActivity.kt                       Flutter IPC bridge к :vpn process
  OrexRayTunnelEvents.kt                cross-process runtime events
  OrexRayVpnService.kt                  foreground VPN service в :vpn process
  OrexRayQuickSettingsTileService.kt    Quick Settings VPN toggle
  OrexRayVpnPermissionActivity.kt       first-run native permission bridge
  OrexRayStartIntentStore.kt            encrypted reconnect state
  OrexRayBootReceiver.kt                optional VPN restore after reboot
  OrexRayDiagnosticsStore.kt            bounded runtime diagnostics
  AndroidSecureStore.kt                 Android Keystore-backed storage
```

Главный принцип: `ProfilesController` хранит маршруты, `XrayConfigBuilder`
строит mode-specific конфиг, а `TunnelController` управляет жизненным циклом
подключения. UI не должен напрямую запускать native core.

## 12. Проверка, debug и release

Сборки теперь устроены одинаково с Orex Messenger: общий builder
`tool\build_channel.ps1` и две короткие точки входа — debug/release.

Базовый quality gate:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Настоящая debug-сборка Android + Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1
```

Release Android + Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
```

Платформу можно ограничить одинаковым параметром:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Platform android
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Platform windows
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Platform android
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Platform windows
```

Артефакты имеют одну схему имени и лежат в `dist\<debug|release>\<version>\`:

```text
OrexRay-<version>-debug.apk
OrexRay-<version>-debug-x64.zip
OrexRay-<version>-arm64-v8a.apk
OrexRay-<version>-armeabi-v7a.apk
OrexRay-<version>-x86_64.apk
OrexRay-<version>-x64-setup.exe
SHA256SUMS.txt
```

Debug Android использует отдельный application id `ru.orex.ray.debug` и имя
`OrexRay Debug`, поэтому может быть установлен рядом с release. Windows debug
упаковывается целиком вместе с DLL/assets и pinned Xray Core; один `.exe` отдельно
не является полноценной portable-сборкой.

Для ADB-сценариев есть отдельный сборщик диагностики:

```powershell
# Собрать debug, установить на подключённый телефон, запустить и начать capture:
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 `
  -PrepareDebug -Area vpn-switch

# Проверить отмену зависшего connecting:
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 `
  -Area vpn-cancel

# Снять batterystats/power/alarm/jobscheduler:
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 `
  -Area battery
```

Подробности:

- [общая схема сборок](docs/release-builds.md);
- [Android release](docs/release-android.md);
- [Windows release](docs/release-windows.md);
- [Android debug/ADB](docs/android-debugging.md).

Release автоматически подписывается Gradle через `android/key.properties` или
`OREX_ANDROID_*`. Debug использует обычный Android debug signing. Release keystore
хранится отдельно от репозитория и не пересоздаётся между версиями.

## 13. Текущий статус

Текущая ветка сфокусирована на долгой фоновой работе, импорте/экспорте и
снижении лишней нагрузки UI:

- Android VPN вынесен в отдельный `:vpn` process и переживает выгрузку Flutter UI;
- foreground stats/ping работают только при активном UI или реально видимом
  notification consumer;
- UI-статистика, notification-статистика и ping получили независимые интервалы;
- timeout/unavailable активного маршрута отображаются как `—` и красное
  health-состояние; зелёный glow означает только подтверждённый успешный ping;
- импорт Xray JSON поддерживает объект, массив, файл, буфер обмена и HTTP(S) URL;
- экспорт умеет сохранять `.json` и копировать один объект или массив выбранных;
- long-press включает множественный выбор; в этом режиме карточки переставляются за отдельный drag-handle, а bulk ping/export/delete остаются рядом с обычными действиями;
- profile screen не подписан на высокочастотные traffic snapshots, а
  неперекрывающиеся glass-карточки используют grouped backdrop blur;
- Android Quick Settings tile и restart state работают из отдельного VPN-process;
- Windows сохраняет system/local proxy и TUN, watchdog/recovery и pinned Xray Core;
- release-документация разделена на Android/Windows и добавлены готовые
  PowerShell build scripts.

### Xray Core pins

Android сейчас закреплён на AndroidLibXrayLite/Xray **26.6.27**. Windows bundle
пока закреплён на **26.4.13**. Более новый upstream не поднимается автоматически:
обновление core должно отдельно обновлять checksum и проходить config/smoke
проверки на обеих платформах. Это важнее, чем следовать latest/pre-release только
ради номера версии.

Legacy-параметр `allowInsecure` больше не считается поддерживаемой возможностью:
современный Xray удалил его. Старые данные могут оставаться читаемыми для
миграции, но новые конфигурации не должны полагаться на отключение TLS-проверки.

## 14. Лицензия

OrexRay распространяется по лицензии [MIT](LICENSE): исходный код можно
использовать, изменять и распространять, в том числе коммерчески, при
сохранении уведомления об авторских правах и текста лицензии. Программное
обеспечение предоставляется «как есть», без гарантий.
