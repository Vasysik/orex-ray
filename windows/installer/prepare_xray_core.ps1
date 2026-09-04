param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Version = '26.4.13'
$ArchiveName = "Xray-windows-64-v$Version.zip"
$DownloadUrl = "https://github.com/XTLS/Xray-core/releases/download/v$Version/Xray-windows-64.zip"
$ExpectedSha256 = '8b8bac59966883e97d6b11a91c6db6115e6bbfcea4c94695bb77de6356ef0034'
$HashFileName = "xray-core.sha256"
$RunnerDir = Join-Path $PSScriptRoot "..\..\build\windows\x64\runner\$Configuration"
$TargetDir = Join-Path $RunnerDir 'xray-core'
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("orexray-xray-" + [guid]::NewGuid().ToString('N'))
$ArchivePath = Join-Path $TempRoot $ArchiveName
$ExtractDir = Join-Path $TempRoot 'extracted'

function Download-FileWithRetry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  $MaxAttempts = 4
  $LastError = $null

  # GitHub requires modern TLS. This is relevant for Windows PowerShell 5.1,
  # whose process-wide default can otherwise depend on the machine policy.
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {
    # Continue: PowerShell 7+ and current Windows already negotiate TLS correctly.
  }

  for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
    Remove-Item -Force -ErrorAction SilentlyContinue $Destination
    try {
      Write-Host "Download attempt $Attempt/$MaxAttempts with Invoke-WebRequest..."
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri $Uri -OutFile $Destination
      if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) {
        return
      }
      throw 'The download completed without producing a non-empty file.'
    } catch {
      $LastError = $_
      Write-Warning "Invoke-WebRequest attempt $Attempt failed: $($_.Exception.Message)"
      if ($Attempt -lt $MaxAttempts) {
        Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $Attempt)))
      }
    }
  }

  $Curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
  if ($null -ne $Curl) {
    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
      Remove-Item -Force -ErrorAction SilentlyContinue $Destination
      Write-Host "Download attempt $Attempt/$MaxAttempts with curl.exe..."
      & $Curl.Source --fail --location --connect-timeout 30 --max-time 300 --output $Destination $Uri
      $CurlExitCode = $LASTEXITCODE
      if ($CurlExitCode -eq 0 -and (Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) {
        return
      }

      $LastError = "curl.exe exited with code $CurlExitCode"
      Write-Warning $LastError
      if ($Attempt -lt $MaxAttempts) {
        Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $Attempt)))
      }
    }
  }

  Remove-Item -Force -ErrorAction SilentlyContinue $Destination
  throw "Failed to download $Uri after retries. Last error: $LastError"
}

try {
  if (-not (Test-Path $RunnerDir)) {
    $FlutterMode = $Configuration.ToLowerInvariant()
    throw "Windows $Configuration build not found: $RunnerDir. Run flutter build windows --$FlutterMode first."
  }

  New-Item -ItemType Directory -Force -Path $TempRoot, $ExtractDir | Out-Null

  $ExistingArchivePath = Join-Path $TargetDir $ArchiveName
  $ReusedExistingArchive = $false
  if (Test-Path $ExistingArchivePath) {
    $ExistingSha256 = (Get-FileHash -Algorithm SHA256 -Path $ExistingArchivePath).Hash.ToLowerInvariant()
    if ($ExistingSha256 -eq $ExpectedSha256) {
      Write-Host "Reusing already verified pinned Xray Core v$Version archive..."
      Copy-Item -Force $ExistingArchivePath $ArchivePath
      $ReusedExistingArchive = $true
    } else {
      Write-Warning 'Existing bundled Xray archive failed SHA-256 verification and will not be reused.'
    }
  }

  if (-not $ReusedExistingArchive) {
    Write-Host "Downloading pinned Xray Core v$Version..."
    Download-FileWithRetry -Uri $DownloadUrl -Destination $ArchivePath
  }

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
  Set-Content -NoNewline -Encoding ASCII -Path (Join-Path $TargetDir $HashFileName) -Value $ExpectedSha256

  Write-Host "Bundled verified Xray Core v$Version into $TargetDir"
} finally {
  if (Test-Path $TempRoot) {
    Remove-Item -Recurse -Force $TempRoot
  }
}
