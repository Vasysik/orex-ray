# Milestone 02 — реальное подключение Windows

## Готово

- [x] Удалены фейковые серверы из production UI.
- [x] Добавлен импорт `vless://`.
- [x] Добавлено сохранение и выбор профилей.
- [x] Добавлен генератор актуальной конфигурации Xray.
- [x] Добавлен Windows TUN backend.
- [x] Добавлена загрузка официального Xray Core.
- [x] Добавлена SHA-256 проверка архива.
- [x] Добавлена проверка конфигурации перед запуском.
- [x] Добавлено подключение/отключение и статистика интерфейса.
- [x] Добавлена белочка Orex как маскот.
- [x] Добавлены unit/widget tests для парсера, config builder и UI.

## Следующий этап

Android backend:

1. собрать `libXray.aar` официальным build script;
2. добавить `VpnService`;
3. создать TUN через `VpnService.Builder`;
4. передать file descriptor в libXray как `xray.tun.fd`;
5. связать start/stop/status с Flutter через MethodChannel.

> Статус: Android-этап выполнен в `MILESTONE_03.md`.
