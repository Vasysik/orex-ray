# OrexRay 0.6.1+9 hotfix

- Fixed custom GeoData import on current Dart/Flutter by replacing incompatible `Stream<Uint8List>.pipe(IOSink)` with explicit streaming copy.
- Removed redundant `dart:typed_data` import.
- Fixed `TunnelController` test race by synchronizing from `engine.current` after awaited start/stop operations.
- Semantic version stays at 0.6.1; only build number changes from 8 to 9.
