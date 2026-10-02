// Regenerate native iOS assets from the existing app artwork; no app build.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const root = 'ios/Runner/Assets.xcassets';
  final icon = img.decodePng(File('assets/index.png').readAsBytesSync())!;
  final opaque = img.Image(width: icon.width, height: icon.height);
  img.fill(opaque, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(opaque, icon);
  final catalog = jsonDecode(
    File('$root/AppIcon.appiconset/Contents.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final entry in catalog['images'] as List<dynamic>) {
    final size = double.parse((entry['size'] as String).split('x').first);
    final scale = double.parse((entry['scale'] as String).replaceAll('x', ''));
    final pixels = (size * scale).round();
    final resized = img.copyResize(opaque,
        width: pixels,
        height: pixels,
        interpolation: img.Interpolation.average);
    File('$root/AppIcon.appiconset/${entry['filename']}')
        .writeAsBytesSync(img.encodePng(resized));
  }

  final logo =
      img.decodePng(File('assets/4.0x/transparent.png').readAsBytesSync())!;
  for (var scale = 1; scale <= 3; scale++) {
    final suffix = scale == 1 ? '' : '@${scale}x';
    final resized = img.copyResize(logo,
        width: 144 * scale,
        height: (144 * scale * logo.height / logo.width).round(),
        interpolation: img.Interpolation.average);
    for (final appearance in ['', 'Dark']) {
      File('$root/LaunchImage.imageset/LaunchImage$appearance$suffix.png')
          .writeAsBytesSync(img.encodePng(resized));
    }
  }
  stdout.writeln(
      'Regenerated iOS icons and light/dark launch logos. No build started.');
}
