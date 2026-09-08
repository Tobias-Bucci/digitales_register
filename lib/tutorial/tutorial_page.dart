import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('tutorial.settings.title'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.text('tutorial.settings.fullTitle'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(l10n.text('tutorial.settings.fullBody')),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => tutorialService.startAll(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.text('tutorial.settings.startAll')),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.text('tutorial.settings.chapters'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final chapter in TutorialChapter.values)
          Card(
            child: ListTile(
              leading: Icon(_icon(chapter)),
              title: Text(l10n.text('tutorial.chapter.${chapter.name}')),
              trailing: FutureBuilder<bool>(
                future: tutorialService.isChapterCompleted(chapter),
                builder: (_, snapshot) => Icon(
                  snapshot.data == true
                      ? Icons.check_circle_rounded
                      : Icons.play_circle_outline,
                  color: snapshot.data == true
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              onTap: () => tutorialService.startChapter(context, chapter),
            ),
          ),
      ]),
    );
  }

  IconData _icon(TutorialChapter chapter) => switch (chapter) {
        TutorialChapter.dashboard => Icons.dashboard_outlined,
        TutorialChapter.grades => Icons.auto_graph_outlined,
        TutorialChapter.absences => Icons.event_busy_outlined,
        TutorialChapter.calendar => Icons.calendar_month_outlined,
        TutorialChapter.exams => Icons.school_outlined,
        TutorialChapter.other => Icons.apps_outlined,
      };
}
