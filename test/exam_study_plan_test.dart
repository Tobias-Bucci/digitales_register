import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  test('finds a local exam and reuses subject and title', () {
    final state = AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>([
        buildDay(
          date: UtcDateTime(2026, 4, 20),
          homework: [
            buildHomework(
              id: 7,
              title: 'Erinnerung',
              subtitle: '/exam Deutsch Mündliche Prüfung',
              type: HomeworkType.homework,
            ),
          ],
        ),
      ]);
      b.gradesState.subjects =
          ListBuilder<Subject>([buildSubject(name: 'Deutsch')]);
    });

    final assessment = examAssessments(state).single;
    expect(assessment.subject, 'Deutsch');
    expect(assessment.title, 'Mündliche Prüfung');
    expect(assessment.id, 'assessment-7');
  });

  test('plans remain before the exam and adapt to short deadlines', () {
    final assessment = ExamAssessment(
      id: 'a',
      date: UtcDateTime(2026, 4, 20),
      subject: 'Deutsch',
      title: 'Test',
      material: null,
    );
    final distant = studyPhases(assessment, DateTime(2026, 4, 1));
    final near = studyPhases(assessment, DateTime(2026, 4, 18));
    final tomorrow = studyPhases(assessment, DateTime(2026, 4, 19));

    expect(distant, hasLength(4));
    expect(distant.every((phase) => !phase.date.isAfter(DateTime(2026, 4, 20))),
        isTrue);
    expect(near, hasLength(2));
    expect(tomorrow.single.id, 'final');
    expect(tomorrow.single.date, DateTime(2026, 4, 19));
  });

  test('today and countdown labels are handled explicitly', () {
    final assessment = ExamAssessment(
      id: 'a',
      date: UtcDateTime(2026, 4, 20),
      subject: null,
      title: 'Test',
      material: null,
    );
    expect(studyPhases(assessment, DateTime(2026, 4, 20)).single.title,
        'Letzte Wiederholung');
    expect(countdownLabel(0), 'Heute');
    expect(countdownLabel(1), 'Morgen');
    expect(countdownLabel(7), 'Noch 7 Tage');
  });

  test('completed phase ids persist independently of dynamic plan dates', () {
    expect(encodeCompletedPhaseIds({'final', 'start'}), 'final,start');
  });
}
