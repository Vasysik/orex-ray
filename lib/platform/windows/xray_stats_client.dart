import 'dart:convert';

import 'package:grpc/grpc.dart';

class XrayTrafficTotals {
  const XrayTrafficTotals({
    required this.downloadBytes,
    required this.uploadBytes,
  });

  final int downloadBytes;
  final int uploadBytes;
}

class XrayStatsClient {
  XrayStatsClient({required int port})
      : _channel = ClientChannel(
          '127.0.0.1',
          port: port,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
          ),
        );

  static final ClientMethod<List<int>, List<int>> _queryStatsMethod =
      ClientMethod<List<int>, List<int>>(
    '/xray.app.stats.command.StatsService/QueryStats',
    (value) => value,
    (value) => value,
  );

  static const _trackedInboundTags = {
    'orexray-tun',
    'orexray-socks',
    'orexray-http',
  };

  final ClientChannel _channel;

  Future<XrayTrafficTotals> queryInboundTotals() async {
    final call = _channel.createCall<List<int>, List<int>>(
      _queryStatsMethod,
      Stream<List<int>>.value(
        encodeQueryStatsRequest(pattern: 'inbound>>>orexray-'),
      ),
      CallOptions(timeout: const Duration(seconds: 2)),
    );
    final response = await call.response.single;
    return parseQueryStatsResponse(response);
  }

  Future<void> close() => _channel.shutdown();

  static List<int> encodeQueryStatsRequest({required String pattern}) {
    final bytes = utf8.encode(pattern);
    return <int>[
      0x0a,
      ..._encodeVarint(bytes.length),
      ...bytes,
    ];
  }

  static XrayTrafficTotals parseQueryStatsResponse(List<int> bytes) {
    final reader = _ProtoReader(bytes);
    var download = 0;
    var upload = 0;

    while (!reader.isAtEnd) {
      final key = reader.readVarint();
      final field = key >> 3;
      final wireType = key & 0x07;
      if (field != 1 || wireType != 2) {
        reader.skip(wireType);
        continue;
      }

      final stat = _parseStat(reader.readLengthDelimited());
      if (stat == null) continue;
      final parts = stat.name.split('>>>');
      if (parts.length < 4 ||
          parts[0] != 'inbound' ||
          !_trackedInboundTags.contains(parts[1]) ||
          parts[2] != 'traffic') {
        continue;
      }
      switch (parts[3]) {
        case 'downlink':
          download += stat.value;
          break;
        case 'uplink':
          upload += stat.value;
          break;
      }
    }

    return XrayTrafficTotals(
      downloadBytes: download,
      uploadBytes: upload,
    );
  }

  static _XrayStat? _parseStat(List<int> bytes) {
    final reader = _ProtoReader(bytes);
    String? name;
    int? value;

    while (!reader.isAtEnd) {
      final key = reader.readVarint();
      final field = key >> 3;
      final wireType = key & 0x07;
      if (field == 1 && wireType == 2) {
        name = utf8.decode(reader.readLengthDelimited(), allowMalformed: false);
      } else if (field == 2 && wireType == 0) {
        value = reader.readVarint();
      } else {
        reader.skip(wireType);
      }
    }

    if (name == null || value == null || value < 0) return null;
    return _XrayStat(name: name, value: value);
  }

  static List<int> _encodeVarint(int value) {
    if (value < 0) throw ArgumentError.value(value, 'value');
    final result = <int>[];
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      result.add(byte);
    } while (remaining != 0);
    return result;
  }
}

class _XrayStat {
  const _XrayStat({required this.name, required this.value});

  final String name;
  final int value;
}

class _ProtoReader {
  _ProtoReader(this._bytes);

  final List<int> _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (shift < 70) {
      if (_offset >= _bytes.length) {
        throw const FormatException('Обрезанный protobuf varint.');
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const FormatException('Слишком длинный protobuf varint.');
  }

  List<int> readLengthDelimited() {
    final length = readVarint();
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('Обрезанное protobuf поле.');
    }
    final result = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return result;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        return;
      case 1:
        _skipBytes(8);
        return;
      case 2:
        _skipBytes(readVarint());
        return;
      case 5:
        _skipBytes(4);
        return;
      default:
        throw FormatException('Неподдерживаемый protobuf wire type: $wireType');
    }
  }

  void _skipBytes(int count) {
    if (count < 0 || _offset + count > _bytes.length) {
      throw const FormatException('Обрезанное protobuf поле.');
    }
    _offset += count;
  }
}
