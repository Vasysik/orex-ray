# OrexRay: debug and release builds

Единственный источник версии — `version:` в `pubspec.yaml`. Общая логика сборки
находится в `tool\build_channel.ps1`; `build_debug.ps1` и `build_release.ps1`
только выбирают режим.

По умолчанию перед любой сборкой выполняется единый quality gate:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Его можно пропустить только осознанно через `-SkipChecks`.

## Debug

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1
```

Или одна платформа:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Platform android
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Platform windows
```

Debug — настоящий Flutter debug build. Android получает package id
`ru.orex.ray.debug` и может быть установлен рядом с release. Windows debug
упаковывается целым runner-каталогом вместе с pinned Xray Core.

## Release

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
```

Или одна платформа:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Platform android
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Platform windows
```

Старые `build_android_release.ps1` и `build_windows_release.ps1` оставлены как
совместимые обёртки и больше не содержат отдельной копии build-логики.

## Артефакты

Все режимы используют одинаковую структуру:

```text
dist\debug\<x.y.z+n>\
  OrexRay-<version>-debug.apk
  OrexRay-<version>-debug-x64.zip
  SHA256SUMS.txt

dist\release\<x.y.z+n>\
  OrexRay-<version>-arm64-v8a.apk
  OrexRay-<version>-armeabi-v7a.apk
  OrexRay-<version>-x86_64.apk
  OrexRay-<version>-x64-setup.exe
  SHA256SUMS.txt
```

`-ReuseFlutterBuilds` позволяет только перепаковать уже существующие Flutter
артефакты; pinned Xray Core и итоговые hashes всё равно проверяются/готовятся.

Не передавай другим людям release keystore, `android/key.properties`, пароли или
локальные секреты.
