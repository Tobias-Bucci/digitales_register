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

import 'package:dr/external_links.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Selectable text whose web addresses open in the system browser.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  late List<TextLinkSegment> _segments;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parse();
  }

  void _parse() {
    _disposeRecognizers();
    _segments = splitTextLinks(widget.text);
    for (final segment in _segments) {
      if (segment.uri == null) continue;
      _recognizers.add(TapGestureRecognizer()
        ..onTap = () => openExternalLink(segment.uri.toString()));
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recognizers.isEmpty) {
      return SelectableText(widget.text, style: widget.style);
    }
    final decoration = widget.style?.decoration;
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.combine([
        TextDecoration.underline,
        if (decoration != null) decoration,
      ]),
    );
    final recognizers = _recognizers.iterator;
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final segment in _segments)
            if (segment.uri == null)
              TextSpan(text: segment.text)
            else
              TextSpan(
                text: segment.text,
                style: linkStyle,
                recognizer: (recognizers..moveNext()).current,
              ),
        ],
      ),
      style: widget.style,
    );
  }
}
