# OrexRay 0.6.0

## Android background service

The Android Xray core remains inside a foreground `VpnService`, independent from the Flutter activity. Closing or removing the UI task does not stop the active tunnel.

New background settings:

- statistics interval: 1, 2, 5 or 10 seconds;
- live download/upload speed in the ongoing notification;
- optional service restoration with the last start intent when Android recreates the service.

The notification is silent, ongoing and includes a Disconnect action. The native service does not hold a wake lock.

## Live traffic statistics

Android reads Xray outbound counters for the active profile or every member outbound of an active balancer. It reports:

- total download;
- total upload;
- current download bytes per second;
- current upload bytes per second;
- connection duration.

The same live speed values are shown on the home screen and in the Android notification.

## Ping

Profiles are now probed with an asynchronous TCP-connect latency check:

- initial refresh after startup;
- automatic refresh every minute while the Flutter process is active;
- manual refresh for one profile;
- manual refresh for all profiles.

Latency is persisted with the profile and shown on profile cards, the active target and the home statistics panel.

## GeoData

A new GeoData page shows the local state of:

- `geoip.dat`;
- `geosite.dat`.

Features:

- file size and modification time;
- exact asset directory;
- manual update;
- automatic checks every 12 hours, 1 day, 3 days or 7 days;
- download progress;
- SHA-256 verification before atomic replacement.

Updated files are picked up on the next Xray start.

## Android per-app VPN routing

A new Apps page supports three modes:

- all applications;
- exclude selected applications;
- only selected applications.

The app list is loaded from launchable Android packages. Settings are applied when the Android VPN interface is created.

## Balancers

Profiles can now be grouped into a balancer and selected from the same profile list as a normal server.

Strategies:

- random;
- round robin;
- least ping.

Least-ping balancers add an Xray observatory with configurable probe URL and interval.

## Profile editing

Existing VLESS profiles can now be edited directly in OrexRay:

- name;
- address and port;
- UUID;
- flow;
- security;
- transport;
- SNI/server name;
- fingerprint;
- REALITY public key/password and short ID;
- path/host;
- gRPC service name;
- TLS allow-insecure.

Changing a profile clears its old latency and triggers a new probe.

## Navigation

Desktop sidebar:

1. Home
2. Profiles
3. Connection
4. Apps
5. Network
6. GeoData
7. Background
8. Interface
9. About

Mobile keeps the compact bottom bar and exposes the extra sections through More.

## Startup rendering

The mascot asset now requests a decode size matched to its on-screen size instead of decoding the full 1254×1254 source for every small widget. This reduces startup/UI work seen in the Android debug logs without changing the source artwork.
