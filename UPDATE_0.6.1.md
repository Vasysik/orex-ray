# OrexRay 0.6.1

Focused refinement release for the existing 0.6 branch. No major-version jump.

## Home and portrait layout

- Portrait layout now stretches the mode and connection panels across the available width.
- The status block sits immediately below the connection panel.
- Mobile status layout: download, upload and ping on the top row; total traffic below.
- Tap ping on the home screen to refresh the active target latency.
- Tap the active profile/balancer name to open a quick target picker.

## Android notification

- Replaced the generic filled-circle status icon with a dedicated monochrome OrexRay network/squirrel mark.
- Expanded notifications also use the full-color OrexRay launcher icon.
- Notification text can show download speed, upload speed and profile ping.
- Ping metadata is refreshed while a tunnel is running.

## VPN plus local proxy

TUN/VPN mode can now keep the local proxy listeners alive at the same time:

- SOCKS5 on the configured SOCKS port;
- HTTP on the configured HTTP port;
- optional LAN binding through the existing setting.

This is enabled by default and can be disabled on the Connection page.

## DNS

Added `System DNS` as the default preset. In this mode Android does not call
`VpnService.Builder.addDnsServer`, so the platform keeps the current network's DNS configuration.
Explicit Cloudflare, Google and custom presets remain available.

## GeoData

GeoData is now connected to Xray routing instead of only being downloaded:

- enable/disable GeoData routing;
- `geoip:` and `geosite:` rules for block, direct and proxy routes;
- first-match routing order;
- import custom `geoip.dat` or `geosite.dat` files through the platform file picker;
- atomic replacement with backup restoration on failure.

## Android app routing

- App list is loaded on a worker thread.
- Real application icons are returned to Flutter.
- System-app metadata and launcher metadata are included.
- UI can hide/show system apps and filter to selected apps.
- Full installed-app visibility is requested because per-app VPN routing is a core feature.

## Profiles and balancers

- Create a VLESS profile manually inside OrexRay.
- Edit existing profiles.
- Create and edit balancers inside OrexRay.
- Import, Create profile, Create balancer and Check ping use a consistent outlined toolbar style.

## Compatibility cleanup

- Replaced deprecated `DropdownButtonFormField.value` with `initialValue`.
- Flutter minimum is now 3.33 because the app already relies on the current RadioGroup/Form APIs.
