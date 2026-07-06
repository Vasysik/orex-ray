# Milestone 01 — OrexRay UI foundation

Готово:

- дизайн-система Orex перенесена из Orex Messenger;
- адаптивный shell для Android и Windows;
- главный экран подключения;
- кнопка connect/disconnect с переходными состояниями;
- mock-статистика трафика и длительности;
- экран профилей;
- экран настроек и переключение темы;
- `TunnelEngine` + `TunnelController`;
- заготовки Android MethodChannel engine и Windows Process engine.

Следующий milestone:

1. `vless://` parser;
2. модель реального Xray-профиля;
3. генератор `config.json`;
4. Windows engine с `xray.exe` + TUN/Wintun;
5. затем Android `VpnService` + libXray.
