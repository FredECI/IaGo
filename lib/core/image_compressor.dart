import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Tamanho máximo da imagem compactada: cabe com folga num documento do
/// Firestore (limite de 1 MiB) e carrega rápido em celular barato.
const int maxImageBytes = 300 * 1024;

/// Compacta a imagem para JPEG com no máximo [maxBytes], reduzindo qualidade
/// e, se preciso, o tamanho. Fundo transparente (comum em prints) vira branco.
Uint8List compressImage(
  Uint8List input, {
  int maxBytes = maxImageBytes,
  int maxSide = 1600,
}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('Formato de imagem não suportado');
  }
  var base = decoded;
  if (base.hasAlpha) {
    final background = img.Image(width: base.width, height: base.height);
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    base = img.compositeImage(background, base);
  }

  var side = maxSide;
  while (true) {
    final resized = _fit(base, side);
    for (final quality in const [82, 70, 58, 46]) {
      final jpg = img.encodeJpg(
        resized,
        quality: quality,
        chroma: img.JpegChroma.yuv420,
      );
      if (jpg.length <= maxBytes) return jpg;
    }
    if (side <= 480) {
      return img.encodeJpg(resized, quality: 40, chroma: img.JpegChroma.yuv420);
    }
    side = (side * 0.75).round();
  }
}

img.Image _fit(img.Image image, int maxSide) {
  if (image.width <= maxSide && image.height <= maxSide) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: maxSide,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: maxSide,
          interpolation: img.Interpolation.average,
        );
}
