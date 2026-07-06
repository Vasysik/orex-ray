# OrexRay 0.4.1 hotfix

Исправлена несовместимость с актуальным Flutter `RadioGroup`: `onChanged` теперь всегда передаётся как обязательный callback, а переключатели блокируются через `RadioListTile.enabled` во время активного соединения.

Затронуты файлы:

- `lib/features/settings/settings_screen.dart`
- `pubspec.yaml`
