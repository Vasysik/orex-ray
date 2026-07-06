# Milestone 03 — Android VPN + Windows build fix

## Готово

- [x] Исправлен Windows `LNK1327` путь: manifest больше не объединяется через linker `mt.exe`.
- [x] UAC/DPI manifest встроен в `Runner.rc` как `RT_MANIFEST`.
- [x] Добавлен `/MANIFEST:NO` для linker-generated manifest.
- [x] Добавлен Android `VpnService`.
- [x] Добавлен системный VPN permission flow.
- [x] Добавлен foreground service для долгоживущего VPN.
- [x] Добавлено создание IPv4 TUN и default route.
- [x] Добавлена передача TUN fd в Android Xray Core.
- [x] Подключён pinned `AndroidLibXrayLite` AAR с SHA-256 проверкой.
- [x] Добавлены MethodChannel и EventChannel.
- [x] Добавлены live status, traffic counters и duration.
- [x] Android включён в `TunnelEngineFactory`.
- [x] Добавлен отдельный Android TUN config без Windows auto-routing полей.
- [x] Обновлена версия UI до 0.3.0.

## Проверено в текущей среде

- XML manifest/resources парсятся;
- относительные Dart imports существуют;
- изменённые исходники имеют сбалансированные delimiters;
- Android native Kotlin слой компилируется с API-совместимыми stubs;
- Windows resource/CMake invariants для обхода `mt.exe` присутствуют.

## Что нужно подтвердить на реальных платформах

- `flutter analyze` и `flutter test` после накатывания обновления;
- Windows native build на установленном Visual Studio/Windows SDK;
- Android Gradle build с реальным скачанным AAR;
- первое VLESS/REALITY подключение на реальном Android устройстве.
