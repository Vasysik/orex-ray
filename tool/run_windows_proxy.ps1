$ErrorActionPreference = "Stop"

Write-Host "Building OrexRay for Windows..." -ForegroundColor Cyan
flutter build windows --debug
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exe = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Debug\orex_ray.exe"
Write-Host "Starting OrexRay without elevation. Use System Proxy or Local Proxy mode." -ForegroundColor Green
Start-Process -FilePath $exe
