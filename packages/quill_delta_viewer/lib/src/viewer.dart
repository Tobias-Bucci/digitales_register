import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:url_launcher/url_launcher.dart';

class QuillDeltaViewer extends StatefulWidget {
  /// The document delta to be rendered
  final Delta delta;

  /// Opens a link the user tapped. Without it, the link is handed to the
  /// platform as it is.
  final void Function(String link)? onLinkTap;

  const QuillDeltaViewer({Key? key, required this.delta, this.onLinkTap})
      : super(key: key);

  @override
  State<QuillDeltaViewer> createState() => _QuillDeltaViewerState();

  /// Splits all operations at newlines
  /// Newlines will be at the end of operations
  List<Operation> isolateLines(Delta delta) {
    final List<Operation> operations = [];
    for (var i = 0; i < delta.length; i++) {
      final op = delta.elementAt(i);
      var string = op.stringData;
      final split = <String>[];
      for (;;) {
        final index = string.indexOf("\n");
        if (index == -1) {
          split.add(string);
          break;
        }
        split.add(string.substring(0, index + 1));
        string = string.substring(index + 1);
      }
      operations.addAll(
        split.map(
          (s) => Operation.insert(
            s,
            op.attributes,
          ),
        ),
      );
    }
    return operations;
  }

  /// Removes the line break that ends [operations]. The viewer no longer
  /// uses this: the last line break carries the format of the last line, so
  /// the lines are read with their breaks (#144).
  List<Operation> removeLastNewline(List<Operation> operations) {
    while (operations.last.stringData.isEmpty) {
      operations.removeLast();
    }
    return operations
      ..add(
        removeTrailingNewline(
          operations.removeLast(),
        ),
      );
  }

  Operation removeTrailingNewline(Operation operation) {
    if (operation.stringData.lastIndexOf("\n") ==
        operation.stringData.length - 1) {
      return Operation.insert(
        operation.stringData.substring(
          0,
          operation.stringData.length - 1,
        ),
        operation.attributes,
      );
    } else {
      return operation;
    }
  }
}

/// Owns the tap recognizers of the links: one per link of the text, made
/// once, reused when only the theme changes, and disposed when the text
/// changes or the widget goes away.
class _QuillDeltaViewerState extends State<QuillDeltaViewer> {
  final _recognizers = <TapGestureRecognizer>[];
  var _nextRecognizer = 0;

  /// What [build] shows, until the text or the theme changes.
  Widget? _content;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content = null;
  }

  @override
  void didUpdateWidget(QuillDeltaViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.delta, widget.delta) &&
        oldWidget.delta != widget.delta) {
      // The old spans are replaced in this frame, before any tap.
      _disposeRecognizers();
      _content = null;
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    var content = _content;
    if (content == null) {
      _nextRecognizer = 0;
      content = _content = render(
        _readLines(widget.isolateLines(widget.delta)),
        context,
      );
    }
    return content;
  }

  /// Shows [lines]. Lines without a line format are shown together as one
  /// text, as before; a line with a format is a block of its own.
  Widget render(List<_Line> lines, BuildContext context) {
    final widgets = <Widget>[];
    final plain = <_Line>[];
    // The number of the current line of a numbered list, 0 outside one.
    var number = 0;

    void addPlain() {
      if (plain.isEmpty) return;
      final spans = <InlineSpan>[];
      for (var i = 0; i < plain.length; i++) {
        if (i > 0) spans.add(const TextSpan(text: '\n'));
        spans.addAll(plain[i].text.map((op) => renderText(op, context)));
      }
      widgets.add(Text.rich(TextSpan(children: spans)));
      plain.clear();
    }

    for (final line in lines) {
      final format = line.format;
      if (format == null) {
        plain.add(line);
        number = 0;
        continue;
      }
      addPlain();
      number = format['list'] == 'ordered' ? number + 1 : 0;
      widgets.add(renderBlock(line, number, context));
    }
    addPlain();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// A line with a line format: a list item ([number] is its number in a
  /// numbered list), a heading or a block quote.
  Widget renderBlock(_Line line, int number, BuildContext context) {
    final format = line.format!;
    final theme = Theme.of(context);
    final level = _headerLevel(format['header']);
    final headerStyle = level == null ? null : _headerStyle(level, theme);

    Widget block = Text.rich(
      TextSpan(
        children: line.text.map((op) => renderText(op, context)).toList(),
      ),
      style: headerStyle,
    );
    if (level != null) {
      block = Semantics(header: true, child: block);
    }

    final list = format['list'];
    if (list != null) {
      block = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(list == 'ordered' ? '$number.' : '•', style: headerStyle),
          const SizedBox(width: 2.5),
          Expanded(child: block),
        ],
      );
    }

    final quote = format['blockquote'];
    if (quote != null && quote != false) {
      block = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            child: block,
          ),
        ),
      );
    }
    return block;
  }

  /// Headings 1 to 3 take the title sizes of the theme; smaller headings
  /// look like heading 3. The color stays the one of the text around them.
  TextStyle _headerStyle(int level, ThemeData theme) {
    final title = switch (level) {
      1 => theme.textTheme.titleLarge,
      2 => theme.textTheme.titleMedium,
      _ => theme.textTheme.titleSmall,
    };
    return TextStyle(
      fontSize: title?.fontSize,
      letterSpacing: title?.letterSpacing,
      fontWeight: FontWeight.w600,
    );
  }

  TextSpan renderText(Operation op, BuildContext context) {
    bool bold = false;
    bool italics = false;
    String? link;
    bool strike = false;
    bool underline = false;
    if (op.attributes != null) {
      bold = op.attributes!["bold"] == true;
      // Quill.js writes "italic"; earlier versions of this viewer read
      // "italics". Both are shown (#144).
      italics =
          op.attributes!["italic"] == true || op.attributes!["italics"] == true;
      link = op.attributes!["link"] as String?;
      strike = op.attributes!["strike"] == true;
      underline = op.attributes!["underline"] == true;
    }

    final text = op.stringData;

    return TextSpan(
      text: text,
      style: TextStyle(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italics ? FontStyle.italic : null,
        decoration: TextDecoration.combine(
          [
            if (strike) TextDecoration.lineThrough,
            // A link is underlined, so it is not told apart by color alone.
            if (underline || link != null) TextDecoration.underline,
          ],
        ),
        color: link != null ? Theme.of(context).colorScheme.primary : null,
      ),
      recognizer: link == null ? null : _recognizerFor(link),
    );
  }

  /// The recognizer of the next link of the text. The links come in the same
  /// order on every build of the same text, so a recognizer made for an
  /// earlier build of it leads to the same [link].
  TapGestureRecognizer _recognizerFor(String link) {
    if (_nextRecognizer < _recognizers.length) {
      return _recognizers[_nextRecognizer++];
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        final open = widget.onLinkTap;
        if (open != null) {
          open(link);
        } else {
          launchUrl(Uri.parse(link));
        }
      };
    _recognizers.add(recognizer);
    _nextRecognizer++;
    return recognizer;
  }
}

extension DataHelper on Operation {
  String get stringData => data as String;
}

/// The line formats the viewer shows. Others, such as `indent`, `align` or
/// `code-block`, leave the line as plain text.
const _lineFormats = {'list', 'header', 'blockquote'};

/// One line of the text: its text without the line break, and the line
/// format that the line break carries, if any.
class _Line {
  _Line(this.text, this.format);

  final List<Operation> text;
  final Map<String, dynamic>? format;
}

int? _headerLevel(Object? header) {
  if (header == null || header == false) return null;
  final level = header is int ? header : int.tryParse('$header');
  return level != null && level > 0 ? level : null;
}

/// Reads the lines of [operations], which [QuillDeltaViewer.isolateLines]
/// split so that a line break only ends an operation. The last line keeps its
/// format; empty lines without a format at the end are left out, so a text
/// does not end with blank space.
List<_Line> _readLines(List<Operation> operations) {
  final lines = <_Line>[];
  var text = <Operation>[];
  for (final op in operations) {
    final data = op.stringData;
    if (data.isEmpty) continue;
    if (!data.endsWith('\n')) {
      text.add(op);
      continue;
    }
    if (data.length > 1) {
      text.add(Operation.insert(
        data.substring(0, data.length - 1),
        op.attributes,
      ));
    }
    final format = <String, dynamic>{
      for (final entry in (op.attributes ?? const <String, dynamic>{}).entries)
        if (_lineFormats.contains(entry.key) && entry.value != null)
          entry.key: entry.value,
    };
    lines.add(_Line(text, format.isEmpty ? null : format));
    text = [];
  }
  if (text.isNotEmpty) lines.add(_Line(text, null));
  while (lines.isNotEmpty &&
      lines.last.format == null &&
      lines.last.text.every((op) => op.stringData.isEmpty)) {
    lines.removeLast();
  }
  return lines;
}
