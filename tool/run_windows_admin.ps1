$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    Write-Host 'Building OrexRay for Windows (debug)...'
    flutter build windows --debug

    $exe = Join-Path $projectRoot 'build\windows\x64\runner\Debug\orex_ray.exe'
    if (-not (Test-Path $exe)) {
        throw "OrexRay executable not found: $exe"
    }

    Write-Host 'Starting OrexRay as Administrator...'
    Start-Process -FilePath $exe -Verb RunAs -WorkingDirectory (Split-Path $exe)
}
finally {
    Pop-Location
}
