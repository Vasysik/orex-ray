import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:orex_ray/features/profiles/qr_import.dart';
import 'package:zxing2/qrcode.dart' as zx;

void main() {
  test('QR importer accepts only single supported proxy links', () {
    expect(QrLinkImport.isSupportedLink(' vless://example '), isTrue);
    expect(QrLinkImport.isSupportedLink('VMESS://payload'), isTrue);
    expect(QrLinkImport.isSupportedLink('trojan://password@example.com'), isTrue);
    expect(QrLinkImport.isSupportedLink('https://proxy.example'), isTrue);
    expect(QrLinkImport.isSupportedLink('https://example.org\nss://other'), isFalse);
    expect(QrLinkImport.isSupportedLink('javascript:alert(1)'), isFalse);
    expect(QrLinkImport.isSupportedLink('arbitrary QR contents'), isFalse);
  });

  test('QR from PNG decodes to the same proxy link', () {
    const link = 'trojan://secret@example.com:443#OrexRay';
    final matrix = zx.Encoder.encode(link, zx.ErrorCorrectionLevel.m).matrix!;
    const scale = 6;
    const quiet = 4;
    final size = (matrix.width + quiet * 2) * scale;
    final image = img.Image(width: size, height: size, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) != 1) continue;
        final x1 = (x + quiet) * scale;
        final y1 = (y + quiet) * scale;
        img.fillRect(image, x1: x1, y1: y1,
            x2: x1 + scale - 1, y2: y1 + scale - 1,
            color: img.ColorRgba8(0, 0, 0, 255));
      }
    }
    expect(QrLinkImport.decodeImage(Uint8List.fromList(img.encodePng(image))), link);
  });

  test('invalid image data shows a format error', () {
    expect(() => QrLinkImport.decodeImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });
}
