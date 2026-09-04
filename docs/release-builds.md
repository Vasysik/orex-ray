# OrexRay: release builds

Единственный источник версии — `version:` в `pubspec.yaml`. Перед релизом всегда
должны проходить:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Для готовой сборки есть единая команда:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
```

Она запускает quality gate один раз, затем собирает Android и Windows и кладёт
готовые файлы вместе с `SHA256SUMS.txt` в `dist\`.

Можно собрать платформу отдельно:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Platform android
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Platform windows
```

Подробности и smoke-checklist:

- [Android release](release-android.md)
- [Windows release](release-windows.md)

Не передавай другим людям release keystore, `android/key.properties`, пароли или
локальные секреты.
