[CmdletBinding()]
param(
  [ValidateSet('general', 'vpn-switch', 'vpn-cancel', 'battery')]
  [string]$Area = 'general',

  [string]$Package,
  [string]$OutputRoot = '.\orexray-test-logs',
  [string]$Serial,

  # Build the real Flutter debug APK, install it and launch it before capture.
  [switch]$PrepareDebug,
  [switch]$SkipBuildChecks,

  [switch]$NoClear,
  [switch]$ResetBatteryStats,
  [switch]$Bugreport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-OrexRayRelease {
  $VersionMatch = [regex]::Match(
    (Get-Content (Join-Path $RepoRoot 'pubspec.yaml') -Raw),
    '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
  )
  if (-not $VersionMatch.Success) {
    throw 'pubspec.yaml must contain version: X.Y.Z+N'
  }
  return '{0}.{1}.{2}+{3}' -f `
    $VersionMatch.Groups[1].Value, `
    $VersionMatch.Groups[2].Value, `
    $VersionMatch.Groups[3].Value, `
    $VersionMatch.Groups[4].Value
}

if ($PrepareDebug) {
  Write-Host '=== Building OrexRay Android debug ===' -ForegroundColor Cyan
  & (Join-Path $PSScriptRoot 'build_debug.ps1') `
    -Platform android `
    -SkipChecks:$SkipBuildChecks
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  throw 'adb не найден в PATH. Добавь Android platform-tools в PATH.'
}

& adb start-server | Out-Null
$DeviceLines = & adb devices
$ConnectedSerials = @(
  $DeviceLines |
    Select-String -Pattern '^(\S+)\s+device$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
)

if ($Serial) {
  if ($ConnectedSerials -notcontains $Serial) {
    throw "Устройство '$Serial' не найдено в состоянии device. Проверь: adb devices"
  }
  $SelectedSerial = $Serial
} else {
  if ($ConnectedSerials.Count -eq 0) {
    throw 'Нет подключённого Android-устройства в состоянии device. Проверь USB debugging и adb devices.'
  }
  if ($ConnectedSerials.Count -gt 1) {
    throw 'Подключено несколько устройств. Передай -Serial <serial>.'
  }
  $SelectedSerial = $ConnectedSerials[0]
}

$AdbTarget = @('-s', $SelectedSerial)
& adb @AdbTarget wait-for-device

function Test-PackageInstalled {
  param([Parameter(Mandatory = $true)][string]$Candidate)
  $Path = ((& adb @AdbTarget shell pm path $Candidate 2>$null) | Out-String).Trim()
  return $LASTEXITCODE -eq 0 -and $Path.StartsWith('package:')
}

function Get-PackageProcesses {
  param([Parameter(Mandatory = $true)][string]$Candidate)

  $Escaped = [regex]::Escape($Candidate)
  $ProcessLines = & adb @AdbTarget shell ps -A 2>$null
  return @(
    $ProcessLines |
      Select-String -Pattern ("\s" + $Escaped + "(?::\S+)?$") |
      ForEach-Object { $_.Line }
  )
}

if ($PrepareDebug) {
  $Release = Get-OrexRayRelease
  $DebugApk = Join-Path $RepoRoot "dist\debug\$Release\OrexRay-$Release-debug-android.apk"
  if (-not (Test-Path $DebugApk)) {
    throw "Debug APK not found after build: $DebugApk"
  }

  Write-Host '=== Installing debug APK ===' -ForegroundColor Cyan
  & adb @AdbTarget install -r $DebugApk
  if ($LASTEXITCODE -ne 0) {
    throw "adb install failed with exit code $LASTEXITCODE"
  }

  $Package = 'ru.orex.ray.debug'
  Write-Host '=== Launching OrexRay Debug ===' -ForegroundColor Cyan
  & adb @AdbTarget shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
  Start-Sleep -Seconds 1
}

$PackageSelection = 'explicit'
if (-not $Package) {
  $Candidates = @('ru.orex.ray.debug', 'ru.orex.ray')
  $ActivityState = (& adb @AdbTarget shell dumpsys activity activities 2>&1) | Out-String
  $Foreground = @(
    $Candidates | Where-Object {
      $Candidate = $_
      $ActivityState -match (
        '(?m)(?:topResumedActivity|mResumedActivity|ResumedActivity).*' +
        [regex]::Escape("$Candidate/")
      )
    }
  )

  if ($Foreground.Count -eq 1) {
    $Package = $Foreground[0]
    $PackageSelection = 'foreground'
  } else {
    $Running = @($Candidates | Where-Object { @(Get-PackageProcesses -Candidate $_).Count -gt 0 })
    if ($Running.Count -eq 1) {
      $Package = $Running[0]
      $PackageSelection = 'running'
    } elseif ($Running.Count -gt 1) {
      throw 'Одновременно запущены OrexRay Release и Debug. Передай -Package явно.'
    } else {
      $Installed = @($Candidates | Where-Object { Test-PackageInstalled -Candidate $_ })
      if ($Installed.Count -eq 1) {
        $Package = $Installed[0]
        $PackageSelection = 'installed'
      } elseif ($Installed.Count -gt 1) {
        throw 'Установлены OrexRay Release и Debug, но ни один не активен. Запусти нужный или передай -Package.'
      } else {
        throw 'OrexRay не найден на устройстве. Используй -PrepareDebug или передай -Package для другого applicationId.'
      }
    }
  }
}

if (-not (Test-PackageInstalled -Candidate $Package)) {
  throw "Пакет '$Package' не установлен на устройстве '$SelectedSerial'."
}

if ($Area -eq 'battery' -and $Package.EndsWith('.debug')) {
  Write-Warning 'Debug build заметно искажает расход батареи. Для цифр по энергоэффективности лучше запусти release ru.orex.ray и повтори -Area battery.'
}

function Invoke-AdbToFile {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $Output = & adb @AdbTarget @Arguments 2>&1
  $Output | Out-File -FilePath $Path -Encoding utf8
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SessionDir = Join-Path $OutputRoot "orexray-$Area-$Stamp"
New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null

$RawLog = Join-Path $SessionDir '01-logcat-full.txt'
$FocusedLog = Join-Path $SessionDir '02-logcat-orexray-focused.txt'
$LogcatErr = Join-Path $SessionDir '03-logcat-stderr.txt'
$DeviceInfo = Join-Path $SessionDir '00-device-info.txt'

@(
  "CapturedAt=$(Get-Date -Format o)"
  "Area=$Area"
  "Package=$Package"
  "PackageSelection=$PackageSelection"
  "Serial=$SelectedSerial"
  "ADB=$((Get-Command adb).Source)"
  ''
  '=== adb devices -l ==='
  (& adb devices -l 2>&1)
  ''
  '=== package version ==='
  (& adb @AdbTarget shell dumpsys package $Package 2>&1 |
    Select-String -Pattern 'versionName=|versionCode=|firstInstallTime=|lastUpdateTime=|debuggable')
  ''
  '=== selected props ==='
  (& adb @AdbTarget shell getprop ro.product.manufacturer 2>&1)
  (& adb @AdbTarget shell getprop ro.product.model 2>&1)
  (& adb @AdbTarget shell getprop ro.build.version.release 2>&1)
  (& adb @AdbTarget shell getprop ro.build.version.sdk 2>&1)
  (& adb @AdbTarget shell getprop ro.build.fingerprint 2>&1)
) | Out-File -FilePath $DeviceInfo -Encoding utf8

if ($ResetBatteryStats) {
  Write-Warning 'Сбрасываю системную статистику batterystats по явному флагу -ResetBatteryStats.'
  & adb @AdbTarget shell dumpsys batterystats --reset | Out-Null
}

if (-not $NoClear) {
  & adb @AdbTarget logcat -c
}

$LogcatArgs = @($AdbTarget + @('logcat', '-b', 'all', '-v', 'threadtime'))
$LogcatProcess = Start-Process `
  -FilePath 'adb' `
  -ArgumentList $LogcatArgs `
  -PassThru `
  -NoNewWindow `
  -RedirectStandardOutput $RawLog `
  -RedirectStandardError $LogcatErr

Write-Host ''
Write-Host "Сбор OrexRay Android-диагностики запущен ($Area)." -ForegroundColor Green
Write-Host "Устройство: $SelectedSerial"
Write-Host "Пакет: $Package ($PackageSelection)"
Write-Host "Каталог: $SessionDir"
Write-Host ''

switch ($Area) {
  'vpn-switch' {
    Write-Host 'Сценарий: подключись к A, затем быстро переключись A -> B -> C и дождись результата.' -ForegroundColor Cyan
  }
  'vpn-cancel' {
    Write-Host 'Сценарий: начни подключение, нажми отмену во время «Создаём подключение», затем подключись снова.' -ForegroundColor Cyan
  }
  'battery' {
    Write-Host 'Сценарий: оставь VPN подключённым на репрезентативное время; по возможности часть времени держи UI в фоне.' -ForegroundColor Cyan
  }
  default {
    Write-Host 'Воспроизведи нужный сценарий в приложении.' -ForegroundColor Cyan
  }
}

Write-Host ''
Write-Host 'Можно поставить метки в logcat:' -ForegroundColor DarkCyan
Write-Host ('  adb -s {0} shell log -p i -t OREXRAY_TEST "CASE=01 START"' -f $SelectedSerial)
Write-Host ('  adb -s {0} shell log -p i -t OREXRAY_TEST "CASE=01 END result=PASS"' -f $SelectedSerial)
Write-Host ''
Read-Host 'После воспроизведения нажми Enter для остановки и упаковки'

# For a debuggable build, request Java/native thread dumps before stopping
# logcat. SIGQUIT does not terminate the app and is especially useful when
# Xray startLoop/stopLoop appears stuck on the :vpn worker.
if ($Package.EndsWith('.debug')) {
  foreach ($ProcessName in @($Package, "$Package`:vpn")) {
    $Pids = ((& adb @AdbTarget shell pidof $ProcessName 2>$null) | Out-String).Trim()
    if ($Pids) {
      foreach ($ProcessId in ($Pids -split '\s+')) {
        if ($ProcessId -match '^\d+$') {
          & adb @AdbTarget shell kill -3 $ProcessId 2>$null | Out-Null
        }
      }
    }
  }
  Start-Sleep -Seconds 1
}

if (-not $LogcatProcess.HasExited) {
  Stop-Process -Id $LogcatProcess.Id -Force
}
Start-Sleep -Milliseconds 500

$CommonDumps = @(
  @{ Name = '10-dumpsys-activity-services.txt'; Args = @('shell', 'dumpsys', 'activity', 'services', $Package) },
  @{ Name = '11-dumpsys-activity-processes.txt'; Args = @('shell', 'dumpsys', 'activity', 'processes') },
  @{ Name = '12-dumpsys-connectivity.txt'; Args = @('shell', 'dumpsys', 'connectivity') },
  @{ Name = '13-dumpsys-network-management.txt'; Args = @('shell', 'dumpsys', 'network_management') },
  @{ Name = '14-dumpsys-netd.txt'; Args = @('shell', 'dumpsys', 'netd') },
  @{ Name = '15-dumpsys-netstats.txt'; Args = @('shell', 'dumpsys', 'netstats') },
  @{ Name = '16-dumpsys-package.txt'; Args = @('shell', 'dumpsys', 'package', $Package) },
  @{ Name = '17-dumpsys-notification.txt'; Args = @('shell', 'dumpsys', 'notification') },
  @{ Name = '18-dumpsys-power.txt'; Args = @('shell', 'dumpsys', 'power') },
  @{ Name = '19-dumpsys-deviceidle.txt'; Args = @('shell', 'dumpsys', 'deviceidle') },
  @{ Name = '20-dumpsys-batterystats.txt'; Args = @('shell', 'dumpsys', 'batterystats', '--charged', $Package) },
  @{ Name = '21-dumpsys-meminfo.txt'; Args = @('shell', 'dumpsys', 'meminfo', $Package) },
  @{ Name = '22-dumpsys-cpuinfo.txt'; Args = @('shell', 'dumpsys', 'cpuinfo') },
  @{ Name = '23-ps.txt'; Args = @('shell', 'ps', '-A') }
)

foreach ($Dump in $CommonDumps) {
  Invoke-AdbToFile -Arguments $Dump.Args -Path (Join-Path $SessionDir $Dump.Name)
}

if ($Area -eq 'battery') {
  Invoke-AdbToFile -Arguments @('shell', 'dumpsys', 'alarm') `
    -Path (Join-Path $SessionDir '30-dumpsys-alarm.txt')
  Invoke-AdbToFile -Arguments @('shell', 'dumpsys', 'jobscheduler') `
    -Path (Join-Path $SessionDir '31-dumpsys-jobscheduler.txt')
}

$Focus = @(
  'OREXRAY_TEST',
  'ru\.orex\.ray',
  '\bOrexRay\b',
  '\bXray\b',
  'libv2ray',
  'VpnService',
  'ConnectivityService',
  'NetworkAgent',
  'AndroidRuntime',
  'FATAL EXCEPTION',
  'ANR in ',
  'ActivityManager',
  'ActivityTaskManager'
)

if (Test-Path $RawLog) {
  Get-Content -Path $RawLog |
    Select-String -Pattern ($Focus -join '|') |
    ForEach-Object { $_.Line } |
    Out-File -FilePath $FocusedLog -Encoding utf8
}

if ($Bugreport) {
  Write-Host 'Снимаю adb bugreport — архив может быть большим...' -ForegroundColor Yellow
  & adb @AdbTarget bugreport (Join-Path $SessionDir '40-bugreport.zip')
}

$ZipPath = "$SessionDir.zip"
Compress-Archive -Path (Join-Path $SessionDir '*') -DestinationPath $ZipPath -Force

Write-Host ''
Write-Host "Готово: $ZipPath" -ForegroundColor Green
Write-Host "Для первого просмотра: $FocusedLog"
Write-Host 'Перед отправкой проверь архив на приватные URL, UUID/ключи профилей и другие чувствительные данные.'
