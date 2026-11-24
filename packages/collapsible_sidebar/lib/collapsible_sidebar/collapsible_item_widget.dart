import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

class CollapsibleItemWidget extends StatelessWidget {
  const CollapsibleItemWidget({
    Key? key,
    required this.leading,
    required this.title,
    required this.tooltip,
    required this.textStyle,
    required this.padding,
    required this.height,
    required this.offsetX,
    required this.titleOpacity,
    required this.selected,
    this.onTap,
    this.selectedBoxColor,
    this.hasDivider = false,
    this.curve,
    this.leadingSize,
  }) : super(key: key);

  final Widget leading;
  final Widget? title;
  final String tooltip;
  final TextStyle textStyle;

  /// [height] is the least height of the item: it grows when its content,
  /// such as a label in a large text size, needs more.
  final double offsetX, padding, height, titleOpacity;
  final VoidCallback? onTap;
  final bool selected, hasDivider;
  final Color? selectedBoxColor;
  final Curve? curve;

  /// The height of [leading] when [title] is a text: the leading widget then
  /// stays beside the first line of a text that wraps. Without it, leading
  /// and title are centered on each other.
  final double? leadingSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          if (hasDivider)
            const Divider(
              endIndent: 5,
              indent: 5,
            ),
          // At least [height]; taller when the content needs it.
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  bottom: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 1000),
                    curve: curve ?? Curves.linear,
                    child: Container(
                      key: selected
                          ? const ValueKey('collapsible-sidebar-selected-box')
                          : null,
                      decoration: BoxDecoration(
                        color: selectedBoxColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                // A button for screen readers too, not a plain view.
                Semantics(
                  button: true,
                  selected: selected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onTap,
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return ui.Gradient.linear(
                          Offset(bounds.right - 10, 0),
                          Offset(bounds.right, 0),
                          [Colors.white, Colors.white.withAlpha(0)],
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.all(padding),
                        // Wider than the item while the sidebar is collapsed or
                        // moving; as tall as the content.
                        child: OverflowBox(
                          maxWidth: 300,
                          alignment: Alignment.centerLeft,
                          fit: OverflowBoxFit.deferToChild,
                          child: leadingSize == null
                              ? _centered()
                              : _besideFirstLine(context, leadingSize!),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(Widget title) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        width: 210,
        child: Opacity(
          opacity: titleOpacity,
          child: DefaultTextStyle(
            style: textStyle,
            child: title,
          ),
        ),
      );

  Widget _centered() => Row(
        children: [
          Tooltip(
            message: tooltip,
            child: leading,
          ),
          if (title != null) _label(title!),
        ],
      );

  /// The leading widget beside the first line of the label: as tall as that
  /// line, or the label as tall as the leading widget if that is taller, so
  /// a label of one line stays centered on it as before.
  Widget _besideFirstLine(BuildContext context, double leadingSize) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final lineHeight = painter.height;
    painter.dispose();
    // The hidden label of a collapsed sidebar takes no room: its items stay
    // square, and they grow with the label as it fades in.
    final line = ui.lerpDouble(
      leadingSize,
      math.max(leadingSize, lineHeight),
      titleOpacity,
    )!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: tooltip,
          child: SizedBox(
            height: line,
            child: Align(widthFactor: 1, child: leading),
          ),
        ),
        if (title != null)
          Align(
            alignment: Alignment.topLeft,
            heightFactor: titleOpacity,
            child: _label(
              // As wide as before, and centered on the leading widget
              // while it is one line.
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: line),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title!],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
