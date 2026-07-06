# Как обновиться с OrexRay 0.2.0 до 0.3.0

1. Сделайте копию проекта или commit в Git.
2. Распакуйте `OrexRay-0.3.0-update.zip` в корень проекта с заменой файлов.
3. Запустите проверки.

## Windows

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

`0.3.0` больше не добавляет `runner.exe.manifest` напрямую в список исходников executable. Manifest компилируется через `Runner.rc`, а linker-generated manifest отключён. Это устраняет конкретный build-step, на котором возникал `LNK1327` при запуске `mt.exe`.

## Android

```powershell
flutter devices
flutter clean
flutter pub get
flutter run -d <ANDROID_DEVICE_ID>
```

Первый Android build скачает pinned AAR. Ожидаемые строки в build log:

```text
OrexRay: downloading Android Xray core v26.6.27 (about 56 MB)...
OrexRay: Android Xray core is ready.
```

При первом Connect Android покажет системное окно разрешения VPN.

## Если Android core download не прошёл

Проверьте доступ к GitHub и повторите build. Недокачанный `.part` файл удаляется автоматически. Файл с неверным SHA-256 не принимается.
