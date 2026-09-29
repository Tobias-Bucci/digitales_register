// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// Resolves image references in certificate HTML against the school's site.
/// Certificate pages sometimes contain file:///images/... for server images.
Uri? resolveCertificateImageUri(String source, Uri? baseUrl) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null || source.trim().isEmpty) return null;

  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return uri.host.isNotEmpty ? uri : null;
  }

  if (baseUrl == null ||
      (baseUrl.scheme != 'http' && baseUrl.scheme != 'https') ||
      baseUrl.host.isEmpty) {
    return null;
  }

  if (uri.scheme == 'file' &&
      uri.host.isEmpty &&
      uri.path.startsWith('/images/')) {
    return baseUrl.resolveUri(Uri(
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ));
  }

  return uri.hasScheme ? null : baseUrl.resolveUri(uri);
}

class CertificateImageFactory extends WidgetFactory {
  CertificateImageFactory(this.baseUrl);

  final Uri? baseUrl;

  @override
  ImageProvider? imageProviderFromNetwork(String url) {
    final resolved = resolveCertificateImageUri(url, baseUrl);
    return resolved == null
        ? null
        : super.imageProviderFromNetwork('$resolved');
  }

  @override
  ImageProvider? imageProviderFromFileUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isEmpty && uri.path.startsWith('/images/')) {
      final resolved = resolveCertificateImageUri(url, baseUrl);
      return resolved == null
          ? null
          : super.imageProviderFromNetwork('$resolved');
    }
    return super.imageProviderFromFileUri(url);
  }
}
