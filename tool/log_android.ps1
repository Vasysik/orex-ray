$ErrorActionPreference = "Stop"

$adb = (Get-Command adb -ErrorAction Stop).Source
& $adb logcat -c
Write-Host "OrexRay + Xray crash logs only. Press Ctrl+C to stop." -ForegroundColor Cyan
& $adb logcat -v time `
  "OrexRay:V" `
  "GoLog:I" `
  "Go:E" `
  "AndroidRuntime:E" `
  "libc:F" `
  "DEBUG:F" `
  "*:S"
