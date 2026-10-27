import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart' as zx;

/// QR decoding never imports a profile on its own. The existing import dialog
/// always shows the decoded link and requires explicit confirmation.
class QrLinkImport {
  QrLinkImport._();

  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxPixels = 16 * 1024 * 1024;
  static const maxLinkLength = 64 * 1024;

  static bool isSupportedLink(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length > maxLinkLength ||
        text.contains('\n') || text.contains('\r')) {
      return false;
    }
    final schemeEnd = text.indexOf('://');
    if (schemeEnd <= 0) {
      return false;
    }
    return const {
      'vless', 'vmess', 'trojan', 'ss', 'socks', 'socks5', 'http', 'https',
    }.contains(text.substring(0, schemeEnd).toLowerCase());
  }

  /// Returns null only when the user cancels file selection.
  static Future<String?> pickFromImage() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'QR-код', extensions: ['png', 'jpg', 'jpeg']),
    ]);
    if (file == null) {
      return null;
    }
    if (await file.length() > maxImageBytes) {
      throw const FormatException('Изображение QR больше 10 МБ');
    }
    final bytes = await file.readAsBytes();
    return compute(decodeImage, bytes);
  }

  /// CPU-heavy image parsing takes place outside the Flutter UI isolate.
  @visibleForTesting
  static String decodeImage(Uint8List bytes) {
    if (bytes.length > maxImageBytes) {
      throw const FormatException('Изображение QR больше 10 МБ');
    }
    // The image package may throw a RangeError on malformed or truncated
    // input instead of returning null. Normalize decoder errors for the UI.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object {
      throw const FormatException('Не удалось прочитать изображение');
    }
    if (decoded == null) {
      throw const FormatException('Не удалось прочитать изображение');
    }
    if (decoded.width * decoded.height > maxPixels) {
      throw const FormatException('Изображение QR слишком большое');
    }
    final rgba = decoded.convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    final source = zx.RGBLuminanceSource(
      decoded.width, decoded.height, rgba.buffer.asInt32List(),
    );
    try {
      final result = zx.QRCodeReader().decode(
        zx.BinaryBitmap(zx.HybridBinarizer(source)),
      );
      final link = result.text.trim();
      if (!isSupportedLink(link)) {
        throw const FormatException('QR не содержит поддерживаемую ссылку профиля');
      }
      return link;
    } on zx.ReaderException {
      throw const FormatException('QR-код на изображении не найден');
    }
  }
}

/// Android camera scanner; desktop uses [QrLinkImport.pickFromImage].
/// Its camera controller is stopped on success and disposed on every exit.
class QrCameraDialog extends StatefulWidget {
  const QrCameraDialog({super.key});

  @override
  State<QrCameraDialog> createState() => _QrCameraDialogState();
}

class _QrCameraDialogState extends State<QrCameraDialog> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finished = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finished || !mounted) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final link = barcode.rawValue?.trim();
      if (link == null || link.isEmpty) {
        continue;
      }
      if (!QrLinkImport.isSupportedLink(link)) {
        if (_error == null) {
          setState(() => _error = 'Нужен QR со ссылкой VLESS, VMess, Trojan или другого прокси');
        }
        continue;
      }
      _finished = true; // Do not process repeated camera frames.
      unawaited(_complete(link));
      return;
    }
  }

  Future<void> _complete(String link) async {
    try {
      await _camera.stop();
    } on Object {
      // The platform can close the camera while a result is being processed.
    }
    if (mounted) {
      Navigator.of(context).pop(link);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(child: Text('Сканировать QR',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                  IconButton(
                    tooltip: 'Закрыть сканер',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: MobileScanner(
                      controller: _camera,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Камера недоступна: ${error.errorCode.name}. '
                              'Проверь разрешение на камеру.'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(_error ?? 'Наведите камеру на QR-код подключения.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}
