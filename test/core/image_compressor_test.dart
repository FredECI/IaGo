import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/image_compressor.dart';
import 'package:image/image.dart' as img;

void main() {
  test('imagem grande e ruidosa vira JPEG de até 300 KB e até 1600 px', () {
    final random = Random(42);
    final source = img.Image(width: 2400, height: 1800);
    for (final pixel in source) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    final png = img.encodePng(source);
    expect(png.length, greaterThan(maxImageBytes));

    final compressed = compressImage(png);
    expect(compressed.length, lessThanOrEqualTo(maxImageBytes));
    final decoded = img.decodeJpg(compressed);
    expect(decoded, isNotNull);
    expect(max(decoded!.width, decoded.height), lessThanOrEqualTo(1600));
  });

  test('fundo transparente vira branco', () {
    final source = img.Image(width: 40, height: 40, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));
    final decoded = img.decodeJpg(compressImage(img.encodePng(source)))!;
    final pixel = decoded.getPixel(20, 20);
    expect(pixel.r, greaterThan(240));
    expect(pixel.g, greaterThan(240));
    expect(pixel.b, greaterThan(240));
  });

  test('bytes que não são imagem geram erro claro', () {
    expect(
      () => compressImage(img.Image(width: 1, height: 1).toUint8List()),
      throwsFormatException,
    );
  });
}
