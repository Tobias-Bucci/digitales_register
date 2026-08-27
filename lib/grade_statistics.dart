import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';

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
  final asOf = now ?? appClock.now;
  final ignored = ignoredSubjects.map((s) => s.toLowerCase()).toSet();
  final averages = <SubjectStatistic>[];
  for (final subject in subjects) {
    if (ignored.contains(subject.name.toLowerCase())) {
      continue;
    }
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
    if (weight > 0) averages.add(SubjectStatistic(subject.name, sum / weight));
  }
  averages.sort((a, b) => b.average.compareTo(a.average));
  return GradeStatistics(averages);
}
