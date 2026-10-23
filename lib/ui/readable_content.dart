import 'package:flutter/widgets.dart';

/// Keeps text-heavy pages readable while letting their scroll views fill the
/// available height. Uses the page's constraints, including in iPad windows.
class ReadableContent extends StatelessWidget {
  const ReadableContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: child,
        ),
      );
}
