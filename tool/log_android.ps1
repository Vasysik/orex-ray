$ErrorActionPreference = "Stop"

$adb = (Get-Command adb -ErrorAction Stop).Source
& $adb logcat -c
Write-Host "OrexRay logs only. Press Ctrl+C to stop." -ForegroundColor Cyan
& $adb logcat -v time "OrexRay:I" "AndroidRuntime:E" "libc:F" "DEBUG:F" "*:S"
