param(
  [ValidateSet('all', 'android', 'windows')]
  [string]$Platform = 'all',
  [switch]$SkipChecks,
  [switch]$ReuseFlutterBuilds
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'build_channel.ps1') `
  -Mode debug `
  -Platform $Platform `
  -SkipChecks:$SkipChecks `
  -ReuseFlutterBuilds:$ReuseFlutterBuilds
