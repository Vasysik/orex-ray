$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Version = '26.3.27'
$ExpectedSha256 = 'd004c39288ce9ada487c6f398c7c545f7d749e44bdfdd59dbc9f865afba4e1ad'
$ArchiveName = "Xray-windows-64-v$Version.zip"
$DownloadUrl = "https://github.com/XTLS/Xray-core/releases/download/v$Version/Xray-windows-64.zip"
$ReleaseDir = Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release'
$TargetDir = Join-Path $ReleaseDir 'xray-core'
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("orexray-xray-" + [guid]::NewGuid().ToString('N'))
$ArchivePath = Join-Path $TempRoot $ArchiveName
$ExtractDir = Join-Path $TempRoot 'extracted'

try {
  if (-not (Test-Path $ReleaseDir)) {
    throw "Windows release build not found: $ReleaseDir. Run flutter build windows --release first."
  }

  New-Item -ItemType Directory -Force -Path $TempRoot, $ExtractDir | Out-Null
  Write-Host "Downloading pinned Xray Core v$Version..."
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $DownloadUrl -OutFile $ArchivePath

  $ActualSha256 = (Get-FileHash -Algorithm SHA256 -Path $ArchivePath).Hash.ToLowerInvariant()
  if ($ActualSha256 -ne $ExpectedSha256) {
    throw "Xray Core SHA-256 mismatch. Expected $ExpectedSha256, got $ActualSha256."
  }

  Expand-Archive -Path $ArchivePath -DestinationPath $ExtractDir -Force
  $XrayFiles = @(Get-ChildItem -Path $ExtractDir -Recurse -File -Filter 'xray.exe')
  $WintunFiles = @(Get-ChildItem -Path $ExtractDir -Recurse -File -Filter 'wintun.dll')
  $GeoIpFiles = @(Get-ChildItem -Path $ExtractDir -Recurse -File -Filter 'geoip.dat')
  $GeoSiteFiles = @(Get-ChildItem -Path $ExtractDir -Recurse -File -Filter 'geosite.dat')
  if ($XrayFiles.Count -ne 1 -or $WintunFiles.Count -ne 1 -or
      $GeoIpFiles.Count -ne 1 -or $GeoSiteFiles.Count -ne 1) {
    throw 'Pinned Xray archive must contain exactly one xray.exe, wintun.dll, geoip.dat and geosite.dat.'
  }

  if (Test-Path $TargetDir) {
    Remove-Item -Recurse -Force $TargetDir
  }
  New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
  Copy-Item -Force $XrayFiles[0].FullName (Join-Path $TargetDir 'xray.exe')
  Copy-Item -Force $WintunFiles[0].FullName (Join-Path $TargetDir 'wintun.dll')
  Copy-Item -Force $GeoIpFiles[0].FullName (Join-Path $TargetDir 'geoip.dat')
  Copy-Item -Force $GeoSiteFiles[0].FullName (Join-Path $TargetDir 'geosite.dat')
  Copy-Item -Force $ArchivePath (Join-Path $TargetDir $ArchiveName)

  Write-Host "Bundled verified Xray Core v$Version into $TargetDir"
} finally {
  if (Test-Path $TempRoot) {
    Remove-Item -Recurse -Force $TempRoot
  }
}
