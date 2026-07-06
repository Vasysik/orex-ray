# OrexRay 0.4.0 — connection modes

## What changed

OrexRay no longer assumes that every user wants a full TUN tunnel.

### Windows

- **System Proxy** — default. Xray listens on localhost and OrexRay applies the HTTP proxy to the current Windows user. No administrator rights required.
- **VPN / TUN** — full-device routing through the Xray TUN adapter. Administrator rights are required.
- **Local Proxy** — Xray only exposes `SOCKS5 127.0.0.1:20808` and `HTTP 127.0.0.1:20809`.

OrexRay stores the previous Windows proxy state before enabling System Proxy and restores it on disconnect. A recovery marker is kept so the old setting can be restored after an abnormal app exit on the next launch.

### Android

- **VPN** — Android `VpnService` creates the device VPN interface and passes its file descriptor to Xray.
- **Local Proxy** — Xray runs with no TUN file descriptor and exposes the same local SOCKS5/HTTP ports.

The foreground-service notification is now started before native Xray initialization. This avoids doing potentially slow native setup before Android's foreground-service deadline.

## Profile stability

- VLESS import dialog now owns and disposes its controller safely.
- Import errors are shown in the dialog instead of escaping into the widget tree.
- Stale or malformed saved profiles are skipped individually instead of breaking profile loading.
- Profile decoding validates required fields and port ranges.
- The VLESS parser uses a safe deterministic ID fallback.

## Branding

The approved OrexRay icon is now used:

- inside the Flutter UI;
- as Android launcher icon;
- as the Windows application icon.

The composition is: white global network behind a protective walnut shell, with the Orex squirrel inside.

## Cleaner Android diagnostics

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\log_android.ps1
```

The script shows `OrexRay` logs and fatal Android runtime errors instead of MIUI/Insets UI noise.
