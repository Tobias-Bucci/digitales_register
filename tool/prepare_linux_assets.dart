import 'dart:io';

import 'package:image/image.dart' as img;

// Resize the existing app logo, preserving transparency and other platforms.
void main() {
  final source = img.decodePng(File('assets/index.png').readAsBytesSync());
  if (source == null) throw StateError('Cannot decode assets/index.png');
  for (final size in [32, 48, 64, 128, 256, 512]) {
    final icon = img.copyResize(source,
        width: size, height: size, interpolation: img.Interpolation.average);
    final bytes = img.encodePng(icon);
    final file =
        File('linux/icons/${size}x$size/apps/io.github.tobias_bucci.digitales_register.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    if (size == 512) File('linux/icon.png').writeAsBytesSync(bytes);
  }
}
