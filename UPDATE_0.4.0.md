# Update to OrexRay 0.4.0

Extract the patch over an existing OrexRay 0.3.1 project:

```powershell
Expand-Archive `
  -Path .\OrexRay-0.4.0-patch.zip `
  -DestinationPath . `
  -Force
```

Then:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
```

## Windows

Normal development launch:

```powershell
flutter run -d windows
```

Use **System Proxy** first. It needs no administrator rights.

For **VPN / TUN**, run the terminal as administrator or use:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_windows_admin.ps1
```

## Android

```powershell
flutter run -d 2e4f5b7e
```

For useful logs only:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\log_android.ps1
```

## Connection modes

Windows:

1. System Proxy (default)
2. VPN / TUN
3. Local Proxy

Android:

1. VPN (default)
2. Local Proxy

Local proxy endpoints:

- SOCKS5: `127.0.0.1:20808`
- HTTP: `127.0.0.1:20809`
