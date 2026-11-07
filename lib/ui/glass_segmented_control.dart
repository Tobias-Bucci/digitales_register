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

import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';

/// One choice of a [GlassSegmentedControl]. [label] is what fits, [fullLabel]
/// what a tooltip and a screen reader say.
@immutable
class GlassSegment<T> {
  const GlassSegment({
    required this.value,
    required this.label,
    required this.fullLabel,
  });

  final T value;
  final String label, fullLabel;
}

/// A choice between a few values on a track of glass. The selected one has the
/// lens of the navigation, which glides over to it. All segments are as wide as
/// the widest one.
class GlassSegmentedControl<T> extends StatelessWidget {
  const GlassSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  /// The touch target, the track is a little lower.
  static const double height = 48;
  static const double _trackInset = 5;
  static const double _lensInset = 2;
  static const double _minSegmentWidth = 44;

  final List<GlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final index = segments.indexWhere((s) => s.value == selected);
    final track = DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.onSurface.withValues(alpha: highContrast ? 0 : 0.06),
        shape: StadiumBorder(
          side: highContrast
              ? BorderSide(color: scheme.outline)
              : BorderSide.none,
        ),
      ),
      child: const SizedBox.expand(),
    );
    return IntrinsicWidth(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              top: _trackInset,
              bottom: _trackInset,
              child: GlassEdge(
                shape: const StadiumBorder(),
                sheen: false,
                child: track,
              ),
            ),
            if (index >= 0)
              Positioned.fill(
                top: _trackInset + _lensInset,
                bottom: _trackInset + _lensInset,
                child: AnimatedAlign(
                  key: const Key('glass-segment-lens'),
                  alignment: Alignment(
                    segments.length == 1
                        ? 0
                        : -1 + 2 * index / (segments.length - 1),
                    0,
                  ),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: FractionallySizedBox(
                    widthFactor: 1 / segments.length,
                    heightFactor: 1,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: _lensInset),
                      child: GlassLens(),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final segment in segments)
                  Expanded(
                    child: _Segment(
                      key: ValueKey('glass-segment-${segment.value}'),
                      label: segment.label,
                      fullLabel: segment.fullLabel,
                      selected: segment.value == selected,
                      onPressed: () {
                        if (segment.value != selected) {
                          onChanged(segment.value);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.fullLabel,
    required this.selected,
    required this.onPressed,
  });

  final String label, fullLabel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false, _hovered = false;

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
    ButtonActivateIntent:
        CallbackAction<ButtonActivateIntent>(onInvoke: _activate),
  };

  void _activate(Intent _) => widget.onPressed();

  void _tap() {
    Feedback.forTap(context);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: widget.fullLabel,
      child: Tooltip(
        message: widget.fullLabel,
        excludeFromSemantics: true,
        child: FocusableActionDetector(
          actions: _actions,
          mouseCursor: NewDesignTheme.clickCursor,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: GlassSegmentedControl._trackInset +
                    GlassSegmentedControl._lensInset,
                horizontal: GlassSegmentedControl._lensInset,
              ),
              child: CustomPaint(
                painter: _focused || _hovered
                    ? GlassFocusRingPainter(
                        shape: const StadiumBorder(),
                        ring: _focused ? navigationFocusRing(scheme) : null,
                        tint: navigationHoverTint(scheme, onLens: selected),
                      )
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: GlassSegmentedControl._minSegmentWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
