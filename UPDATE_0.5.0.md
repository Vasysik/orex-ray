# OrexRay 0.5.0

## Android crash fix

The previous Android integration called:

```kotlin
Libv2ray.initCoreEnv(envDir.absolutePath, "orexray")
```

The second argument is the XUDP base key, not an application name. Current Xray expects it to be URL-safe Base64 that decodes to exactly 32 bytes. OrexRay now derives a stable 32-byte value from Android ID and encodes it as URL-safe Base64 without padding, matching the approach used by v2rayNG.

## Startup experience

OrexRay now starts immediately into an Orex-style bootstrap screen while preferences and profiles load:

- mascot/logo;
- version/build label;
- warm ambient background;
- copper progress indicator;
- startup error screen if initialization fails.

## Navigation

Desktop navigation now has dedicated pages:

1. Home
2. Profiles
3. Connection
4. Network
5. Interface
6. About

The extra mascot icon above the navigation rail was removed.

Mobile keeps a compact bottom navigation with Home, Profiles, Connection and More.

## New persistent settings

### Connection

- mode;
- SOCKS5 port;
- HTTP port;
- LAN binding;
- VPN MTU.

### Network

- automatic, Cloudflare, Google or custom DNS;
- direct access to private networks;
- protocol sniffing;
- Xray log level.

These settings are used when generating the next Xray configuration. Android VPN also receives MTU and DNS values through the native channel.
