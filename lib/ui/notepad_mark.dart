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

import 'package:dr/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// The app logo, a notepad with a check mark, drawn so that it follows the
/// theme. It doubles as the checkbox of the day list: an empty notepad is open,
/// a notepad with its notes and check mark is done.
class NotepadMark extends StatelessWidget {
  const NotepadMark({
    super.key,
    required this.checked,
    this.size = 24,
    this.outline,
    this.accent,
    this.fill,
  });

  final bool checked;
  final double size;

  /// The notepad; defaults to the text colour.
  final Color? outline;

  /// The binding and check mark; defaults to the success colour.
  final Color? accent;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: checked ? 1 : 0),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => CustomPaint(
        size: Size.square(size),
        painter: NotepadPainter(
          progress: progress,
          outline: outline ?? scheme.onSurface,
          accent: accent ?? scheme.success,
          fill: fill ?? Colors.transparent,
        ),
      ),
    );
  }
}

/// Draws the notepad on the 512-unit grid of the launcher icon.
class NotepadPainter extends CustomPainter {
  const NotepadPainter({
    required this.progress,
    required this.outline,
    required this.accent,
    required this.fill,
  });

  /// How much of the notes and the check mark is drawn, from 0 to 1.
  final double progress;
  final Color outline;
  final Color accent;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    final page = RRect.fromLTRBR(56, 56, 456, 456, const Radius.circular(66));
    canvas.drawRRect(page, Paint()..color = fill);
    canvas.drawRRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34
        ..color = outline,
    );
    final binding = Paint()..color = accent;
    for (final top in const [148.0, 210.0, 272.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(24, top, 72, top + 28, const Radius.circular(8)),
        binding,
      );
    }
    if (progress > 0) {
      final notes = Paint()
        ..color = outline.withValues(alpha: 0.4 * progress)
        ..strokeWidth = 24
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(const Offset(132, 163), const Offset(294, 163), notes)
        ..drawLine(const Offset(132, 203), const Offset(248, 203), notes);
      final check = Path()
        ..moveTo(136, 306)
        ..lineTo(200, 368)
        ..lineTo(388, 184);
      final metric = check.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 50
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NotepadPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.outline != outline ||
      oldDelegate.accent != accent ||
      oldDelegate.fill != fill;
}
