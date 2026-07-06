param(
    [switch]$BuildBundle,
    [switch]$SkipTests,
    [switch]$NoObfuscate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    function Invoke-Flutter([string[]]$Arguments) {
        Write-Host "`n> flutter $($Arguments -join ' ')" -ForegroundColor Cyan
        & flutter @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter завершился с кодом $LASTEXITCODE"
        }
    }

    function Test-ReleaseSigningConfigured {
        if (Test-Path "android/key.properties") { return $true }
        $required = @(
            "OREX_ANDROID_STORE_FILE",
            "OREX_ANDROID_STORE_PASSWORD",
            "OREX_ANDROID_KEY_ALIAS",
            "OREX_ANDROID_KEY_PASSWORD"
        )
        return ($required | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }).Count -eq 0
    }

    $versionLine = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if ($null -eq $versionLine) { throw "Не найдена version: в pubspec.yaml" }
    $version = $versionLine.Matches[0].Groups[1].Value.Trim()

    Write-Host "OrexRay Android release $version" -ForegroundColor Green
    if (-not (Test-ReleaseSigningConfigured)) {
        throw @"
Android release signing не настроен.
Создай android/key.properties по android/key.properties.example
или задай OREX_ANDROID_STORE_FILE / STORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD.
"@
    }

    Invoke-Flutter -Arguments @("pub", "get")
    if (-not (Test-Path "pubspec.lock")) {
        throw "flutter pub get завершился без pubspec.lock; release-сборка остановлена"
    }
    Invoke-Flutter -Arguments @("analyze", "--no-pub")
    if (-not $SkipTests) {
        Invoke-Flutter -Arguments @("test", "--no-pub")
    }

    $symbolsDir = Join-Path $projectRoot "build/symbols/android/$version"
    New-Item -ItemType Directory -Force $symbolsDir | Out-Null

    $common = @(
        "--release",
        "--no-pub",
        "--dart-define=OREX_ENV=production",
        "--dart-define=OREX_DEBUG_LOGS=false"
    )
    if (-not $NoObfuscate) {
        $common += "--obfuscate"
        $common += "--split-debug-info=$symbolsDir"
    }

    Invoke-Flutter -Arguments (@("build", "apk") + $common)

    $distDir = Join-Path $projectRoot "dist/android/$version"
    New-Item -ItemType Directory -Force $distDir | Out-Null
    $apkSource = Join-Path $projectRoot "build/app/outputs/flutter-apk/app-release.apk"
    if (-not (Test-Path $apkSource)) { throw "Не найден release APK: $apkSource" }
    $apkTarget = Join-Path $distDir "OrexRay-$version-android.apk"
    Copy-Item $apkSource $apkTarget -Force

    $artifacts = @($apkTarget)
    if ($BuildBundle) {
        Invoke-Flutter -Arguments (@("build", "appbundle") + $common)
        $aabSource = Join-Path $projectRoot "build/app/outputs/bundle/release/app-release.aab"
        if (-not (Test-Path $aabSource)) { throw "Не найден release AAB: $aabSource" }
        $aabTarget = Join-Path $distDir "OrexRay-$version-android.aab"
        Copy-Item $aabSource $aabTarget -Force
        $artifacts += $aabTarget
    }

    $hashLines = foreach ($artifact in $artifacts) {
        $hash = (Get-FileHash -Algorithm SHA256 $artifact).Hash.ToLowerInvariant()
        "$hash  $(Split-Path $artifact -Leaf)"
    }
    $hashFile = Join-Path $distDir "SHA256SUMS.txt"
    $hashLines | Set-Content -Path $hashFile -Encoding ASCII

    $commit = "unknown"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $candidate = (& git rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $candidate) { $commit = $candidate.Trim() }
    }
    $lockFile = Join-Path $projectRoot "pubspec.lock"
    $lockHash = if (Test-Path $lockFile) {
        (Get-FileHash -Algorithm SHA256 $lockFile).Hash.ToLowerInvariant()
    } else {
        "missing"
    }

    @"
OrexRay $version
BuiltAtUtc=$(Get-Date).ToUniversalTime().ToString("o")
GitCommit=$commit
PubspecLockSha256=$lockHash
Obfuscated=$(-not $NoObfuscate)
Symbols=$symbolsDir
"@ | Set-Content -Path (Join-Path $distDir "BUILD-INFO.txt") -Encoding UTF8

    Write-Host "`nRelease готов:" -ForegroundColor Green
    foreach ($artifact in $artifacts) { Write-Host "  $artifact" }
    Write-Host "  $hashFile"
    if (-not $NoObfuscate) {
        Write-Host "`nНЕ УДАЛЯЙ symbols: $symbolsDir" -ForegroundColor Yellow
        Write-Host "Они нужны для расшифровки stack trace обфусцированной сборки."
    }
}
finally {
    Pop-Location
}
