# OrexRay

OrexRay is a Flutter Xray client for Windows and Android with the Orex visual language and squirrel mascot.

Current milestone: **0.6.0**.

## What works

### Windows

- **System Proxy** — default, no admin rights; applies OrexRay's local HTTP proxy to Windows for the current user.
- **VPN / TUN** — full-device routing; requires elevation.
- **Local Proxy** — configurable SOCKS5 and HTTP listeners.

### Android

- **VPN** — foreground `VpnService` + Xray external TUN file descriptor.
- **Local Proxy** — Xray without TUN.
- background tunnel independent from the Flutter activity;
- live traffic speed notification and Disconnect action;
- configurable statistics interval;
- per-app VPN routing: all, exclude selected, only selected.

## Profiles and routing

- import `vless://`;
- edit existing profiles;
- automatic and manual TCP latency checks;
- create balancers and select them like profiles;
- strategies: random, round robin, least ping;
- persistent DNS, private-network bypass, sniffing and Xray log-level settings.

Supported profile combinations currently include:

- security: none, TLS, REALITY;
- transport: RAW/TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade.

## GeoData

The GeoData page can inspect and update `geoip.dat` and `geosite.dat` in the active Xray asset directory. Downloads are verified with SHA-256 before replacement. Automatic checks can run every 12, 24, 72 or 168 hours.

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

See `UPDATE_0.6.0.md` for the complete milestone notes.
