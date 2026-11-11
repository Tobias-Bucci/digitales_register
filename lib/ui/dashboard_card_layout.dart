import 'package:dr/dashboard_items.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays the cards out in rows. Every card is measured at the width it gets in
/// its row, and all cards of a row get the height of the tallest one there, so
/// a row is only as tall as its content needs. Supports LayoutBuilder/loading
/// cards without intrinsic sizing or a fixed height that could clip
/// translated/large text.
class DashboardCardLayout extends MultiChildRenderObjectWidget {
  const DashboardCardLayout(
      {super.key,
      required this.widths,
      required this.textScale,
      this.preferredCardWidth = 170,
      required super.children});

  final List<DashboardItemWidth> widths;
  final double textScale;

  /// The automatic layout adds a column as soon as cards can have this width.
  final double preferredCardWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _DashboardCardLayout(widths, textScale, preferredCardWidth);

  @override
  void updateRenderObject(
      BuildContext context, covariant _DashboardCardLayout renderObject) {
    renderObject
      ..widths = widths
      ..textScale = textScale
      ..preferredCardWidth = preferredCardWidth
      ..markNeedsLayout();
  }
}

class _DashboardCardParentData extends ContainerBoxParentData<RenderBox> {}

class _DashboardCardLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DashboardCardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DashboardCardParentData> {
  _DashboardCardLayout(this.widths, this.textScale, this.preferredCardWidth);
  List<DashboardItemWidth> widths;
  double textScale;
  double preferredCardWidth;
  static const gap = 10.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DashboardCardParentData) {
      child.parentData = _DashboardCardParentData();
    }
  }

  @override
  void performLayout() {
    final available = constraints.maxWidth;
    if (childCount == 0) {
      size = constraints.constrain(Size(available, 0));
      return;
    }
    final half = (available - gap) / 2;
    final canUseHalf = half >= 128 * textScale;
    final custom = widths.any((width) => width != DashboardItemWidth.automatic);
    final preferredColumns =
        ((available + gap) / (preferredCardWidth * textScale + gap))
            .floor()
            .clamp(1, childCount.clamp(1, 3));
    final columns = custom ? (canUseHalf ? 2 : 1) : preferredColumns;
    final automatic = (available - (columns - 1) * gap) / columns;
    final cardWidths = <double>[];
    final rows = <List<int>>[];
    var row = <int>[];
    var used = 0.0;
    void finishRow() {
      if (row.isEmpty) return;
      // An automatic card at the end of a row consumes the remaining space.
      // In particular, the third automatic card below two halves is full width.
      if (widths[row.last] == DashboardItemWidth.automatic) {
        cardWidths[row.last] += available - used;
      }
      rows.add(row);
      row = <int>[];
      used = 0;
    }

    for (var index = 0; index < childCount; index++) {
      final width = switch (widths[index]) {
        DashboardItemWidth.full => available,
        DashboardItemWidth.half => canUseHalf ? half : available,
        DashboardItemWidth.automatic => automatic,
      };
      if (row.isNotEmpty && used + gap + width > available + 0.001) {
        finishRow();
      }
      used += (row.isEmpty ? 0 : gap) + width;
      row.add(index);
      cardWidths.add(width);
    }
    finishRow();

    final boxes = getChildrenAsList();
    var y = 0.0;
    for (final indices in rows) {
      // A row is as tall as its tallest card, measured at the widths the cards
      // actually get. A shared height for the whole grid would stretch short
      // rows and leave empty space in their cards.
      var height = 0.0;
      for (final index in indices) {
        final child = boxes[index];
        child.layout(BoxConstraints.tightFor(width: cardWidths[index]),
            parentUsesSize: true);
        if (child.size.height > height) height = child.size.height;
      }
      var x = 0.0;
      for (final index in indices) {
        final child = boxes[index];
        child.layout(
            BoxConstraints.tightFor(width: cardWidths[index], height: height),
            parentUsesSize: true);
        if (child.parentData case final _DashboardCardParentData data) {
          data.offset = Offset(x, y);
        }
        x += cardWidths[index] + gap;
      }
      y += height + gap;
    }
    size = constraints.constrain(Size(available, y - gap));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
