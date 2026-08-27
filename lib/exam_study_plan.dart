import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/utc_date_time.dart';

/// A view of an existing, graded dashboard entry.  It intentionally does not
/// duplicate appointments: the dashboard/calendar stay the source of truth.
class ExamAssessment {
  const ExamAssessment({
    required this.id,
    required this.date,
    required this.subject,
    required this.title,
    required this.material,
  });

  final String id;
  final UtcDateTime date;
  final String? subject;
  final String title;
  final String? material;

  int daysUntil(DateTime today) =>
      date.stripTime().difference(_date(today)).inDays;
}

class StudyPhase {
  const StudyPhase(this.id, this.title, this.date);
  final String id;
  final String title;
  final DateTime date;
}

DateTime _date(DateTime value) => DateTime(value.year, value.month, value.day);

String countdownLabel(int days) {
  if (days < 0) return 'Vergangen';
  if (days == 0) return 'Heute';
  if (days == 1) return 'Morgen';
  return 'Noch $days Tage';
}

List<ExamAssessment> examAssessments(AppState state) {
  final result = <ExamAssessment>[];
  for (final day in state.dashboardState.allDays ?? const <Day>[]) {
    for (final homework in day.homework) {
      final local = parseLocalReminderAssessment(
        homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
        state.extractAllSubjects(),
      );
      // Grade groups are the server's native model for tests and classwork.
      // Local /test, /cw and /exam reminders are projected as grade groups.
      if (local == null && homework.type != HomeworkType.gradeGroup) continue;
      final title = local?.displaySubtitle ??
          (homework.subtitle.trim().isNotEmpty
              ? homework.subtitle.trim()
              : homework.title);
      final material = local == null && homework.subtitle.trim().isNotEmpty
          ? homework.subtitle.trim()
          : null;
      result.add(ExamAssessment(
        id: 'assessment-${homework.id}',
        date: day.date,
        subject: local?.subject ?? homework.label,
        title: title,
        material: material,
      ));
    }
  }
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

/// Generates a small, date-safe plan from the currently available time.
/// Phase identifiers remain stable as the demo date changes, while dates are
/// recalculated from the appointment so a moved assessment needs no migration.
List<StudyPhase> studyPhases(ExamAssessment assessment, DateTime today) {
  final examDate = _date(assessment.date);
  final now = _date(today);
  final remaining = examDate.difference(now).inDays;
  if (remaining <= 0) {
    return [StudyPhase('final', 'Letzte Wiederholung', now)];
  }
  if (remaining == 1) {
    return [StudyPhase('final', 'Heute: finale Wiederholung', now)];
  }
  if (remaining <= 3) {
    return [
      StudyPhase('start', 'Stoff vorbereiten', now),
      StudyPhase('final', 'Finale Wiederholung',
          examDate.subtract(const Duration(days: 1))),
    ];
  }
  if (remaining <= 9) {
    return [
      StudyPhase('start', 'Vorbereitung starten', now),
      StudyPhase('deepen', 'Stoff vertiefen',
          examDate.subtract(const Duration(days: 2))),
      StudyPhase('final', 'Finale Wiederholung',
          examDate.subtract(const Duration(days: 1))),
    ];
  }
  final start = now.add(Duration(days: (remaining * .35).floor()));
  return [
    StudyPhase('start', 'Vorbereitung starten', start),
    StudyPhase('deepen', 'Stoff vertiefen',
        examDate.subtract(const Duration(days: 7))),
    StudyPhase('practice', 'Üben und Wissenslücken schließen',
        examDate.subtract(const Duration(days: 3))),
    StudyPhase('final', 'Finale Wiederholung',
        examDate.subtract(const Duration(days: 1))),
  ];
}

Set<String> completedPhaseIds(AppState state, String assessmentId) =>
    (state.settingsState.assessmentStudyProgress[assessmentId] ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toSet();

String encodeCompletedPhaseIds(Iterable<String> ids) =>
    (ids.toSet().toList()..sort()).join(',');

DateTime get studyPlanNow => appClock.now;
