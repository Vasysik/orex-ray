# OrexRay: Windows release

## Требования

Нужны Flutter Windows toolchain и Inno Setup 6:

```powershell
winget install --id JRSoftware.InnoSetup -e `
  --accept-package-agreements `
  --accept-source-agreements
```

Windows bundle также включает закреплённый Xray Core. Сейчас Windows pin
остаётся на `26.4.13`; `prepare_xray_core.ps1` проверяет SHA-256 архива перед
копированием `xray.exe`, `wintun.dll`, `geoip.dat` и `geosite.dat`.

## Сборка

Рекомендуемая команда:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_windows_release.ps1
```

Скрипт выполняет:

```text
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
windows\installer\prepare_xray_core.ps1
Inno Setup
```

Результат:

```text
dist\windows\<x.y.z+n>\
  OrexRay-Setup-<version>.exe
  SHA256SUMS.txt
```

Не распространяй один `orex_ray.exe`: рядом требуются Flutter/native DLL и
папка Xray Core. Inno Setup забирает весь `build\windows\x64\runner\Release`.

## Smoke-checklist

```text
установка и обновление поверх предыдущей версии
запуск без elevation в system/local proxy
system proxy connect/disconnect и восстановление системных настроек
TUN при включённом запуске с правами администратора
SOCKS5/HTTP
проверка ping и интервала UI statistics
импорт/экспорт JSON
восстановление Xray Core из Диагностики
удаление/повторная установка без потери пользовательских app-data настроек
```

## Обновление Xray Core

Не меняй номер версии без одновременного обновления URL/SHA-256 и проверки
конфигов OrexRay через новый `xray.exe`. Актуальный upstream может быть
pre-release, поэтому pin обновляется отдельным проверяемым изменением, а не как
побочный эффект обычного релиза приложения.
