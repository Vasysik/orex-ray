# OrexRay

OrexRay is a Flutter Xray client for Windows and Android with the Orex visual language and squirrel mascot.

Current milestone: **0.4.0**.

## Modes

### Windows

- **System Proxy** — default, no admin rights; applies OrexRay's local HTTP proxy to Windows for the current user.
- **VPN / TUN** — full-device routing; requires elevation.
- **Local Proxy** — SOCKS5 `127.0.0.1:20808`, HTTP `127.0.0.1:20809`.

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

See `MILESTONE_04.md` and `UPDATE_0.4.0.md` for details.
