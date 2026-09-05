class EgressIdentity {
  const EgressIdentity({
    required this.countryCode,
    required this.warp,
    required this.checkedAt,
  });

  final String countryCode;
  final bool warp;
  final DateTime checkedAt;

  Map<String, Object?> toJson() => {
        'countryCode': countryCode,
        'warp': warp,
        'checkedAt': checkedAt.toIso8601String(),
      };

  static EgressIdentity? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, Object?>.from(value);
    final code = (json['countryCode'] as String?)?.trim().toUpperCase() ?? '';
    final checkedAt = DateTime.tryParse(json['checkedAt'] as String? ?? '');
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) || checkedAt == null) return null;
    return EgressIdentity(
      countryCode: code,
      warp: json['warp'] == true,
      checkedAt: checkedAt,
    );
  }
}


EgressIdentity? parseCloudflareTrace(String body, {DateTime? checkedAt}) {
  final values = <String, String>{};
  for (final line in body.split('\n')) {
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator).trim()] =
        line.substring(separator + 1).trim();
  }
  final country = values['loc']?.toUpperCase() ?? '';
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) return null;
  final warpValue = values['warp']?.toLowerCase();
  return EgressIdentity(
    countryCode: country,
    warp: warpValue == 'on' || warpValue == 'plus',
    checkedAt: checkedAt ?? DateTime.now(),
  );
}
