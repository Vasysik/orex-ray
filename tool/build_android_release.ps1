param(
  [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
  function Invoke-Native {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) {
      throw "Command failed with exit code $LASTEXITCODE"
    }
  }

  $VersionMatch = [regex]::Match(
    (Get-Content 'pubspec.yaml' -Raw),
    '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
  )
  if (-not $VersionMatch.Success) {
    throw 'pubspec.yaml must contain version: X.Y.Z+N'
  }
  $Release = '{0}.{1}.{2}+{3}' -f `
    $VersionMatch.Groups[1].Value, `
    $VersionMatch.Groups[2].Value, `
    $VersionMatch.Groups[3].Value, `
    $VersionMatch.Groups[4].Value

  if (-not $SkipChecks) {
    Invoke-Native { flutter pub get }
    Invoke-Native { flutter analyze --no-pub }
    Invoke-Native { flutter test --no-pub }
  }

  Invoke-Native { flutter build apk --release --split-per-abi --no-pub }

  $Out = Join-Path $RepoRoot "dist\android\$Release"
  if (Test-Path $Out) {
    Remove-Item -Recurse -Force $Out
  }
  New-Item -ItemType Directory -Force $Out | Out-Null
  $Artifacts = @(
    @{ Source = 'app-arm64-v8a-release.apk'; Abi = 'arm64-v8a' },
    @{ Source = 'app-armeabi-v7a-release.apk'; Abi = 'armeabi-v7a' },
    @{ Source = 'app-x86_64-release.apk'; Abi = 'x86_64' }
  )
  $OutputFiles = @()
  foreach ($Artifact in $Artifacts) {
    $Source = Join-Path $RepoRoot "build\app\outputs\flutter-apk\$($Artifact.Source)"
    if (-not (Test-Path $Source)) { throw "Missing APK: $Source" }
    $Name = "OrexRay-$Release-android-$($Artifact.Abi).apk"
    $Destination = Join-Path $Out $Name
    Copy-Item -Force $Source $Destination
    $OutputFiles += Get-Item $Destination
  }

  $HashLines = foreach ($File in $OutputFiles) {
    $Hash = (Get-FileHash -Algorithm SHA256 $File.FullName).Hash.ToLowerInvariant()
    "$Hash  $($File.Name)"
  }
  Set-Content -Encoding ascii -Path (Join-Path $Out 'SHA256SUMS.txt') -Value $HashLines
  Write-Host "Android release ready: $Out"
} finally {
  Pop-Location
}
