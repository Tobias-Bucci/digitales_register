import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reserves real space outside the Navigator, including all modal routes.
/// No coach mark or navigation control can cover an application control.
class TutorialHost extends StatelessWidget {
  const TutorialHost({super.key, required this.child, required this.service});
  final Widget child;
  final TutorialService service;

  @override
  Widget build(BuildContext context) => TutorialScope(
      service: service,
      child: AnimatedBuilder(
        animation: service,
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 950;
          // The keyboard and the tutorial panel otherwise compete for the
          // same space, leaving reminder dialogs squeezed above the keyboard.
          final showPanel = service.active &&
              MediaQuery.viewInsetsOf(context).bottom == 0 &&
              !(service.suspended && service.step.key == 'deadlines');
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
          final panelSize = wide
              ? 320.0
              : (constraints.maxHeight * (largeText ? .55 : .40))
                  .clamp(160.0, 280.0)
                  .clamp(0.0, constraints.maxHeight * .65);
          final contentSize = Size(
            constraints.maxWidth - (showPanel && wide ? panelSize : 0),
            constraints.maxHeight - (showPanel && !wide ? panelSize : 0),
          );
          // Keep the Navigator at the same tree position across start/stop/resize.
          return CallbackShortcuts(
              bindings: {
                if (service.active) ...{
                  const SingleActivator(LogicalKeyboardKey.escape):
                      service.cancel,
                  const SingleActivator(LogicalKeyboardKey.arrowLeft,
                      alt: true): service.previous,
                  const SingleActivator(LogicalKeyboardKey.arrowRight,
                      alt: true): service.next,
                },
              },
              child: Flex(
                  direction: wide ? Axis.horizontal : Axis.vertical,
                  children: [
                    Expanded(
                        child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: contentSize),
                      child: child,
                    )),
                    if (showPanel)
                      SizedBox(
                        width: wide ? panelSize : null,
                        height: wide ? null : panelSize,
                        child: _TutorialPanel(service: service),
                      ),
                  ]));
        }),
      ));
}

class _TutorialPanel extends StatelessWidget {
  const _TutorialPanel({required this.service});
  final TutorialService service;
  @override
  Widget build(BuildContext context) => Material(
        elevation: 12,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Expanded(
                    child: SingleChildScrollView(
                        key: ValueKey(service.step.key),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                                header: true,
                                liveRegion: true,
                                child: Text(
                                    '${service.index + 1}/${service.length} · ${service.stepTitle()}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium)),
                            const SizedBox(height: 8),
                            Text(service.stepBody()),
                            if (service.step.requiresAction &&
                                !service.canContinue) ...[
                              const SizedBox(height: 8),
                              Text(service.text('actionHint')),
                            ],
                            if (service.suspended &&
                                !service.step.requiresAction) ...[
                              const SizedBox(height: 8),
                              Text(service.text('dialogHint')),
                            ] else if (tutorialTargets
                                    .rectFor(service.step.target) ==
                                null) ...[
                              const SizedBox(height: 8),
                              Text(service.text('unavailable')),
                            ],
                          ],
                        ))),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: service.cancel,
                        child: Text(service.text('cancel')),
                      ),
                      if (service.index > 0)
                        TextButton(
                          style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48)),
                          onPressed:
                              service.canGoBack ? service.previous : null,
                          child: Text(service.text('back')),
                        ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: service.canContinue ? service.next : null,
                        child: Text(service.text(
                            service.index + 1 == service.length
                                ? 'finish'
                                : 'next')),
                      ),
                    ],
                  ),
                ),
              ]),
            )),
      );
}

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key, required this.service});
  final TutorialService service;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: service,
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
          if (!service.active) return const SizedBox.shrink();
          final origin = tutorialTargets.boundsFor(context)?.topLeft;
          if (origin == null) return const SizedBox.shrink();
          final bounds = Offset.zero & constraints.biggest;
          final raw =
              tutorialTargets.rectFor(service.highlightTarget)?.shift(-origin);
          final hole = raw?.inflate(5).intersect(bounds);
          // Missing/hidden controls are explained without blocking exploration.
          if (hole == null || hole.isEmpty) return const SizedBox.shrink();
          return IgnorePointer(
              child: CustomPaint(
            size: constraints.biggest,
            painter:
                _SpotlightPainter(hole, Theme.of(context).colorScheme.primary),
          ));
        }),
      );
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole, this.color);
  final Rect hole;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(hole, const Radius.circular(12));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
        cutout,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.color != color;
}
