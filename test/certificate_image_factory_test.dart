import 'package:dr/ui/certificate_image_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final school = Uri.parse('https://ms-sspterlan.digitalesregister.it');

  test('resolves the reported certificate background image URL', () {
    final factory = CertificateImageFactory(school);
    final image = factory.imageProviderFromFileUri(
      'file:///images/ms-sspterlan.jpg',
    );

    expect(image, isA<NetworkImage>());
    expect(
      (image! as NetworkImage).url,
      'https://ms-sspterlan.digitalesregister.it/images/ms-sspterlan.jpg',
    );
  });

  test('resolves the other reported school images to their own hosts', () {
    for (final schoolName in ['ms-neumarkt', 'rgtfo-me']) {
      final site = Uri.parse('https://$schoolName.digitalesregister.it');
      final image = CertificateImageFactory(site).imageProviderFromFileUri(
        'file:///images/$schoolName.jpg',
      );
      expect(
        (image! as NetworkImage).url,
        'https://$schoolName.digitalesregister.it/images/$schoolName.jpg',
      );
    }
  });

  test('keeps image query parameters when replacing the invalid file scheme',
      () {
    expect(
      resolveCertificateImageUri('file:///images/logo.jpg?v=2', school)
          .toString(),
      'https://ms-sspterlan.digitalesregister.it/images/logo.jpg?v=2',
    );
  });

  test('resolves root-relative and relative CSS background images', () {
    final factory = CertificateImageFactory(school);
    expect(
      (factory.imageProviderFromNetwork('/images/logo.jpg')! as NetworkImage)
          .url,
      'https://ms-sspterlan.digitalesregister.it/images/logo.jpg',
    );
    expect(
      (factory.imageProviderFromNetwork('images/logo.jpg')! as NetworkImage)
          .url,
      'https://ms-sspterlan.digitalesregister.it/images/logo.jpg',
    );
  });

  test('keeps absolute network and other local images available', () {
    final factory = CertificateImageFactory(school);
    expect(
      (factory.imageProviderFromNetwork('https://example.org/logo.png')!
              as NetworkImage)
          .url,
      'https://example.org/logo.png',
    );
    expect(factory.imageProviderFromFileUri('file:///tmp/local.png'),
        isA<FileImage>());
  });

  test('does not send unresolved image references to NetworkImage', () {
    final factory = CertificateImageFactory(null);
    expect(factory.imageProviderFromNetwork('/images/logo.jpg'), isNull);
    expect(factory.imageProviderFromFileUri('file:///images/logo.jpg'), isNull);
    expect(factory.imageProviderFromNetwork('file:///images/logo.jpg'), isNull);
  });
}
