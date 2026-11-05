import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

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

/// [ReadableContent] for pages that Legacy shares, which stay as they are there.
class NewDesignReadable extends StatelessWidget {
  const NewDesignReadable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ResponsiveNavigationScope.isActive(context)
          ? ReadableContent(
              maxWidth: DesignTokens.contentMaxWidth,
              child: child,
            )
          : child;
}
