param(
  [ValidateSet('all', 'android', 'windows')]
  [string]$Platform = 'all',
  [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-Native {
  param([Parameter(Mandatory = $true)][scriptblock]$Command)
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE"
  }
}

Push-Location $RepoRoot
try {
  if (-not $SkipChecks) {
    Invoke-Native { flutter pub get }
    Invoke-Native { flutter analyze --no-pub }
    Invoke-Native { flutter test --no-pub }
  }

  if ($Platform -in @('all', 'android')) {
    & (Join-Path $PSScriptRoot 'build_android_release.ps1') -SkipChecks
  }
  if ($Platform -in @('all', 'windows')) {
    & (Join-Path $PSScriptRoot 'build_windows_release.ps1') -SkipChecks
  }
} finally {
  Pop-Location
}
