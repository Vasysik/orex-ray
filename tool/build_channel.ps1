param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('debug', 'release')]
  [string]$Mode,

  [ValidateSet('all', 'android', 'windows')]
  [string]$Platform = 'all',

  [switch]$SkipChecks,
  [switch]$ReuseFlutterBuilds
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($ArgumentList -join ' ')"
  }
}

function Get-OrexRayVersion {
  $VersionMatch = [regex]::Match(
    (Get-Content (Join-Path $RepoRoot 'pubspec.yaml') -Raw),
    '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
  )
  if (-not $VersionMatch.Success) {
    throw 'pubspec.yaml must contain version: X.Y.Z+N'
  }

  return [pscustomobject]@{
    VersionName = '{0}.{1}.{2}' -f `
      $VersionMatch.Groups[1].Value, `
      $VersionMatch.Groups[2].Value, `
      $VersionMatch.Groups[3].Value
    BuildNumber = $VersionMatch.Groups[4].Value
  }
}

function Remove-ArtifactPattern {
  param([Parameter(Mandatory = $true)][string]$Pattern)
  Get-ChildItem -Path $OutputDir -Filter $Pattern -File -ErrorAction SilentlyContinue |
    Remove-Item -Force
}

function Publish-Artifact {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (-not (Test-Path $Source)) {
    throw "Build artifact was not found: $Source"
  }

  $Destination = Join-Path $OutputDir $Name
  Copy-Item -Force $Source $Destination
  Write-Host "  $Name"
  return $Destination
}

Push-Location $RepoRoot
try {
  $Version = Get-OrexRayVersion
  $Release = "$($Version.VersionName)+$($Version.BuildNumber)"
  $OutputDir = Join-Path $RepoRoot "dist\$Mode\$Release"
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

  Write-Host '========================================'
  Write-Host "OrexRay $Mode build"
  Write-Host "Version:  $Release"
  Write-Host "Platform: $Platform"
  Write-Host "Output:   $OutputDir"
  Write-Host '========================================'

  if (-not $SkipChecks) {
    Write-Host ''
    Write-Host '=== Quality gate ==='
    Invoke-NativeCommand -FilePath 'flutter' -ArgumentList @('pub', 'get')
    Invoke-NativeCommand -FilePath 'flutter' -ArgumentList @('analyze', '--no-pub')
    Invoke-NativeCommand -FilePath 'flutter' -ArgumentList @('test', '--no-pub')
  }

  if ($Platform -in @('all', 'android')) {
    Write-Host ''
    Write-Host "=== Android $Mode ==="
    if ($Mode -eq 'debug') {
      Remove-ArtifactPattern -Pattern "OrexRay-$Release-debug*.apk"
    } else {
      Remove-ArtifactPattern -Pattern "OrexRay-$Release-*.apk"
    }

    if (-not $ReuseFlutterBuilds) {
      if ($Mode -eq 'debug') {
        Invoke-NativeCommand -FilePath 'flutter' -ArgumentList @(
          'build', 'apk', '--debug', '--no-pub'
        )
      } else {
        Invoke-NativeCommand -FilePath 'flutter' -ArgumentList @(
          'build', 'apk', '--release', '--split-per-abi', '--no-pub'
        )
      }
    }

    if ($Mode -eq 'debug') {
      $DebugApk = Join-Path $RepoRoot 'build\app\outputs\flutter-apk\app-debug.apk'
      Publish-Artifact `
        -Source $DebugApk `
        -Name "OrexRay-$Release-debug.apk" | Out-Null
    } else {
      $AndroidArtifacts = @(
        @{ Source = 'app-arm64-v8a-release.apk'; Abi = 'arm64-v8a' },
        @{ Source = 'app-armeabi-v7a-release.apk'; Abi = 'armeabi-v7a' },
        @{ Source = 'app-x86_64-release.apk'; Abi = 'x86_64' }
      )
      foreach ($Artifact in $AndroidArtifacts) {
        $Source = Join-Path $RepoRoot "build\app\outputs\flutter-apk\$($Artifact.Source)"
        Publish-Artifact `
          -Source $Source `
          -Name "OrexRay-$Release-$($Artifact.Abi).apk" | Out-Null
      }
    }
  }

  if ($Platform -in @('all', 'windows')) {
    Write-Host ''
    Write-Host "=== Windows $Mode ==="
    if ($Mode -eq 'debug') {
      Remove-ArtifactPattern -Pattern "OrexRay-$Release-debug-x64*"
    } else {
      Remove-ArtifactPattern -Pattern "OrexRay-$Release-*-setup.exe"
    }

    $Configuration = if ($Mode -eq 'debug') { 'Debug' } else { 'Release' }
    $WindowsRunnerDir = Join-Path $RepoRoot "build\windows\x64\runner\$Configuration"

    if (-not $ReuseFlutterBuilds) {
      Invoke-NativeCommand -FilePath 'flutter' -ArgumentList @(
        'build', 'windows', "--$Mode", '--no-pub'
      )
    } elseif (-not (Test-Path $WindowsRunnerDir)) {
      throw "Reusable Windows build was not found: $WindowsRunnerDir"
    }

    & (Join-Path $RepoRoot 'windows\installer\prepare_xray_core.ps1') `
      -Configuration $Configuration

    if ($Mode -eq 'debug') {
      if (-not (Test-Path (Join-Path $WindowsRunnerDir 'orex_ray.exe'))) {
        throw "Windows debug executable was not found in $WindowsRunnerDir"
      }
      $ZipName = "OrexRay-$Release-debug-x64.zip"
      $ZipPath = Join-Path $OutputDir $ZipName
      Remove-Item -Force -ErrorAction SilentlyContinue $ZipPath
      Compress-Archive -Path (Join-Path $WindowsRunnerDir '*') -DestinationPath $ZipPath -Force
      Write-Host "  $ZipName"
    } else {
      $Iscc = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
      ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
      if (-not $Iscc) {
        throw 'Inno Setup 6 not found. Install it with: winget install --id JRSoftware.InnoSetup -e'
      }

      $VersionInfo = "$($Version.VersionName).$($Version.BuildNumber)"
      Invoke-NativeCommand -FilePath $Iscc -ArgumentList @(
        "/DMyAppVersion=$Release",
        "/DMyAppVersionInfo=$VersionInfo",
        'windows\installer\orexray.iss'
      )

      $Installer = Join-Path $RepoRoot "build\windows\x64\installer\OrexRay-Setup-$Release.exe"
      Publish-Artifact `
        -Source $Installer `
        -Name "OrexRay-$Release-x64-setup.exe" | Out-Null
    }
  }

  Write-Host ''
  Write-Host '=== SHA-256 ==='
  $HashFiles = @(
    Get-ChildItem -Path $OutputDir -File |
      Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
      Sort-Object Name
  )
  $HashLines = foreach ($File in $HashFiles) {
    $Hash = (Get-FileHash -Algorithm SHA256 $File.FullName).Hash.ToLowerInvariant()
    "$Hash  $($File.Name)"
  }
  Set-Content -Encoding ascii -Path (Join-Path $OutputDir 'SHA256SUMS.txt') -Value $HashLines

  Write-Host ''
  Write-Host '========================================'
  Write-Host 'Build completed successfully'
  Write-Host "Artifacts: $OutputDir"
  foreach ($File in $HashFiles) {
    Write-Host "  $($File.Name)"
  }
  Write-Host '  SHA256SUMS.txt'
  Write-Host '========================================'
} finally {
  Pop-Location
}
