import 'package:flutter/widgets.dart';

/// Keeps text-heavy pages readable while letting their scroll views fill the
/// available height. Uses the page's constraints, including in iPad windows.
class ReadableContent extends StatelessWidget {
  const ReadableContent({
    super.key,
    required this.child,
    this.maxWidth = 960,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
