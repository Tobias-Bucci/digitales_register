import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/tutorial/tutorial_target.dart';
import 'package:dr/ui/days.dart' show showEnterReminderDialog;
import 'package:flutter/material.dart';

/// A disposable exercise: never calls server actions or writes real reminders.
class TutorialPractice extends StatefulWidget {
  const TutorialPractice({super.key, this.service});
  final TutorialService? service;
  @override
  State<TutorialPractice> createState() => _TutorialPracticeState();
}

class _TutorialPracticeState extends State<TutorialPractice> {
  String? message;
  TutorialService get service => widget.service ?? tutorialService;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final tour = service;
          if (!tour.active ||
              ![
                'reminders',
                'deleteReminder',
                'assessmentShortcuts',
                'deleteAssessment'
              ].contains(tour.step.key)) {
            message = null;
            return const SizedBox.shrink();
          }
          final assessment = ['assessmentShortcuts', 'deleteAssessment']
              .contains(tour.step.key);
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tour.text('practice'),
                          style: Theme.of(context).textTheme.titleSmall),
                      if (message == null)
                        TutorialTarget(
                            id: 'tutorial-create',
                            child: IconButton(
                              tooltip: tour.text('step.reminders.title'),
                              icon: const Icon(Icons.add),
                              onPressed: () async {
                                final value = await showEnterReminderDialog(
                                    context,
                                    initialMessage:
                                        '${assessment ? '/cw ' : ''}${tour.text('example')}',
                                    tutorial: true);
                                if (!mounted || !tour.active || value == null)
                                  return;
                                setState(() => message = value);
                                tour.completeRequiredAction('tutorial-create');
                              },
                            ))
                      else
                        ListTile(
                          title: Text(message!),
                          leading: TutorialTarget(
                              id: 'tutorial-delete',
                              child: IconButton(
                                tooltip: tour.text('deleteExample'),
                                icon: const Icon(Icons.close),
                                onPressed: !tour.step.key.startsWith('delete')
                                    ? null
                                    : () {
                                        setState(() => message = null);
                                        tour.completeRequiredAction(
                                            'tutorial-delete');
                                      },
                              )),
                        ),
                    ],
                  )));
        },
      );
}
