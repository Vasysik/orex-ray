# OrexRay Release Builds

Эта инструкция повторяет Android release-путь Orex Messenger: обычный Flutter
release, APK по ABI, без Dart obfuscation. Подпись выполняет Gradle автоматически
из `android/key.properties` или `OREX_ANDROID_*`.

## 1. Перед сборкой

Проверь версию в `pubspec.yaml`, затем выполни:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Release APK не собирай, пока analyze или tests красные.

## 2. Как работает подпись

Flutter/Gradle **не должны создавать новый release key при каждой сборке**.
Release key создаётся один раз и потом автоматически используется во всех
обновлениях. Именно поэтому Android может проверить, что обновление выпустил тот
же разработчик.

OrexRay использует тот же механизм и те же имена параметров, что Orex Messenger:

```text
android/key.properties
OREX_ANDROID_STORE_FILE
OREX_ANDROID_STORE_PASSWORD
OREX_ANDROID_KEY_ALIAS
OREX_ANDROID_KEY_PASSWORD
```

Для одинаковой developer signing identity у Orex приложений используй тот же
реальный keystore и те же значения `key.properties`, что на release-машине Orex
Messenger. Например:

```properties
storeFile=secrets/orex-release.jks
storePassword=ВАШ_STORE_PASSWORD
keyAlias=orex
keyPassword=ВАШ_KEY_PASSWORD
```

`storeFile` читается относительно папки `android/`. Сам keystore и
`android/key.properties` не коммитятся.

Важно: если OrexRay уже раздавался с другим release key и должен обновляться
поверх той версии, нельзя просто переключиться на ключ Messenger. Для обновления
нужен именно прежний сертификат OrexRay. Если публичной цепочки обновлений ещё
нет, один общий Orex release key упрощает дальнейшие локальные сборки.

Без настроенной подписи release должен завершиться ошибкой, а не тихо стать
артефактом для раздачи. Android отклоняет unsigned release APK как
недействительный или повреждённый пакет.

## 3. Android release APK — так же, как Orex Messenger

Команда:

```powershell
flutter build apk --release --split-per-abi --no-pub
```

Никаких `--obfuscate` и `--split-debug-info` здесь нет. Для OrexRay obfuscation
не даёт полезной защиты конфигов, URL, assets или native Xray library, зато
усложняет stack traces и добавляет отдельное хранение symbols. Если появится
отдельная реальная причина скрывать Dart symbols, это можно вернуть как
осознанный release-профиль, а не включать по умолчанию.

Артефакты:

```text
build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
build\app\outputs\flutter-apk\app-x86_64-release.apk
```

Для большинства современных Android-телефонов нужен:

```text
app-arm64-v8a-release.apk
```

## 4. Проверить подпись APK

Проверяй именно тот APK, который собираешься установить или отправить:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<VERSION>\apksigner.bat" `
  verify --verbose --print-certs `
  "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

У release-обновлений должны сохраняться:

- package id `ru.orex.ray`;
- certificate SHA-256;
- возрастающий `versionCode` из `pubspec.yaml`.

## 5. Почему Android пишет «конфликтует с другим пакетом»

Release package id OrexRay — `ru.orex.ray`. Android не разрешает поставить APK
поверх уже установленного пакета с тем же id, если сертификаты подписи разные.
Чаще всего это старая debug-сборка или release, созданный другим keystore.

Посмотреть, есть ли пакет на устройстве:

```powershell
adb shell pm path ru.orex.ray
```

Получить точную ошибку установки:

```powershell
adb install -r `
  "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

Если старая установка не нужна, сохрани профили и удали её один раз:

```powershell
adb uninstall ru.orex.ray
```

После этого установи release APK заново. Если данные старой установки нужно
сохранить, решение только одно: собрать новый APK тем же signing key, которым
подписана уже установленная версия.

Начиная с этой версии debug получает отдельный package id:

```text
ru.orex.ray.debug
```

Поэтому будущие debug и release сборки смогут стоять рядом и больше не будут
блокировать друг друга.

## 6. Подготовить папку для раздачи

```powershell
$Version = (Select-String -Path pubspec.yaml -Pattern "^version:\s*(.+)$").Matches[0].Groups[1].Value.Trim()
$Out = "dist\android\$Version"
New-Item -ItemType Directory -Force $Out

Copy-Item `
  "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" `
  "$Out\OrexRay-$Version-android-arm64-v8a.apk"

$Hash = (Get-FileHash `
  "$Out\OrexRay-$Version-android-arm64-v8a.apk" `
  -Algorithm SHA256).Hash.ToLower()

"$Hash  OrexRay-$Version-android-arm64-v8a.apk" | `
  Set-Content "$Out\SHA256SUMS.txt" -Encoding ascii
```

Если нужны все три ABI для раздачи, повтори тот же блок `Copy-Item` для `app-armeabi-v7a-release.apk` и `app-x86_64-release.apk`. Отдельные helper-скрипты не нужны: release-процесс выше полностью описывает, что именно собирается и куда копируется.

## 7. Android smoke-проверка

Минимальный сценарий перед отправкой товарищам:

```text
чистый запуск -> splash -> главная
импорт VLESS из буфера обмена
создание нового профиля без смены текущего активного маршрута
редактирование профиля
проверка ping с карточки и с главной
VPN connect -> интернет TCP/UDP
экран погашен -> VPN продолжает работать
уведомление -> скорость + задержка без слова Ping
смена профиля во включённом VPN -> автоматическое переподключение
VPN + локальный SOCKS5 одновременно
split tunneling: только выбранные
split tunneling: кроме выбранных
поиск системного приложения и отображение иконки
создание балансировщика
балансировщик с direct fallback
балансировщик с profile fallback
disconnect из приложения
disconnect из notification action
добавление плитки OrexRay VPN через редактирование быстрых настроек
quick tile: connect последнего успешно запущенного VPN
quick tile: disconnect активного VPN
quick tile: первый запуск корректно запрашивает системное разрешение VPN
перезапуск приложения -> профили и настройки восстановлены
```

Логи:

```powershell
adb logcat -c
adb logcat -v time OrexRay:I GoLog:I AndroidRuntime:E libc:F "*:S"
```

## 8. Что отправлять товарищам

Минимально:

- `OrexRay-<version-from-pubspec>-android-arm64-v8a.apk`;
- `SHA256SUMS.txt`;
- короткий текст: версия, что изменилось, какие сценарии особенно проверить.

Не отправляй release keystore, `key.properties` и пароли.

## 9. Windows release build

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
```

Готовое приложение находится в:

```text
build\windows\x64\runner\Release\
```

Один `orex_ray.exe` отдельно не переносится: рядом нужны Flutter runtime и
native DLL.

## 10. Windows installer вместо zip

Схема повторяет Orex Messenger: Inno Setup забирает **всю** release-папку и
собирает один user-level `.exe` установщик.

Установить Inno Setup один раз:

```powershell
winget install --id JRSoftware.InnoSetup -e `
  --accept-package-agreements `
  --accept-source-agreements
```

После успешной Windows release-сборки задай версию из `pubspec.yaml` и передай её в Inno Setup:

```powershell
$VersionLine = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$').Matches[0]
$Version = '{0}.{1}.{2}+{3}' -f `
  $VersionLine.Groups[1].Value, `
  $VersionLine.Groups[2].Value, `
  $VersionLine.Groups[3].Value, `
  $VersionLine.Groups[4].Value
$VersionInfo = '{0}.{1}.{2}.{3}' -f `
  $VersionLine.Groups[1].Value, `
  $VersionLine.Groups[2].Value, `
  $VersionLine.Groups[3].Value, `
  $VersionLine.Groups[4].Value

$Iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

& $Iscc `
  "/DMyAppVersion=$Version" `
  "/DMyAppVersionInfo=$VersionInfo" `
  windows\installer\orexray.iss
```

Артефакт:

```text
build\windows\x64\installer\OrexRay-Setup-<version-from-pubspec>.exe
```

Установщик:

- ставит OrexRay в `%LOCALAPPDATA%\Programs\OrexRay`;
- не требует админских прав для самой установки;
- создаёт пункт в меню «Пуск»;
- предлагает необязательный ярлык на рабочем столе;
- забирает все DLL и данные из `build\windows\x64\runner\Release\`;
- запускает OrexRay после установки, если пользователь не снял галочку.

Режим Windows VPN/TUN всё равно может потребовать запуск самого OrexRay с
правами администратора. Это не причина делать весь установщик системным или
требующим UAC: системный и локальный proxy-режимы работают без elevation.

При смене версии обновляй только `pubspec.yaml`. Команды выше читают эту строку и передают в Inno Setup Flutter-вид `x.y.z+n` для имени установщика и Windows-вид `x.y.z.n` для version resource.
