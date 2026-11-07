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

import 'package:dr/main.dart' show showSnackBar, tr;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

const _maxLinkLength = 2048;

final _foreignScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:(?!\d)');
final _whitespace = RegExp(r'\s');

/// Where a link typed by a teacher leads, or null if it is not one the app
/// should open: only web addresses count. A missing scheme, as in
/// `www.example.org`, means https.
Uri? parseExternalLink(String? value) {
  final text = value?.trim();
  if (text == null ||
      text.isEmpty ||
      text.length > _maxLinkLength ||
      text.contains(_whitespace)) {
    return null;
  }
  final hasScheme = text.contains('://');
  if (!hasScheme && _foreignScheme.hasMatch(text)) return null;
  final uri = Uri.tryParse(hasScheme ? text : 'https://$text');
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  // `https://school.it@example.org` only looks like it leads to the school.
  if (uri.userInfo.isNotEmpty) return null;
  return uri.host.contains('.') ? uri : null;
}

/// What to show below a link called [name]: where it leads, or the link as it
/// was typed if it is not a valid one. Null if [name] already says as much.
String? linkCaption(String name, String? link) {
  final text = link?.trim();
  if (text == null || text.isEmpty || text == name.trim()) return null;
  return parseExternalLink(text)?.host ?? text;
}

/// A piece of a text: a link if [uri] is set, plain text otherwise.
@immutable
class TextLinkSegment {
  const TextLinkSegment(this.text, [this.uri]);

  final String text;
  final Uri? uri;

  @override
  bool operator ==(Object other) =>
      other is TextLinkSegment && other.text == text && other.uri == uri;

  @override
  int get hashCode => Object.hash(text, uri);

  @override
  String toString() => 'TextLinkSegment($text, $uri)';
}

final _linkInText = RegExp(
  r'''(?<![\w@./-])(?:https?://|www\.)[^\s<>"']+''',
  caseSensitive: false,
);

const _sentencePunctuation = '.,;:!?';
const _closingBrackets = {')': '(', ']': '[', '}': '{'};

/// Sentence punctuation after a link, and a closing bracket that was opened
/// before it, belong to the text around it.
String _withoutTrailingText(String match) {
  var end = match.length;
  while (end > 0) {
    final last = match[end - 1];
    final opening = _closingBrackets[last];
    final unbalanced = opening != null &&
        opening.allMatches(match.substring(0, end)).length <
            last.allMatches(match.substring(0, end)).length;
    if (!_sentencePunctuation.contains(last) && !unbalanced) break;
    end--;
  }
  return match.substring(0, end);
}

/// Splits [text] around the web addresses in it. What looks like an address
/// but is not a valid one stays plain text.
List<TextLinkSegment> splitTextLinks(String text) {
  final segments = <TextLinkSegment>[];
  var position = 0;
  for (final match in _linkInText.allMatches(text)) {
    final link = _withoutTrailingText(match.group(0)!);
    final uri = parseExternalLink(link);
    if (uri == null) continue;
    if (match.start > position) {
      segments.add(TextLinkSegment(text.substring(position, match.start)));
    }
    segments.add(TextLinkSegment(link, uri));
    position = match.start + link.length;
  }
  if (position < text.length) {
    segments.add(TextLinkSegment(text.substring(position)));
  }
  return segments;
}

/// Replaces the system browser in tests.
@visibleForTesting
Future<bool> Function(Uri uri)? externalLinkLauncherOverride;

/// Opens [link] in the system browser and tells the user if that fails.
Future<bool> openExternalLink(String? link) async {
  final uri = parseExternalLink(link);
  var opened = false;
  if (uri != null) {
    try {
      final launcher = externalLinkLauncherOverride;
      opened = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
  }
  if (!opened) showSnackBar(tr('navigation.linkOpenFailed'));
  return opened;
}
