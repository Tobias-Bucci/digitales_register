// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

/// The certificate in the new design: the school's HTML on a glass card in
/// readable width, with its colours made readable on the light, the dark and
/// the AMOLED theme. The legacy page stays in `certificate.dart`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/export_container.dart';
import 'package:dr/export/export_data.dart' show ExportCategory, readableHtml;
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/certificate_image_factory.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The text the server sends in place of a certificate, in its languages. The
/// export recognizes the same texts (`export_data.dart`).
final _unavailable = RegExp(
  'report card not available|zeugnis (ist )?nicht verfügbar|'
  'pagella non disponibile',
  caseSensitive: false,
);

/// Whether [html] holds a certificate: some text, and not the server's note
/// that there is none.
bool certificateAvailable(String html) {
  final text = readableHtml(html);
  return text.isNotEmpty && !_unavailable.hasMatch(text);
}

/// The certificate page of the new design. It asks for the certificate when
/// it opens ([onLoad], which joins a load already on its way), so that it can
/// tell a failed load from a slow one.
class CertificateNew extends StatefulWidget {
  const CertificateNew({
    super.key,
    required this.vm,
    required this.onLoad,
    required this.onRetry,
  });

  final CertificateViewModel vm;
  final Future<void> Function() onLoad;

  /// Tries again after the connection was lost or a load failed.
  final Future<void> Function() onRetry;

  @override
  State<CertificateNew> createState() => _CertificateNewState();
}

class _CertificateNewState extends State<CertificateNew> {
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run(widget.onLoad));
  }

  Future<void> _run(Future<void> Function() load) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    var threw = false;
    try {
      await load();
    } catch (_) {
      threw = true;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Without a connection the page says so; otherwise a load that brought
      // nothing has failed.
      _failed = !widget.vm.noInternet && (threw || widget.vm.html == null);
    });
  }

  void _retry() => unawaited(_run(widget.onRetry));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vm = widget.vm;
    return GlassPage(
      loading: _loading && !vm.noInternet,
      header: GlassPageHeader(
        surfaceKey: const Key('certificate-app-header'),
        titleKey: const Key('certificate-header-title'),
        title: l10n.text('certificate.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        actions: [
          HeaderDiscButton(
            key: const Key('certificate-export'),
            tooltip: l10n.text('export.title'),
            icon: Icons.file_download_outlined,
            onPressed: () => openExportPage(
              context,
              category: ExportCategory.certificates,
            ),
          ),
        ],
      ),
      body: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final vm = widget.vm;
    final html = vm.html;
    if (html == null) {
      if (vm.noInternet) {
        return GlassStateCard(
          key: const Key('certificate-offline'),
          icon: Icons.wifi_off_rounded,
          title: l10n.text('offline.title'),
          body: l10n.text('offline.body'),
          actionLabel: l10n.text('common.retry'),
          onAction: _retry,
        );
      }
      if (_failed) {
        return GlassStateCard(
          key: const Key('certificate-error'),
          icon: Icons.error_outline_rounded,
          title: l10n.text('certificate.loadFailed'),
          body: '',
          actionLabel: l10n.text('common.retry'),
          onAction: _retry,
        );
      }
      // The bar below the header shows that the certificate is on its way.
      return const SizedBox.expand(key: Key('certificate-loading'));
    }
    final lastFetched = vm.lastFetched;
    final hint = vm.noInternet && lastFetched != null
        ? GlassOfflineHint(
            key: const Key('certificate-last-fetched'),
            message: l10n.text(
              'grades.offlineMode',
              args: {'time': l10n.formatTimeAgo(lastFetched)},
            ),
            onRetry: _retry,
          )
        : null;
    if (!_CertificateHtml.available(html)) {
      final empty = GlassStateCard(
        key: const Key('certificate-empty'),
        icon: Icons.description_outlined,
        title: l10n.text('certificate.empty'),
        body: l10n.text('certificate.emptyBody'),
      );
      if (hint == null) return empty;
      return GlassListBody(
        listKey: const Key('certificate-list'),
        children: [hint, const SizedBox(height: 8), empty],
      );
    }
    return GlassListBody(
      listKey: const Key('certificate-list'),
      children: [
        if (hint != null) ...[hint, const SizedBox(height: 8)],
        GlassCard(
          key: const Key('certificate-card'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: _CertificateHtml(html: html, baseUrl: vm.baseUrl),
        ),
      ],
    );
  }
}

/// The school's HTML, unchanged in its content. Only colours that would not
/// be readable on the card are replaced, wide tables scroll sideways inside
/// the card, and images keep a light backing on a dark theme.
class _CertificateHtml extends StatefulWidget {
  const _CertificateHtml({required this.html, required this.baseUrl});

  final String html;
  final String? baseUrl;

  static String? _lastHtml;
  static bool _lastAvailable = false;

  /// [certificateAvailable], remembered for the last certificate, as the page
  /// builds again with every change of the store.
  static bool available(String html) {
    if (html != _lastHtml) {
      _lastHtml = html;
      _lastAvailable = certificateAvailable(html);
    }
    return _lastAvailable;
  }

  @override
  State<_CertificateHtml> createState() => _CertificateHtmlState();
}

class _CertificateHtmlState extends State<_CertificateHtml> {
  String? _source;
  ColorScheme? _scheme;
  late String _adapted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_source != widget.html || _scheme != scheme) {
      _source = widget.html;
      _scheme = scheme;
      _adapted = adaptCertificateHtml(
        widget.html,
        scheme,
        highContrast: MediaQuery.highContrastOf(context),
      );
    }
    final parsedBaseUrl = Uri.tryParse(widget.baseUrl ?? '');
    final baseUrl = parsedBaseUrl != null &&
            (parsedBaseUrl.scheme == 'http' ||
                parsedBaseUrl.scheme == 'https') &&
            parsedBaseUrl.host.isNotEmpty
        ? parsedBaseUrl
        : null;
    final dark = theme.brightness == Brightness.dark;
    final outline = _css(scheme.outlineVariant);
    return HtmlWidget(
      _adapted,
      key: const Key('certificate-html'),
      baseUrl: baseUrl,
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
        height: 1.4,
      ),
      // Below whatever the school's HTML says itself: room in the cells, so
      // that a bare table does not run its columns together.
      customStylesBuilder: (element) => switch (element.localName) {
        'td' || 'th' => {
            'padding': '4px 8px',
            'vertical-align': 'top',
          },
        'hr' => {'border-top': '1px solid $outline'},
        _ => null,
      },
      factoryBuilder: () => _GlassCertificateFactory(
        baseUrl,
        imageBacking: dark ? scheme.onSurface : null,
      ),
    );
  }
}

/// [CertificateImageFactory], whose wide tables scroll inside the card and
/// whose images stand on [imageBacking], for stamps and signatures in black
/// ink on a dark theme.
class _GlassCertificateFactory extends CertificateImageFactory {
  _GlassCertificateFactory(super.baseUrl, {required this.imageBacking});

  final Color? imageBacking;

  /// After the table itself and its box, so that all of it scrolls.
  static const _scrollPriority = 8999999999999999;

  static final _scrollOp = BuildOp.v2(
    debugLabel: 'certificate-table-scroll',
    priority: _scrollPriority,
    onRenderBlock: (tree, child) => _ScrollingTable(child: child),
  );

  @override
  void parse(BuildTree tree) {
    super.parse(tree);
    final element = tree.element;
    if (element.localName == 'table' && !_insideTable(element)) {
      tree.register(_scrollOp);
    }
  }

  static bool _insideTable(dom.Element element) {
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (parent.localName == 'table') return true;
    }
    return false;
  }

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final image = super.buildImageWidget(tree, src);
    final backing = imageBacking;
    if (image == null || backing == null) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backing,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Padding(padding: const EdgeInsets.all(4), child: image),
    );
  }
}

/// A table in the width of the card, which scrolls sideways where its words
/// do not fit, rather than running out of the card on a narrow phone.
class _ScrollingTable extends StatelessWidget {
  const _ScrollingTable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (!width.isFinite) return child;
          return SingleChildScrollView(
            key: const Key('certificate-table-scroll'),
            scrollDirection: Axis.horizontal,
            child: _FitOrGrow(width: width, child: child),
          );
        },
      );
}

/// Lays out its child in [width], or, where it is wider without breaking its
/// lines, in that width up to 720 px.
class _FitOrGrow extends SingleChildRenderObjectWidget {
  const _FitOrGrow({required this.width, required super.child});

  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFitOrGrow(width);

  @override
  void updateRenderObject(BuildContext context, _RenderFitOrGrow renderObject) {
    renderObject.width = width;
  }
}

class _RenderFitOrGrow extends RenderProxyBox {
  _RenderFitOrGrow(this._width);

  /// The widest a table gets where long cells could still wrap.
  static const double _maxWidth = 720;

  double _width;
  double get width => _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // A table cannot tell how narrow it may get, only how wide it is without
    // breaking a line, and it runs out of a narrower box rather than growing.
    // So it gets that width, within [_maxWidth], where the card is too narrow.
    child.layout(const BoxConstraints(), parentUsesSize: true);
    final natural = child.size.width;
    child.layout(
      BoxConstraints(maxWidth: math.max(_width, math.min(natural, _maxWidth))),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      // Measuring needs a real layout of the table.
      constraints.constrain(Size(_width, 0));
}

/// [html] with the colours that would not be readable on the card of
/// [scheme] replaced: text in a colour too close to the card gets
/// `onSurface`, a background the text would vanish on gets a faint tint, and
/// borders that disappear get `outlineVariant`. Everything else, the text
/// above all, stays as the school sent it.
String adaptCertificateHtml(
  String html,
  ColorScheme scheme, {
  bool highContrast = false,
}) {
  if (!html.contains('<')) return html;
  final card = highContrast
      ? scheme.surfaceContainerLowest
      : Color.alphaBlend(
          scheme.surfaceContainerLowest.withValues(
            alpha: DesignTokens.cardOpacity,
          ),
          scheme.surface,
        );
  final text = _css(scheme.onSurface);
  final tint = _css(scheme.onSurface.withValues(alpha: 0.08));
  final line = _css(scheme.outlineVariant);
  bool readableText(Color color) =>
      _contrast(Color.alphaBlend(color, card), card) >= 3;
  bool readableBackground(Color color) =>
      color.a == 0 ||
      _contrast(scheme.onSurface, Color.alphaBlend(color, card)) >= 4.5;
  bool visibleLine(Color color) =>
      _contrast(Color.alphaBlend(color, card), card) >= 1.3;

  final fragment =
      html_parser.HtmlParser(html, parseMeta: false).parseFragment();
  var changed = false;
  for (final element in fragment.querySelectorAll('*')) {
    final attributes = element.attributes;
    final style = attributes['style'];
    if (style != null && style.isNotEmpty) {
      final adapted = style.replaceAllMapped(_declaration, (match) {
        final property = match[2]!.toLowerCase();
        final value = match[3]!;
        if (property == 'color') {
          return _replaceColors(match, value, readableText, text);
        }
        if (property.startsWith('background')) {
          // An image is not a colour; leave it alone.
          if (value.contains('url(')) return match[0]!;
          return _replaceColors(match, value, readableBackground, tint);
        }
        return _replaceColors(match, value, visibleLine, line);
      });
      if (adapted != style) {
        attributes['style'] = adapted;
        changed = true;
      }
    }
    final color = attributes['color'];
    final parsedColor = color == null ? null : _parseColor(color);
    if (parsedColor != null && !readableText(parsedColor)) {
      attributes['color'] = text;
      changed = true;
    }
    final background = attributes['bgcolor'];
    final parsedBackground =
        background == null ? null : _parseColor(background);
    if (parsedBackground != null && !readableBackground(parsedBackground)) {
      attributes.remove('bgcolor');
      final style = attributes['style'];
      attributes['style'] = [
        if (style != null && style.trim().isNotEmpty)
          style.trim().replaceFirst(RegExp(r';$'), ''),
        'background-color: $tint',
      ].join('; ');
      changed = true;
    }
    final borderColor = attributes['bordercolor'];
    final parsedBorder = borderColor == null ? null : _parseColor(borderColor);
    if (parsedBorder != null && !visibleLine(parsedBorder)) {
      attributes['bordercolor'] = line;
      changed = true;
    }
  }
  return changed ? fragment.outerHtml : html;
}

/// One declaration of a style attribute whose colours may need a change.
final _declaration = RegExp(
  r'(^|;)\s*(color|background(?:-color)?|'
  'border(?:-(?:top|right|bottom|left))?(?:-color)?|outline(?:-color)?)'
  r'\s*:\s*([^;]*)',
  caseSensitive: false,
);

final _colorToken = RegExp(
  r'#[0-9a-f]{3,8}\b|rgba?\([^)]*\)|\b(?:' + _named.keys.join('|') + r')\b',
  caseSensitive: false,
);

String _replaceColors(
  Match declaration,
  String value,
  bool Function(Color) keep,
  String replacement,
) {
  final adapted = value.replaceAllMapped(_colorToken, (token) {
    final color = _parseColor(token[0]!);
    return color == null || keep(color) ? token[0]! : replacement;
  });
  if (adapted == value) return declaration[0]!;
  final whole = declaration[0]!;
  return whole.substring(0, whole.length - value.length) + adapted;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

String _css(Color color) {
  int channel(double value) => (value * 255).round().clamp(0, 255);
  final r = channel(color.r), g = channel(color.g), b = channel(color.b);
  if (color.a >= 1) {
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    return '#${hex(r)}${hex(g)}${hex(b)}';
  }
  return 'rgba($r, $g, $b, ${color.a.toStringAsFixed(2)})';
}

/// The colours HTML of a school is likely to name.
const _named = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'darkgray': 0xFFA9A9A9,
  'darkgrey': 0xFFA9A9A9,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'lightgray': 0xFFD3D3D3,
  'lightgrey': 0xFFD3D3D3,
  'gainsboro': 0xFFDCDCDC,
  'whitesmoke': 0xFFF5F5F5,
  'silver': 0xFFC0C0C0,
  'red': 0xFFFF0000,
  'darkred': 0xFF8B0000,
  'maroon': 0xFF800000,
  'green': 0xFF008000,
  'darkgreen': 0xFF006400,
  'blue': 0xFF0000FF,
  'darkblue': 0xFF00008B,
  'navy': 0xFF000080,
  'yellow': 0xFFFFFF00,
  'orange': 0xFFFFA500,
  'transparent': 0x00000000,
};

Color? _parseColor(String raw) {
  final value = raw.trim().toLowerCase();
  final named = _named[value];
  if (named != null) return Color(named);
  if (value.startsWith('#')) {
    var hex = value.substring(1);
    if (hex.length == 3 || hex.length == 4) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    if (hex.length == 6) return Color(0xFF000000 | parsed);
    if (hex.length == 8) {
      // CSS puts the alpha last.
      return Color(((parsed & 0xFF) << 24) | (parsed >> 8));
    }
    return null;
  }
  final match = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(value);
  if (match == null) return null;
  final parts = match[1]!
      .split(RegExp(r'[\s,/]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 3) return null;
  double? component(String part, double scale) {
    if (part.endsWith('%')) {
      final percent = double.tryParse(part.substring(0, part.length - 1));
      return percent == null ? null : percent / 100;
    }
    final number = double.tryParse(part);
    return number == null ? null : number / scale;
  }

  final r = component(parts[0], 255);
  final g = component(parts[1], 255);
  final b = component(parts[2], 255);
  final a = parts.length > 3 ? component(parts[3], 1) : 1.0;
  if (r == null || g == null || b == null || a == null) return null;
  return Color.from(
    alpha: a.clamp(0, 1),
    red: r.clamp(0, 1),
    green: g.clamp(0, 1),
    blue: b.clamp(0, 1),
  );
}
