param(
    [switch]$BuildBundle,
    [switch]$SkipTests
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
        return ($required | Where-Object {
            [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
        }).Count -eq 0
    }

    $versionLine = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if ($null -eq $versionLine) { throw "Не найдена version: в pubspec.yaml" }
    $version = $versionLine.Matches[0].Groups[1].Value.Trim()

    Write-Host "OrexRay Android release $version" -ForegroundColor Green
    if (-not (Test-ReleaseSigningConfigured)) {
        throw @"
Android release signing не настроен.
Как и в Orex Messenger, release автоматически подписывается через android/key.properties
или OREX_ANDROID_STORE_FILE / STORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD.
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

    # Keep the APK build identical to Orex Messenger: release, split per ABI,
    # no Dart obfuscation, and signing handled automatically by Gradle.
    Invoke-Flutter -Arguments @(
        "build",
        "apk",
        "--release",
        "--split-per-abi",
        "--no-pub"
    )

    $distDir = Join-Path $projectRoot "dist/android/$version"
    New-Item -ItemType Directory -Force $distDir | Out-Null

    $apkOutputs = @(
        @{ Abi = "armeabi-v7a"; Source = "app-armeabi-v7a-release.apk" },
        @{ Abi = "arm64-v8a"; Source = "app-arm64-v8a-release.apk" },
        @{ Abi = "x86_64"; Source = "app-x86_64-release.apk" }
    )

    $artifacts = @()
    foreach ($apk in $apkOutputs) {
        $source = Join-Path $projectRoot "build/app/outputs/flutter-apk/$($apk.Source)"
        if (-not (Test-Path $source)) { throw "Не найден release APK: $source" }
        $target = Join-Path $distDir "OrexRay-$version-android-$($apk.Abi).apk"
        Copy-Item $source $target -Force
        $artifacts += $target
    }

    if ($BuildBundle) {
        Invoke-Flutter -Arguments @("build", "appbundle", "--release", "--no-pub")
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
    $lockHash = (Get-FileHash -Algorithm SHA256 "pubspec.lock").Hash.ToLowerInvariant()

    @"
OrexRay $version
PackageId=ru.orex.ray
BuiltAtUtc=$(Get-Date).ToUniversalTime().ToString("o")
GitCommit=$commit
PubspecLockSha256=$lockHash
SplitPerAbi=true
Obfuscated=false
"@ | Set-Content -Path (Join-Path $distDir "BUILD-INFO.txt") -Encoding UTF8

    Write-Host "`nRelease готов:" -ForegroundColor Green
    foreach ($artifact in $artifacts) { Write-Host "  $artifact" }
    Write-Host "  $hashFile"
    Write-Host "`nДля большинства современных телефонов отдавай arm64-v8a APK." -ForegroundColor Cyan
}
finally {
    Pop-Location
}
