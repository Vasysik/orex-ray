# OrexRay: Android release

## Подпись

Release package id — `ru.orex.ray`. Gradle требует постоянный release key из
`android/key.properties` либо переменных окружения:

```text
OREX_ANDROID_STORE_FILE
OREX_ANDROID_STORE_PASSWORD
OREX_ANDROID_KEY_ALIAS
OREX_ANDROID_KEY_PASSWORD
```

Пример `android/key.properties`:

```properties
storeFile=secrets/orex-release.jks
storePassword=<STORE_PASSWORD>
keyAlias=orex
keyPassword=<KEY_PASSWORD>
```

Файл и keystore не коммитятся. Для обновления уже установленного release нужен
тот же сертификат, которым подписана предыдущая версия.

## Сборка

Рекомендуемая команда:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_android_release.ps1
```

Скрипт запускает `pub get`, `analyze`, `test`, затем:

```powershell
flutter build apk --release --split-per-abi --no-pub
```

и собирает готовую папку:

```text
dist\android\<x.y.z+n>\
  OrexRay-<version>-android-arm64-v8a.apk
  OrexRay-<version>-android-armeabi-v7a.apk
  OrexRay-<version>-android-x86_64.apk
  SHA256SUMS.txt
```

Для большинства современных телефонов нужен `arm64-v8a`.

## Проверка подписи

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<VERSION>\apksigner.bat" `
  verify --verbose --print-certs `
  "dist\android\<version>\OrexRay-<version>-android-arm64-v8a.apk"
```

У обновлений должны сохраняться package id и certificate SHA-256, а
`versionCode` из `pubspec.yaml` должен расти.

## Smoke-checklist

Перед раздачей проверь минимум:

```text
запуск и восстановление профилей
импорт ссылки и JSON: объект, массив, файл, HTTP(S) URL
копирование/экспорт одного и выбранных профилей
множественный выбор, массовый ping/delete, drag-and-drop порядка
VPN connect/disconnect
смена профиля при активном VPN
TCP/UDP через TUN
локальный SOCKS5/HTTP параллельно VPN
split tunneling: only/exclude
уведомление: speed/ping и их отдельные интервалы
оба notification metric toggle OFF + UI в фоне -> нет stats/ping polling
экран заблокирован -> :vpn process продолжает работать
Quick Settings tile connect/disconnect
restart приложения -> живой :vpn корректно подхватывается UI
```

Для проверки двух процессов при активном VPN:

```powershell
adb shell ps -A | findstr "ru.orex.ray"
```

При открытом UI ожидаются `ru.orex.ray` и `ru.orex.ray:vpn`.
