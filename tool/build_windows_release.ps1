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
  $VersionName = '{0}.{1}.{2}' -f `
    $VersionMatch.Groups[1].Value, `
    $VersionMatch.Groups[2].Value, `
    $VersionMatch.Groups[3].Value
  $BuildNumber = $VersionMatch.Groups[4].Value
  $Release = "$VersionName+$BuildNumber"
  $VersionInfo = "$VersionName.$BuildNumber"

  if (-not $SkipChecks) {
    Invoke-Native { flutter pub get }
    Invoke-Native { flutter analyze --no-pub }
    Invoke-Native { flutter test --no-pub }
  }

  Invoke-Native { flutter build windows --release --no-pub }
  Invoke-Native { & powershell -ExecutionPolicy Bypass -File 'windows\installer\prepare_xray_core.ps1' }

  $Iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $Iscc) {
    throw 'Inno Setup 6 not found. Install it with: winget install --id JRSoftware.InnoSetup -e'
  }

  Invoke-Native {
    & $Iscc `
      "/DMyAppVersion=$Release" `
      "/DMyAppVersionInfo=$VersionInfo" `
      'windows\installer\orexray.iss'
  }

  $Installer = Join-Path $RepoRoot "build\windows\x64\installer\OrexRay-Setup-$Release.exe"
  if (-not (Test-Path $Installer)) { throw "Missing installer: $Installer" }
  $Out = Join-Path $RepoRoot "dist\windows\$Release"
  if (Test-Path $Out) {
    Remove-Item -Recurse -Force $Out
  }
  New-Item -ItemType Directory -Force $Out | Out-Null
  $Destination = Join-Path $Out (Split-Path $Installer -Leaf)
  Copy-Item -Force $Installer $Destination
  $Hash = (Get-FileHash -Algorithm SHA256 $Destination).Hash.ToLowerInvariant()
  "$Hash  $(Split-Path $Destination -Leaf)" | `
    Set-Content -Encoding ascii -Path (Join-Path $Out 'SHA256SUMS.txt')
  Write-Host "Windows release ready: $Out"
} finally {
  Pop-Location
}
