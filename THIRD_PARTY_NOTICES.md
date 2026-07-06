# Third-party notices

OrexRay использует внешние компоненты. Этот файл — техническая памятка, а не юридическая консультация.

## Xray-core

- Project: XTLS/Xray-core
- License: Mozilla Public License 2.0 (MPL-2.0)
- Windows: загружается runtime-менеджером OrexRay.
- Android: входит внутрь AndroidLibXrayLite build.

Project source: https://github.com/XTLS/Xray-core

## AndroidLibXrayLite

- Project: 2dust/AndroidLibXrayLite
- Pinned release in OrexRay 0.3.0: `v26.6.27`
- License: GNU Lesser General Public License v3.0 (LGPL-3.0)
- Build artifact: `libv2ray.aar`
- SHA-256 pin: `7846eb7f663d1d8ae931034faa7a56cccc82d618c2d029198e6e91a77fd8de1e`

Project source: https://github.com/2dust/AndroidLibXrayLite

## Перед распространением

Перед публикацией APK/EXE проверьте требования всех лицензий, приложите необходимые notices/license texts и обеспечьте требуемый лицензиями доступ к соответствующему исходному коду и/или relinkable form там, где это применимо.

## GeoData update source

OrexRay can download `geoip.dat` and `geosite.dat` plus their published SHA-256 checksum files from the `Loyalsoldier/v2ray-rules-dat` release branch. These data files are downloaded at runtime and are not authored by OrexRay.

Project source: https://github.com/Loyalsoldier/v2ray-rules-dat

## Flutter file_selector

- Package: `file_selector`
- Publisher: flutter.dev
- License: BSD-3-Clause
- Purpose in OrexRay: user-selected custom `geoip.dat` and `geosite.dat` imports on Android and Windows.

Project source: https://github.com/flutter/packages/tree/main/packages/file_selector
