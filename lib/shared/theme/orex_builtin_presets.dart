import 'dart:convert';

import 'package:flutter/services.dart';

import 'simple_theme_profile.dart';

/// Presentation metadata and thumbnail from the same portable preset JSON.
class OrexBuiltinPresetPreview {
  const OrexBuiltinPresetPreview({
    required this.name,
    required this.description,
    required this.accent,
    required this.mascotBytes,
  });

  final String name;
  final String description;
  final Color accent;
  final Uint8List? mascotBytes;
}

/// Only IDs live in Dart. Preset titles, descriptions and colors live in JSON.
/// Images and JSON aren't loaded until the Interface screen is opened.
class OrexBuiltinPreset {
  const OrexBuiltinPreset(this.id);
  final String id;

  static final Map<String, Future<OrexBuiltinPresetPreview?>> _cachedPreviews = {};

  Future<OrexBuiltinPresetPreview?> loadPreview() =>
      _cachedPreviews.putIfAbsent(id, () async {
        try {
          final data = jsonDecode(await rootBundle.loadString(assetPath));
          if (data is! Map || data['format'] != 'orexray-theme' ||
              data['version'] != 1) {
            return null;
          }
          final name = data['name'];
          final description = data['description'];
          if (name is! String || name.trim().isEmpty ||
              description is! String || description.trim().isEmpty) {
            return null;
          }
          final accent = SimpleThemeProfile.parseColors(data['colors'])['accent'];
          if (accent == null) {
            return null;
          }

          Uint8List? mascotBytes;
          final dataUri = data['mascot'];
          if (dataUri is String) {
            const marker = ';base64,';
            final at = dataUri.indexOf(marker);
            if (dataUri.startsWith('data:image/') && at >= 0) {
              mascotBytes = base64Decode(dataUri.substring(at + marker.length));
            }
          }
          return OrexBuiltinPresetPreview(
            name: name.trim(),
            description: description.trim(),
            accent: accent,
            mascotBytes: mascotBytes,
          );
        } on Object {
          return null;
        }
      });

  String get storageId => 'preset_$id';
  String get assetPath => 'assets/themes/presets/$id.json';

  static const values = <OrexBuiltinPreset>[
    OrexBuiltinPreset('noir'),
    OrexBuiltinPreset('cabbage'),
    OrexBuiltinPreset('hardcore'),
    OrexBuiltinPreset('hacker'),
  ];
}
