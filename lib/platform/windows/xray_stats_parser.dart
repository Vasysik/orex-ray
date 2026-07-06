import 'dart:convert';

class XrayTrafficTotals {
  const XrayTrafficTotals({
    required this.downloadBytes,
    required this.uploadBytes,
  });

  final int downloadBytes;
  final int uploadBytes;
}

XrayTrafficTotals parseXrayInboundStats(String output) {
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Xray stats response is not a JSON object.');
  }

  final stats = decoded['stat'];
  if (stats is! List) {
    return const XrayTrafficTotals(downloadBytes: 0, uploadBytes: 0);
  }

  var download = 0;
  var upload = 0;
  for (final entry in stats) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || !name.startsWith('inbound>>>')) continue;

    final value = _parseCounter(entry['value']);
    if (name.endsWith('>>>traffic>>>downlink')) {
      download += value;
    } else if (name.endsWith('>>>traffic>>>uplink')) {
      upload += value;
    }
  }

  return XrayTrafficTotals(
    downloadBytes: download,
    uploadBytes: upload,
  );
}

int _parseCounter(Object? value) {
  if (value is int) return value < 0 ? 0 : value;
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}
