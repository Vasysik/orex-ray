# OrexRay Release Builds

Эта инструкция нужна для локальной private-beta сборки `0.6.2+1` и передачи
артефактов товарищам. Здесь нет CI-обёрток и `.ps1`-скриптов: все команды
запускаются напрямую из PowerShell в корне проекта.

## 1. Перед сборкой

Проверь версию в `pubspec.yaml`:

```yaml
version: 0.6.2+1
```

Обнови зависимости и пройди обязательный gate:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Release APK не собирай, пока analyze или tests красные.

## 2. Android release signing

Для первого релиза нужен постоянный keystore. Создай его **один раз** на машине,
с которой будут собираться обновления:

```powershell
New-Item -ItemType Directory -Force android\secrets

keytool -genkeypair -v `
  -keystore android\secrets\orexray-release.jks `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias orexray
```

Сохрани пароли и сделай минимум две офлайн-копии файла:

```text
android\secrets\orexray-release.jks
```

Потеря этого keystore означает, что уже розданные APK с package id
`ru.orex.ray` нельзя будет обновлять той же подписью.

## 3. `android/key.properties`

Создай файл:

```text
android/key.properties
```

Содержимое:

```properties
storeFile=secrets/orexray-release.jks
storePassword=ВАШ_STORE_PASSWORD
keyAlias=orexray
keyPassword=ВАШ_KEY_PASSWORD
```

`storeFile` читается относительно папки `android/`.

`android/key.properties`, `android/secrets/`, `*.jks` и `*.keystore` уже
исключены из git. Не добавляй их в ZIP с исходниками и не отправляй вместе с
APK.

Вместо `key.properties` можно использовать переменные окружения:

```text
OREX_ANDROID_STORE_FILE
OREX_ANDROID_STORE_PASSWORD
OREX_ANDROID_KEY_ALIAS
OREX_ANDROID_KEY_PASSWORD
```

Пример для текущего PowerShell-сеанса:

```powershell
$env:OREX_ANDROID_STORE_FILE = "secrets/orexray-release.jks"
$env:OREX_ANDROID_STORE_PASSWORD = "..."
$env:OREX_ANDROID_KEY_ALIAS = "orexray"
$env:OREX_ANDROID_KEY_PASSWORD = "..."
```

## 4. Android release APK

Сначала ещё раз пройди gate без повторного `pub get`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Собери release APK с obfuscation и отдельными символами:

```powershell
flutter build apk --release --no-pub `
  --obfuscate `
  --split-debug-info=build\symbols\android\0.6.2+1
```

Готовый APK:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Символы:

```text
build\symbols\android\0.6.2+1\
```

Символы не отправляй тестировщикам и не удаляй: они нужны для разбора
обфусцированных Dart stack traces.

## 5. Подготовить папку для раздачи

```powershell
$Version = "0.6.2+1"
$Out = "dist\android\$Version"

New-Item -ItemType Directory -Force $Out
Copy-Item `
  build\app\outputs\flutter-apk\app-release.apk `
  "$Out\OrexRay-$Version-android.apk"
```

Посчитать SHA-256:

```powershell
Get-FileHash `
  "$Out\OrexRay-$Version-android.apk" `
  -Algorithm SHA256 | Format-List
```

Записать checksum в файл:

```powershell
$Hash = (Get-FileHash `
  "$Out\OrexRay-$Version-android.apk" `
  -Algorithm SHA256).Hash.ToLower()

"$Hash  OrexRay-$Version-android.apk" | `
  Set-Content "$Out\SHA256SUMS.txt" -Encoding ascii
```

Итог:

```text
dist\
  android\
    0.6.2+1\
      OrexRay-0.6.2+1-android.apk
      SHA256SUMS.txt
```

## 6. Проверить подпись APK

Найди `apksigner.bat` в Android SDK `build-tools` и выполни:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<VERSION>\apksigner.bat" `
  verify --verbose --print-certs `
  "dist\android\0.6.2+1\OrexRay-0.6.2+1-android.apk"
```

Проверь:

- `Verified` без ошибки;
- certificate SHA-256 сохраняется между всеми будущими версиями OrexRay;
- APK не подписан Android debug certificate.

## 7. Установить release APK на устройство

Перед первой раздачей установи именно release-артефакт:

```powershell
adb install -r `
  "dist\android\0.6.2+1\OrexRay-0.6.2+1-android.apk"
```

После обновления поверх debug-сборки Android может отказать из-за другой
подписи. В таком случае для чистой release-проверки удали debug-версию вручную,
затем установи release APK. Перед удалением сохрани нужные профили отдельно.

## 8. Android smoke-проверка

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
перезапуск приложения -> профили и настройки восстановлены
```

Для логов во время smoke-проверки:

```powershell
adb logcat -c
adb logcat -v time OrexRay:I GoLog:I AndroidRuntime:E libc:F "*:S"
```

Для release privacy-проверки отдельно убедись, что обычный успешный трафик не
сыплет подробные destination logs при log level `error`.

## 9. Что отправлять товарищам

Минимально:

- `OrexRay-0.6.2+1-android.apk`;
- `SHA256SUMS.txt`;
- короткий текст: версия, что изменилось, какие сценарии особенно проверить.

Не отправляй:

- release keystore;
- `key.properties`;
- пароли;
- `build/symbols/`;
- полный исходный проект только ради установки APK.

## 10. Windows release build

Windows пока проходит отдельный dogfood-путь. Перед сборкой:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Сборка:

```powershell
flutter build windows --release --no-pub
```

Артефакты:

```text
build\windows\x64\runner\Release\
```

Передавать нужно всю папку `Release`, а не один `.exe`, потому что рядом лежат
Flutter runtime и native DLL.

Перед более широкой Windows-раздачей нужен отдельный security-проход по
локальному хранению профилей и recovery системного proxy.
