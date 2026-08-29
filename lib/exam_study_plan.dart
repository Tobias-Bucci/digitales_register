import 'dart:convert';

import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

/// A view of an existing, graded dashboard entry.  It intentionally does not
/// duplicate appointments: the dashboard/calendar stay the source of truth.
class ExamAssessment {
  const ExamAssessment({
    required this.id,
    required this.date,
    required this.subject,
    required this.title,
    required this.material,
    this.type,
  });

  final String id;
  final UtcDateTime date;
  final String? subject;
  final String title;
  final String? material;
  final String? type;

  int daysUntil(DateTime today) =>
      date.stripTime().difference(_date(today)).inDays;
}

class StudyPhase {
  const StudyPhase(
    this.id,
    this.title,
    this.date, {
    this.effort = 'Mittel',
    this.durationDays = 1,
  });
  final String id;
  final String title;
  final DateTime date;
  final String effort;
  final int durationDays;

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'effort': effort,
        'durationDays': durationDays,
      };
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
        type: local?.serverTypeName ?? homework.title.trim(),
      ));
    }
  }
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

/// Returns the ungraded assessment opportunities from the exam calendar that
/// belong to [subject]. Dates are compared as calendar dates so an assessment
/// scheduled for today is never accidentally treated as a future assessment
/// because of a time-zone or time-of-day difference.
List<ExamAssessment> upcomingExamAssessmentsForSubject(
  AppState state,
  Subject subject,
  DateTime today,
) {
  final todayDate = DateTime(today.year, today.month, today.day);
  final seenIds = <String>{};
  return examAssessments(state).where((assessment) {
    final assessmentSubject = assessment.subject;
    final assessmentDate = DateTime(
      assessment.date.year,
      assessment.date.month,
      assessment.date.day,
    );
    return assessmentSubject != null &&
        equalsIgnoreCase(assessmentSubject, subject.name) &&
        assessmentDate.isAfter(todayDate) &&
        seenIds.add(assessment.id);
  }).toList(growable: false);
}

/// Generates a small, date-safe plan from the currently available time.
/// Phase identifiers remain stable as the demo date changes, while dates are
/// recalculated from the appointment so a moved assessment needs no migration.
List<StudyPhase> studyPhases(
  ExamAssessment assessment,
  DateTime today, {
  String? customPhases,
}) {
  final savedPhases = decodeStudyPhases(customPhases);
  // Once the user has saved a plan, it always wins over the generated plan.
  // This also preserves the deliberate choice to remove every phase (`[]`).
  if (customPhases != null) return savedPhases;
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

List<StudyPhase> decodeStudyPhases(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const <StudyPhase>[];
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const <StudyPhase>[];
    return decoded
        .whereType<Map>()
        .map((value) {
          final id = value['id'];
          final title = value['title'];
          final date = DateTime.tryParse(value['date']?.toString() ?? '');
          if (id is! String || title is! String || date == null) return null;
          return StudyPhase(
            id,
            title,
            _date(date),
            effort: value['effort'] is String
                ? value['effort'] as String
                : 'Mittel',
            durationDays: value['durationDays'] is int
                ? (value['durationDays'] as int).clamp(1, 30)
                : 1,
          );
        })
        .whereType<StudyPhase>()
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  } catch (_) {
    return const <StudyPhase>[];
  }
}

String encodeStudyPhases(Iterable<StudyPhase> phases) =>
    jsonEncode(phases.map((phase) => phase.toJson()).toList());

Set<String> completedPhaseIds(AppState state, String assessmentId) =>
    (state.settingsState.assessmentStudyProgress[assessmentId] ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toSet();

String encodeCompletedPhaseIds(Iterable<String> ids) =>
    (ids.toSet().toList()..sort()).join(',');

DateTime get studyPlanNow => appClock.now;
