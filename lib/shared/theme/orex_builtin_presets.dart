import 'dart:convert';

import 'package:flutter/services.dart';

/// Metadata only. Preset JSON (including mascot bytes) is loaded on demand.
class OrexBuiltinPreset {
  const OrexBuiltinPreset(this.id, this.title, this.subtitle, this.accent);
  final String id;
  final String title;
  final String subtitle;
  final Color accent;

  // No work on app bootstrap. Thumbnail image loaded only if Appearance opens.
  static final Map<String, Future<Uint8List?>> _cachedThumbnails = {};
  Future<Uint8List?> loadMascotPreview() =>
      _cachedThumbnails.putIfAbsent(id, () async {
        try {
          final data = jsonDecode(await rootBundle.loadString(assetPath));
          final dataUri = data['mascot'];
          if (dataUri is! String) return null;
          final marker = ';base64,';
          final at = dataUri.indexOf(marker);
          if (!dataUri.startsWith('data:image/') || at < 0) return null;
          return base64Decode(dataUri.substring(at + marker.length));
        } on Object {
          return null;
        }
      });

  String get storageId => 'preset_$id';
  String get assetPath => 'assets/themes/presets/$id.json';

  static const values = <OrexBuiltinPreset>[
    OrexBuiltinPreset('noir', 'Серая тема Орешка', 'Графитовые оттенки, мягкий синий акцент и серая белочка', Color(0xFF4F8FB8)),
    OrexBuiltinPreset('cabbage', 'Soft Lime', 'Мягкая салатовая тема с котом и капустой', Color(0xFFC9E279)),
    OrexBuiltinPreset('hardcore', 'Hardcore Red', 'Чёрно-красная тема с белочкой', Color(0xFFFF303A)),
    OrexBuiltinPreset('hacker', 'Hacker Green', 'Чёрно-зелёная тема с котом-хакером', Color(0xFF3BFF70)),
  ];
}
