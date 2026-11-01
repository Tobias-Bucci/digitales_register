// Regenerate the iOS app icons from the existing app artwork; no app build.
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

  // The launch images are generated with the launch animation by
  // `flutter test tool/launch_assets/generate_test.dart`.
  stdout.writeln('Regenerated iOS icons. No build started.');
}
