import 'dart:typed_data';
import 'dart:ui' as ui;

/// Limit headers before invoking the platform decoder; retain a small PNG only.
Future<Uint8List> normalizeCover(Uint8List bytes) async {
  if (bytes.length > 4 * 1024 * 1024 || bytes.length < 24) {
    throw const FormatException('cover_budget');
  }
  var width = 0, height = 0;
  if (bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71) {
    if (bytes[12] != 73 ||
        bytes[13] != 72 ||
        bytes[14] != 68 ||
        bytes[15] != 82) {
      throw const FormatException('cover_png');
    }
    final data = ByteData.sublistView(bytes);
    width = data.getUint32(16);
    height = data.getUint32(20);
  } else if (bytes[0] == 255 && bytes[1] == 216) {
    var i = 2;
    while (i + 4 < bytes.length) {
      if (bytes[i++] != 255) throw const FormatException('cover_jpeg');
      while (i < bytes.length && bytes[i] == 255) {
        i++;
      }
      if (i >= bytes.length) break;
      final marker = bytes[i++];
      if (marker == 217 || marker == 218) break;
      final size = (bytes[i] << 8) | bytes[i + 1];
      if (size < 2 || i + size > bytes.length) {
        throw const FormatException('cover_jpeg');
      }
      if (const [192, 193, 194].contains(marker) && size >= 8) {
        height = (bytes[i + 3] << 8) | bytes[i + 4];
        width = (bytes[i + 5] << 8) | bytes[i + 6];
        break;
      }
      i += size;
    }
  }
  if (width <= 0 ||
      height <= 0 ||
      width > 4096 ||
      height > 4096 ||
      width * height > 8 * 1024 * 1024) {
    throw const FormatException('cover_dimensions');
  }
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width > 384 ? 384 : width,
    allowUpscaling: false,
  );
  try {
    if (codec.frameCount != 1) throw const FormatException('cover_animation');
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null || png.lengthInBytes > 4 * 1024 * 1024) {
        throw const FormatException('cover_output');
      }
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
