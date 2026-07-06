# OrexRay

OrexRay is a Flutter Xray client for Windows and Android with the Orex visual language and squirrel mascot.

Current milestone: **0.5.0**.

## What changed in 0.5.0

- Fixed the Android native crash caused by an invalid XUDP base key.
- Added a real Orex-style startup/loading screen.
- Removed the extra mascot icon from the Windows navigation rail.
- Split settings into dedicated navigation pages: Connection, Network, Interface, About.
- Added persistent proxy ports, LAN binding, VPN MTU, DNS presets/custom DNS, private-network bypass, sniffing and Xray log level.
- Wired the settings into Windows and Android Xray configuration generation.
- Android VPN now receives MTU and DNS settings through the native bridge.
- Android log helper now filters for OrexRay, Go/Xray and fatal runtime errors.

## Modes

### Windows

- **System Proxy** — default, no admin rights; applies OrexRay's local HTTP proxy to Windows for the current user.
- **VPN / TUN** — full-device routing; requires elevation.
- **Local Proxy** — configurable SOCKS5 and HTTP listeners.

### Android

- **VPN** — `VpnService` + Xray external TUN file descriptor.
- **Local Proxy** — Xray with no TUN file descriptor.

## Supported profiles

The current importer supports `vless://` with:

- security: none, TLS, REALITY;
- transport: RAW/TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade.

## Run

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
```

Windows:

```powershell
flutter run -d windows
```

Android:

```powershell
flutter run -d <device-id>
```

Filtered Android logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\log_android.ps1
```

See `UPDATE_0.5.0.md` for details.
