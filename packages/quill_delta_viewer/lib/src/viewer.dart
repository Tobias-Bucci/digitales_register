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
        widget.removeLastNewline(widget.isolateLines(widget.delta)),
        context,
      );
    }
    return content;
  }

  Widget render(List<Operation> ops, BuildContext context) {
    final reversed = ops.reversed.toList();
    final widgets = <Widget>[];
    var spans = <InlineSpan>[];

    /// Whether we previously rendered a block.
    /// blocks always go to a new line automatically, so _one_
    /// newline in front should be removed
    var renderedBlock = false;

    for (var i = 0; i < reversed.length; i++) {
      var op = reversed[i];
      if (op.data == "\n") {
        if (spans.isNotEmpty) {
          widgets.add(
            Text.rich(
              TextSpan(
                children: spans.reversed.toList(),
              ),
            ),
          );
          spans = [];
        }
        var use = <Operation>[];
        while (reversed.length > i + 1 &&
            !reversed[i + 1].stringData.endsWith("\n")) {
          use.add(reversed[i + 1]);
          i++;
        }
        use = use.reversed.toList();
        widgets.add(renderBlock(use..add(op), context));
        renderedBlock = true;
      } else {
        if (renderedBlock) {
          op = widget.removeTrailingNewline(op);
        }
        spans.add(renderText(op, context));
        renderedBlock = false;
      }
    }
    if (spans.isNotEmpty) {
      widgets.add(
        Text.rich(
          TextSpan(
            children: spans.reversed.toList(),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets.reversed.toList(),
    );
  }

  Widget renderBlock(List<Operation> ops, BuildContext context) {
    final blockOperation = ops.last;

    bool list = false;
    if (blockOperation.attributes != null) {
      list = blockOperation.attributes!["list"] != null;
    }
    final text = Text.rich(
      TextSpan(
        children: widget
            .removeLastNewline(ops)
            .map(
              (e) => renderText(e, context),
            )
            .toList(),
      ),
    );

    if (list) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("•"),
          const SizedBox(width: 2.5),
          Expanded(child: text),
        ],
      );
    }
    return text;
  }

  TextSpan renderText(Operation op, BuildContext context) {
    bool bold = false;
    bool italics = false;
    String? link;
    bool strike = false;
    bool underline = false;
    if (op.attributes != null) {
      bold = op.attributes!["bold"] == true;
      italics = op.attributes!["italics"] == true;
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
