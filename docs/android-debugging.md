# OrexRay: Android debug and ADB diagnostics

## Быстрый debug build

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Platform android
```

Результат:

```text
dist\debug\<version>\OrexRay-<version>-debug-android.apk
```

Это настоящий Flutter debug APK с package id `ru.orex.ray.debug`; release
`ru.orex.ray` можно держать установленным одновременно.

## Автоматическая подготовка телефона и сбор логов

Самый удобный сценарий:

```powershell
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 `
  -PrepareDebug `
  -Area vpn-switch
```

`-PrepareDebug`:

1. запускает Android debug build;
2. устанавливает APK через `adb install -r`;
3. запускает OrexRay Debug;
4. очищает logcat и начинает capture;
5. после Enter снимает dumpsys/процессы и упаковывает всё в ZIP.

Для быстрого локального повторения без analyze/test можно явно добавить
`-SkipBuildChecks`.

## Сценарии

```powershell
# Быстрая смена A -> B -> C при активном VPN
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 -Area vpn-switch

# Connecting -> отмена -> новое подключение
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 -Area vpn-cancel

# Общая диагностика
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 -Area general

# Энергоэффективность: batterystats, power, alarm, jobscheduler
powershell -ExecutionPolicy Bypass -File tool\collect_orexray_android_logs.ps1 -Area battery
```

Если подключено несколько устройств, укажи `-Serial <adb-serial>`. Если одновременно
установлены debug и release и нужный процесс нельзя определить автоматически,
укажи `-Package ru.orex.ray.debug` или `-Package ru.orex.ray`.

`-ResetBatteryStats` сбрасывает системную статистику батареи перед сценарием и
поэтому выполняется только по явному флагу. Для реальных сравнений расхода используй
release `ru.orex.ray`: debug/JIT/служебные хуки заметно искажают battery numbers.

## Что попадает в архив

- полный и сфокусированный logcat;
- для debug package перед завершением capture — SIGQUIT thread dump main и `:vpn` процессов (без завершения приложения);
- `dumpsys activity services/processes`;
- connectivity/network management/netd/netstats;
- package/notification/power/deviceidle;
- `batterystats --charged`, meminfo, cpuinfo и список процессов;
- для `battery` дополнительно alarm/jobscheduler;
- по `-Bugreport` — полный Android bugreport.

Перед отправкой архива проверь его на приватные URL, UUID/ключи профилей и другие
чувствительные данные.
