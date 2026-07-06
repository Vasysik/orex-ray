param(
    [string]$Alias = "orexray",
    [string]$KeystoreName = "orexray-release.jks",
    [switch]$WriteKeyProperties
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $projectRoot "android"
$secretsDir = Join-Path $androidDir "secrets"
$keystorePath = Join-Path $secretsDir $KeystoreName
$keyPropertiesPath = Join-Path $androidDir "key.properties"

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw "keytool не найден. Установи JDK или добавь его bin в PATH."
}

New-Item -ItemType Directory -Force $secretsDir | Out-Null
if (Test-Path $keystorePath) {
    throw "Keystore уже существует: $keystorePath`nНе перезаписывай релизный ключ."
}

Write-Host "Создаём OrexRay release keystore:" -ForegroundColor Cyan
Write-Host "  $keystorePath"
Write-Host "Пароли вводятся интерактивно самим keytool и не попадают в командную строку."

& keytool -genkeypair -v `
    -keystore $keystorePath `
    -storetype JKS `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -alias $Alias
if ($LASTEXITCODE -ne 0) {
    throw "keytool завершился с кодом $LASTEXITCODE"
}

Write-Host "`nKeystore создан." -ForegroundColor Green
Write-Host "Сделай две офлайн-копии keystore и сохрани пароли отдельно." -ForegroundColor Yellow

if ($WriteKeyProperties) {
    if (Test-Path $keyPropertiesPath) {
        throw "android/key.properties уже существует. Удали его вручную, если хочешь пересоздать."
    }

    function ConvertFrom-SecureStringPlain {
        param([Security.SecureString]$Value)
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }

    $storePassword = Read-Host "Повтори store password для android/key.properties" -AsSecureString
    $keyPassword = Read-Host "Повтори key password для android/key.properties" -AsSecureString
    $storePlain = ConvertFrom-SecureStringPlain -Value $storePassword
    $keyPlain = ConvertFrom-SecureStringPlain -Value $keyPassword
    try {
        @"
storeFile=secrets/$KeystoreName
storePassword=$storePlain
keyAlias=$Alias
keyPassword=$keyPlain
"@ | Set-Content -Path $keyPropertiesPath -Encoding ASCII
        Write-Host "Создан $keyPropertiesPath (он уже в .gitignore)." -ForegroundColor Green
    }
    finally {
        $storePlain = $null
        $keyPlain = $null
    }
}
else {
    Write-Host "`nДальше скопируй android/key.properties.example в android/key.properties" -ForegroundColor Cyan
    Write-Host "и впиши реальные пароли. Или повтори команду с -WriteKeyProperties."
}
