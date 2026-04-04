// Copyright (C) 2026 Tobias Bucci

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;

final UtcDateTime fixtureNow = UtcDateTime(2026, 3, 28, 12);

Homework buildHomework({
  int id = 1,
  String title = 'Titel',
  String subtitle = 'Untertitel',
  String? label,
  HomeworkType type = HomeworkType.lessonHomework,
  bool checkable = false,
  bool checked = false,
  bool deleteable = false,
  bool deleted = false,
  bool warning = false,
  bool isNew = false,
  bool isChanged = false,
  String? grade,
  String? gradeFormatted,
  UtcDateTime? firstSeen,
  UtcDateTime? lastNotSeen,
  List<GradeGroupSubmission>? submissions,
}) {
  return Homework(
    (b) => b
      ..id = id
      ..title = title
      ..subtitle = subtitle
      ..label = label
      ..type = type
      ..checkable = checkable
      ..checked = checked
      ..deleteable = deleteable
      ..deleted = deleted
      ..warning = warning
      ..isNew = isNew
      ..isChanged = isChanged
      ..grade = grade
      ..gradeFormatted = gradeFormatted
      ..firstSeen = firstSeen ?? fixtureNow
      ..lastNotSeen = lastNotSeen ?? fixtureNow
      ..gradeGroupSubmissions = submissions == null
          ? null
          : ListBuilder<GradeGroupSubmission>(submissions),
  );
}

Day buildDay({
  required UtcDateTime date,
  List<Homework> homework = const <Homework>[],
  List<Homework> deletedHomework = const <Homework>[],
  UtcDateTime? lastRequested,
}) {
  return Day(
    (b) => b
      ..date = date
      ..homework = ListBuilder<Homework>(homework)
      ..deletedHomework = ListBuilder<Homework>(deletedHomework)
      ..lastRequested = lastRequested ?? fixtureNow,
  );
}

Notification buildNotification({
  int id = 1,
  String title = 'Benachrichtigung',
  String? subTitle,
  String? type,
  int? objectId,
  UtcDateTime? timeSent,
}) {
  return Notification(
    (b) => b
      ..id = id
      ..title = title
      ..subTitle = subTitle
      ..type = type
      ..objectId = objectId
      ..timeSent = timeSent ?? fixtureNow,
  );
}

Message buildMessage({
  int id = 25,
  String subject = 'Betreff',
  String fromName = 'Sender',
  String recipient = 'Empfänger',
  String? text,
  List<MessageAttachmentFile> attachments = const <MessageAttachmentFile>[],
  UtcDateTime? timeSent,
}) {
  return Message(
    (b) => b
      ..id = id
      ..subject = subject
      ..fromName = fromName
      ..recipientString = recipient
      ..text = text ??
          '{"ops":[{"insert":"Sehr geehrte Eltern,\\nliebe Schülerinnen und Schüler\\n"}]}'
      ..attachments = ListBuilder<MessageAttachmentFile>(attachments)
      ..timeSent = timeSent ?? fixtureNow,
  );
}

MessageAttachmentFile buildAttachment({
  int id = 12,
  int messageId = 25,
  String originalName = 'Bild.png',
  String file = 'attachment.png',
  bool downloading = false,
  bool fileAvailable = false,
}) {
  return MessageAttachmentFile(
    (b) => b
      ..id = id
      ..messageId = messageId
      ..originalName = originalName
      ..file = file
      ..downloading = downloading
      ..fileAvailable = fileAvailable,
  );
}

Subject buildSubject({
  int? id,
  required String name,
  Map<Semester, BuiltList<GradeAll>>? gradesAll,
  Map<Semester, BuiltList<GradeDetail>>? grades,
  Map<Semester, BuiltList<Observation>>? observations,
}) {
  return Subject(
    (b) => b
      ..id = id
      ..name = name
      ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>(
        gradesAll ?? const <Semester, BuiltList<GradeAll>>{},
      )
      ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>(
        grades ?? const <Semester, BuiltList<GradeDetail>>{},
      )
      ..observations = MapBuilder<Semester, BuiltList<Observation>>(
        observations ?? const <Semester, BuiltList<Observation>>{},
      ),
  );
}

GradeAll buildGradeAll({
  required UtcDateTime date,
  required int grade,
  String type = 'Schularbeit',
  int weightPercentage = 100,
  bool cancelled = false,
}) {
  return GradeAll(
    (b) => b
      ..date = date
      ..grade = grade
      ..type = type
      ..weightPercentage = weightPercentage
      ..cancelled = cancelled,
  );
}

GradeDetail buildGradeDetail({
  required int id,
  required UtcDateTime date,
  required int grade,
  String name = 'Note',
  String type = 'Schularbeit',
  String created = 'erstellt',
  List<Competence> competences = const <Competence>[],
}) {
  return GradeDetail(
    (b) => b
      ..id = id
      ..date = date
      ..grade = grade
      ..name = name
      ..type = type
      ..created = created
      ..cancelled = false
      ..weightPercentage = 100
      ..competences = ListBuilder<Competence>(competences),
  );
}

Competence buildCompetence({
  required String typeName,
  required int grade,
}) {
  return Competence(
    (b) => b
      ..typeName = typeName
      ..grade = grade,
  );
}

Observation buildObservation({
  required String typeName,
  required UtcDateTime date,
  String created = 'Erstellt',
  String? note,
}) {
  return Observation(
    (b) => b
      ..typeName = typeName
      ..date = date
      ..created = created
      ..note = note
      ..cancelled = false,
  );
}

CalendarHour buildCalendarHour({
  required String subject,
  int fromHour = 1,
  int toHour = 1,
  List<String> rooms = const <String>[],
  List<Teacher> teachers = const <Teacher>[],
  List<TimeSpan> timeSpans = const <TimeSpan>[],
  List<HomeworkExam> homeworkExams = const <HomeworkExam>[],
  List<LessonContent> lessonContents = const <LessonContent>[],
}) {
  return CalendarHour(
    (b) => b
      ..subject = subject
      ..fromHour = fromHour
      ..toHour = toHour
      ..rooms = ListBuilder<String>(rooms)
      ..teachers = ListBuilder<Teacher>(teachers)
      ..timeSpans = ListBuilder<TimeSpan>(timeSpans)
      ..homeworkExams = ListBuilder<HomeworkExam>(homeworkExams)
      ..lessonContents = ListBuilder<LessonContent>(lessonContents),
  );
}

CalendarDay buildCalendarDay({
  required UtcDateTime date,
  List<CalendarHour> hours = const <CalendarHour>[],
}) {
  return CalendarDay(
    (b) => b
      ..date = date
      ..hours = ListBuilder<CalendarHour>(hours)
      ..lastFetched = fixtureNow,
  );
}

Teacher buildTeacher({
  String? firstName,
  String? lastName,
}) {
  return Teacher(
    (b) => b
      ..firstName = firstName
      ..lastName = lastName,
  );
}

TimeSpan buildTimeSpan({
  required UtcDateTime from,
  required UtcDateTime to,
}) {
  return TimeSpan(
    (b) => b
      ..from = from
      ..to = to,
  );
}

HomeworkExam buildHomeworkExam({
  int id = 5,
  String name = 'Hausaufgabe',
  String typeName = 'Hausaufgabe',
  bool homework = true,
  bool warning = false,
  bool online = false,
  bool hasGrades = false,
  bool hasGradeGroupSubmissions = false,
  UtcDateTime? deadline,
}) {
  return HomeworkExam(
    (b) => b
      ..id = id
      ..name = name
      ..typeId = id
      ..typeName = typeName
      ..homework = homework
      ..warning = warning
      ..online = online
      ..hasGrades = hasGrades
      ..hasGradeGroupSubmissions = hasGradeGroupSubmissions
      ..deadline = deadline ?? fixtureNow,
  );
}

LessonContentSubmission buildLessonContentSubmission({
  required UtcDateTime date,
  String id = 'submission-1',
  String lessonContentId = 'content-1',
  String originalName = 'Datei.pdf',
  bool downloading = false,
  bool fileAvailable = false,
}) {
  return LessonContentSubmission(
    (b) => b
      ..id = id
      ..lessonContentId = lessonContentId
      ..originalName = originalName
      ..type = 'file'
      ..date = date
      ..downloading = downloading
      ..fileAvailable = fileAvailable,
  );
}

LessonContent buildLessonContent({
  String name = 'Unterrichtsmaterial',
  String typeName = 'Datei',
  List<LessonContentSubmission> submissions = const <LessonContentSubmission>[],
}) {
  return LessonContent(
    (b) => b
      ..name = name
      ..typeName = typeName
      ..submissions = ListBuilder<LessonContentSubmission>(submissions),
  );
}

AppState buildStateWithSubjects({
  List<String> subjects = const <String>['Fach1'],
  List<String> favoriteSubjects = const <String>[],
}) {
  return AppState(
    (b) {
      b.gradesState.subjects = ListBuilder<Subject>(
        subjects
            .map(
              (subject) => buildSubject(name: subject),
            )
            .toList(),
      );
      b.settingsState.favoriteSubjects = ListBuilder<String>(favoriteSubjects);
    },
  );
}

AppState buildGradesPageState({
  bool loading = false,
  List<String> favoriteSubjects = const <String>[],
}) {
  return AppState(
    (b) {
      b.gradesState
        ..loading = loading
        ..semester = Semester.first.toBuilder()
        ..subjects = ListBuilder<Subject>(<Subject>[
          buildSubject(
            name: 'Fach1',
            gradesAll: <Semester, BuiltList<GradeAll>>{
              Semester.first: BuiltList<GradeAll>(<GradeAll>[
                buildGradeAll(
                  date: UtcDateTime(2021, 1, 2),
                  grade: 775,
                  type: 'Schularbeit1',
                ),
                buildGradeAll(
                  date: UtcDateTime(2021, 1, 3),
                  grade: 750,
                  type: 'Schularbeit2',
                ),
                buildGradeAll(
                  date: UtcDateTime(2021, 1, 4),
                  grade: 725,
                  type: 'Schularbeit3',
                ),
              ]),
            },
            grades: <Semester, BuiltList<GradeDetail>>{
              Semester.first: BuiltList<GradeDetail>(<GradeDetail>[
                buildGradeDetail(
                  id: 0,
                  date: UtcDateTime(2021, 1, 2),
                  grade: 775,
                  name: 'Erste Schularbeit',
                  type: 'Schularbeit1',
                  created: 'am 3. 2. erstellt',
                ),
                buildGradeDetail(
                  id: 1,
                  date: UtcDateTime(2021, 1, 3),
                  grade: 750,
                  name: 'Zweite Schularbeit',
                  type: 'Schularbeit2',
                  created: 'am 4. 2. erstellt',
                ),
                buildGradeDetail(
                  id: 2,
                  date: UtcDateTime(2021, 1, 4),
                  grade: 725,
                  name: 'Dritte Schularbeit',
                  type: 'Schularbeit3',
                  created: 'am 5. 2. erstellt',
                  competences: <Competence>[
                    buildCompetence(typeName: 'Kompetenz1', grade: 3),
                  ],
                ),
              ]),
            },
            observations: <Semester, BuiltList<Observation>>{
              Semester.first: BuiltList<Observation>(<Observation>[
                buildObservation(
                  typeName: 'Beobachtung',
                  date: UtcDateTime(2021, 2, 21),
                  created: 'Am 3. März 2021',
                  note: 'Notiz blabla bla',
                ),
              ]),
            },
          ),
          buildSubject(
            name: 'Fach2',
            gradesAll: <Semester, BuiltList<GradeAll>>{
              Semester.first: BuiltList<GradeAll>(<GradeAll>[
                buildGradeAll(
                  date: UtcDateTime(2021, 1, 2),
                  grade: 400,
                  type: 'Test',
                  weightPercentage: 25,
                ),
              ]),
            },
            observations: <Semester, BuiltList<Observation>>{
              Semester.first: BuiltList<Observation>(),
            },
          ),
        ]);
      b.settingsState
        ..favoriteSubjects = ListBuilder<String>(favoriteSubjects)
        ..subjectThemes = MapBuilder<String, SubjectTheme>(<String, SubjectTheme>{
          'Fach1': SubjectTheme(
            (b) => b
              ..color = Colors.red.toARGB32()
              ..thick = 5,
          ),
          'Fach2': SubjectTheme(
            (b) => b
              ..color = Colors.green.toARGB32()
              ..thick = 4,
          ),
        });
    },
  );
}
