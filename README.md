# OrexRay

OrexRay is a Flutter Xray client for Windows and Android with the Orex visual language and squirrel mascot.

Current milestone: **0.6.1**.

## What works

### Windows

- **System Proxy** — default, no admin rights; applies OrexRay's local HTTP proxy to Windows for the current user.
- **VPN / TUN** — full-device routing; requires elevation.
- **Local Proxy** — configurable SOCKS5 and HTTP listeners.
- VPN mode can keep the local SOCKS5/HTTP listeners active in parallel.

### Android

- **VPN** — foreground `VpnService` + Xray external TUN file descriptor.
- **Local Proxy** — Xray without TUN.
- VPN mode can expose the local SOCKS5/HTTP listeners at the same time.
- background tunnel independent from the Flutter activity;
- live traffic speed and ping notification with Disconnect action;
- configurable statistics interval;
- per-app VPN routing: all, exclude selected, only selected;
- app icons plus optional system-app visibility.

## Profiles and routing

- import `vless://`;
- create and edit profiles inside OrexRay;
- automatic and manual TCP latency checks;
- tap ping on Home to refresh it;
- quick profile/balancer switch from Home;
- create and edit balancers and select them like profiles;
- strategies: random, round robin, least ping;
- persistent DNS, private-network bypass, sniffing and Xray log-level settings.

Supported profile combinations currently include:

- security: none, TLS, REALITY;
- transport: RAW/TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade.

## GeoData

The GeoData page can inspect, update and import `geoip.dat` and `geosite.dat` in the active Xray asset directory. GeoData can be used by real `geoip:` / `geosite:` route rules for block, direct and proxy decisions. Downloads are verified with SHA-256 before replacement.

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

See `UPDATE_0.6.1.md` for the complete milestone notes.
