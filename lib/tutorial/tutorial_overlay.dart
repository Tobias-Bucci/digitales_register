import 'dart:math' as math;

import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key, required this.service});
  final TutorialService service;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final screen = MediaQuery.sizeOf(context);
          final raw = tutorialTargets.rectFor(service.step.target);
          Rect? target;
          if (raw != null && raw.bottom > 0 && raw.top < screen.height) {
            final left = math.max(8.0, raw.left - 6);
            final top = math.max(8.0, raw.top - 6);
            final right = math.min(screen.width - 8, raw.right + 6);
            final bottom = math.min(screen.height - 8, raw.bottom + 6);
            if (right > left && bottom > top) {
              target = Rect.fromLTRB(left, top, right, bottom);
            }
          }
          final cardWidth = math.min(420.0, screen.width - 24);
          final preferBelow =
              target == null || target.center.dy < screen.height * .45;
          final top = target == null
              ? math.max(72.0, screen.height * .22)
              : preferBelow
                  ? math.min(target.bottom + 12, screen.height - 270)
                  : math.max(16, target.top - 210);
          return Material(
            color: Colors.transparent,
            child: Stack(children: [
              ..._barriers(screen, target),
              if (target != null)
                Positioned.fromRect(
                  rect: target,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3),
                        boxShadow: [
                          BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .35),
                              blurRadius: 18)
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                top: top.toDouble(),
                left: (screen.width - cardWidth) / 2,
                width: cardWidth,
                child: Card(
                  elevation: 12,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            CircleAvatar(
                                radius: 16,
                                child: Text('${service.index + 1}')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(service.stepTitle(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700))),
                          ]),
                          const SizedBox(height: 10),
                          Text(service.stepBody()),
                          if (service.step.requiresAction &&
                              !service.canContinue) ...[
                            const SizedBox(height: 10),
                            Text(service.text('actionHint'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)),
                          ],
                        ]),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: Row(children: [
                    TextButton.icon(
                        onPressed: service.cancel,
                        icon: const Icon(Icons.close),
                        label: Text(service.text('cancel'))),
                    const Spacer(),
                    Text('${service.index + 1}/${service.length}',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: service.canContinue ? service.next : null,
                      label: Text(service.index + 1 == service.length
                          ? service.text('finish')
                          : service.text('next')),
                      icon: Icon(service.index + 1 == service.length
                          ? Icons.check
                          : Icons.arrow_forward),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      );

  List<Widget> _barriers(Size size, Rect? hole) {
    const color = Color(0xB8000000);
    Widget part(double left, double top, double width, double height) =>
        Positioned(
          left: left,
          top: top,
          width: math.max(0, width),
          height: math.max(0, height),
          child: const ColoredBox(color: color),
        );
    if (hole == null) {
      return [const Positioned.fill(child: ColoredBox(color: color))];
    }
    return [
      part(0, 0, size.width, hole.top),
      part(0, hole.bottom, size.width, size.height - hole.bottom),
      part(0, hole.top, hole.left, hole.height),
      part(hole.right, hole.top, size.width - hole.right, hole.height),
    ];
  }
}
