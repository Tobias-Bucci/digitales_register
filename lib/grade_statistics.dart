import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_date.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_average.dart';

class SubjectStatistic {
  const SubjectStatistic(this.name, this.average);
  final String name;
  final double average;
}

class GradeStatistics {
  const GradeStatistics(this.subjectAverages);
  final List<SubjectStatistic> subjectAverages;
}

GradeStatistics calculateGradeStatistics({
  required Iterable<Subject> subjects,
  required Semester semester,
  required Iterable<String> ignoredSubjects,
  DateTime? now,
}) {
  final asOf = calendarDate(now ?? appClock.now);
  final ignored = ignoredSubjects.map((s) => s.toLowerCase()).toSet();
  final averages = <SubjectStatistic>[];
  for (final subject in subjects) {
    if (ignored.contains(subject.name.toLowerCase())) {
      continue;
    }
    final average = weightedGradeAverage(
      (subject.basicGrades(semester) ?? const <GradeAll>[])
          .where((grade) => !calendarDate(grade.date).isAfter(asOf)),
    );
    if (average != null) {
      averages.add(SubjectStatistic(subject.name, average.toDouble()));
    }
  }
  averages.sort((a, b) => b.average.compareTo(a.average));
  return GradeStatistics(averages);
}
