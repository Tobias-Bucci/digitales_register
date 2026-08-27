import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';

class GradeHistorySubjectComparison {
  const GradeHistorySubjectComparison({
    required this.subject,
    required this.current,
    required this.previous,
  });

  final String subject;
  final double current;
  final double previous;
  double get change => current - previous;
}

class GradeHistoryComparison {
  const GradeHistoryComparison({
    required this.currentSemester,
    required this.previousSemester,
    required this.currentAverage,
    required this.previousAverage,
    required this.subjects,
  });

  final Semester currentSemester;
  final Semester previousSemester;
  final double? currentAverage;
  final double? previousAverage;
  final List<GradeHistorySubjectComparison> subjects;
  double? get change => currentAverage != null && previousAverage != null
      ? currentAverage! - previousAverage!
      : null;
}

GradeHistoryComparison? compareGradeSemesters({
  required Iterable<Subject> subjects,
  required Semester currentSemester,
  required Semester previousSemester,
  required Iterable<String> ignoredSubjects,
  DateTime? now,
}) {
  final asOf = _dateOnly(now ?? appClock.now);
  final ignored = ignoredSubjects.map((s) => s.toLowerCase()).toSet();
  final current = _averagesBySubject(subjects, currentSemester, asOf, ignored);
  final previous =
      _averagesBySubject(subjects, previousSemester, asOf, ignored);
  if (current.isEmpty && previous.isEmpty) return null;
  final shared = current.keys
      .where(previous.containsKey)
      .map((name) => GradeHistorySubjectComparison(
            subject: name,
            current: current[name]!,
            previous: previous[name]!,
          ))
      .toList()
    ..sort(
        (a, b) => a.subject.toLowerCase().compareTo(b.subject.toLowerCase()));
  return GradeHistoryComparison(
    currentSemester: currentSemester,
    previousSemester: previousSemester,
    currentAverage: _mean(current.values),
    previousAverage: _mean(previous.values),
    subjects: shared,
  );
}

Map<String, double> _averagesBySubject(
  Iterable<Subject> subjects,
  Semester semester,
  DateTime asOf,
  Set<String> ignored,
) {
  final result = <String, double>{};
  for (final subject in subjects) {
    if (ignored.contains(subject.name.toLowerCase())) continue;
    var sum = 0;
    var weight = 0;
    for (final grade in subject.basicGrades(semester) ?? const <GradeAll>[]) {
      if (grade.grade == null || grade.cancelled || grade.date.isAfter(asOf)) {
        continue;
      }
      final gradeWeight =
          grade.weightPercentage > 0 ? grade.weightPercentage : 1;
      sum += grade.grade! * gradeWeight;
      weight += gradeWeight;
    }
    if (weight > 0) result[subject.name] = sum / weight;
  }
  return result;
}

double? _mean(Iterable<double> values) {
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
