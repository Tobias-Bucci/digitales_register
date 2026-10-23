import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/export/export_csv.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/export/export_pdf.dart';
import 'package:dr/export/export_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/utc_date_time.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

AppState exportFixture() {
  final subject = buildSubject(name: 'Mathematik', gradesAll: {
    Semester.first: BuiltList([
      buildGradeAll(
          date: UtcDateTime(2025, 10, 10), grade: 625, weightPercentage: 25),
      buildGradeAll(
          date: UtcDateTime(2025, 11, 10), grade: 875, weightPercentage: 75),
      buildGradeAll(
          date: UtcDateTime(2025, 12, 10), grade: 1000, cancelled: true),
    ]),
    Semester.second: BuiltList([
      buildGradeAll(date: UtcDateTime(2026, 3, 10), grade: 700),
      buildGradeAll(date: UtcDateTime(2024, 3, 10), grade: 400),
    ]),
  });
  final day = buildCalendarDay(date: fixtureNow, hours: [
    buildCalendarHour(subject: 'Mathematik', rooms: [
      'A1'
    ], timeSpans: [
      buildTimeSpan(
          from: UtcDateTime(2026, 3, 28, 8), to: UtcDateTime(2026, 3, 28, 9))
    ], homeworkExams: [
      buildHomeworkExam(id: 1, homework: false, name: 'Prüfung'),
      buildHomeworkExam(id: 2, homework: true, name: 'Aufgabe')
    ], lessonContents: [
      buildLessonContent(name: 'Gleichungen')
    ]),
  ]);
  return AppState((b) => b
    ..loginState.username = 'student'
    ..loginState.loggedIn = true
    ..gradesState.subjects.replace([subject])
    ..calendarState.days.replace({day.date: day})
    ..messagesState.messages.replace([
      buildMessage(subject: 'Grüße & città', attachments: [buildAttachment()])
    ])
    ..certificateState.html =
        '<h1>Schuljahr 2025/2026</h1><p>1. Semester</p><table><tr><th>Fach</th><th>Bewertung</th></tr><tr><td>Mathematik</td><td>8</td></tr></table>'
    ..absencesState.absences.replace([
      AbsenceGroup((g) => g
        ..date = fixtureNow
        ..hours = 1
        ..minutes = 10
        ..justified = AbsenceJustified.justified
        ..absences.replace([
          Absence((a) => a
            ..date = fixtureNow
            ..hour = 1
            ..minutes = 10
            ..minutesCameTooLate = 0
            ..minutesLeftTooEarly = 0)
        ]))
    ]));
}

class _Picker extends FilePickerPlatform {
  Uint8List? received;
  String? name;
  String? result = '/chosen/export.pdf';
  bool fail = false;
  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    received = bytes;
    name = fileName;
    if (fail) throw const FileSystemException('unavailable');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations de;
  setUpAll(() async {
    de = await AppLocalizations.load(const Locale('de'));
    await initializeDateFormatting('de');
  });

  test(
      'all eight categories project real model data and keep the store immutable',
      () {
    final state = exportFixture();
    final source = ExportDataSource(state);
    for (final category in ExportCategory.values) {
      expect(source.records(category), isNotEmpty, reason: category.name);
    }
    expect(source.records(ExportCategory.messages).single.body,
        contains('Sehr geehrte Eltern'));
    expect(source.records(ExportCategory.messages).single.body,
        isNot(contains('"ops"')));
    expect(
        source.records(ExportCategory.timetable).single.fields['room'], 'A1');
    expect(
        source.records(ExportCategory.absences).single.fields['minutes'], '10');
    expect(
        source.records(ExportCategory.certificates).single.tables.single.last,
        ['Mathematik', '8']);
    expect(state.gradesState.subjects.single.basicGrades(Semester.all),
        hasLength(5));
  });

  test(
      'weighted averages, cancellation, semester, year, dates and IDs use app rules',
      () {
    final state = exportFixture();
    final source = ExportDataSource(state);
    final first = source.section(ExportCategory.grades,
        ExportFilter(schoolYear: 2025, semester: Semester.first));
    expect(first.records, hasLength(3));
    expect(first.averages['Mathematik'], 813);
    expect(first.overallAverage, 8.13);
    expect(first.averages['Mathematik'],
        state.gradesState.subjects.single.average(Semester.first));
    final range = source.section(
        ExportCategory.grades,
        ExportFilter(
            from: DateTime(2025, 10, 10),
            until: DateTime(2025, 10, 10),
            ids: {first.records.first.id}));
    expect(range.records, hasLength(1));
    expect(range.averages['Mathematik'], 625);
    expect(
        source
            .section(ExportCategory.grades,
                const ExportFilter(subject: 'Nonexistent'))
            .records,
        isEmpty);
    expect(source.schoolYears([ExportCategory.grades]), [2025, 2023]);
    expect(
        source
            .section(
                ExportCategory.grades, const ExportFilter(schoolYear: 2023))
            .averages['Mathematik'],
        400);
    expect(state.gradesState.semester, Semester.all);
  });

  test('ignored subjects and missing numeric grades are not invented', () {
    final state = exportFixture().rebuild(
        (b) => b.settingsState.ignoreForGradesAverage.replace(['mathematik']));
    final section = ExportDataSource(state)
        .section(ExportCategory.grades, const ExportFilter());
    expect(section.overallAverage, isNull);
    final missing = buildSubject(name: 'Missing', gradesAll: {
      Semester.first: BuiltList([
        GradeAll((b) => b
          ..date = fixtureNow
          ..type = 'Observation'
          ..cancelled = false
          ..weightPercentage = 100),
      ])
    });
    final empty = ExportDataSource(
            state.rebuild((b) => b.gradesState.subjects.replace([missing])))
        .section(ExportCategory.grades, const ExportFilter());
    expect(empty.averages['Missing'], isNull);
    expect(empty.records.single.fields['grade'], '');
  });

  test('calendar assessments spanning lessons are exported once', () {
    final state = exportFixture();
    final day = state.calendarState.days.values.single;
    final duplicated = day.rebuild((b) => b.hours.add(day.hours.single));
    final source = ExportDataSource(
        state.rebuild((b) => b.calendarState.days[day.date] = duplicated));
    expect(source.records(ExportCategory.exams), hasLength(1));
    expect(source.records(ExportCategory.tasks), hasLength(1));
    expect(source.records(ExportCategory.timetable), hasLength(2));
  });

  test(
      'HTML and Delta extraction preserves meaningful content without scripts or media fetches',
      () {
    expect(
        readableHtml(
            '<p>Grüße &amp; città<br>riga 2</p><script>secret()</script><img src="https://tracking.invalid">'),
        'Grüße & città\nriga 2');
    expect(
        readableMessage(
            r'{"ops":[{"insert":"Hallo\n"},{"insert":{"image":"https://tracking.invalid"}},{"insert":"città"}]}'),
        'Hallo\ncittà');
    expect(readableMessage('plain\ntext'), 'plain\ntext');
    expect(readableMessage('{invalid JSON'), '{invalid JSON');
  });

  test(
      'CSV uses BOM, semicolon, CRLF, quoting, decimals and formula neutralization',
      () {
    final section = ExportSection(ExportCategory.messages, [
      ExportRecord(
          id: '1',
          title: 'Grüße; "città"',
          fields: const {'sender': ' =HYPERLINK("bad")'},
          body: 'line 1\nline 2')
    ]);
    final bytes = createExportCsv(section, de);
    expect(bytes.take(3), [239, 187, 191]);
    final text = utf8.decode(bytes);
    expect(text, contains('"Grüße; ""città"""'));
    expect(text, contains('"\' =HYPERLINK(""bad"")"'));
    expect(text, contains('"line 1\nline 2"\r\n'));
    final grades = utf8.decode(createExportCsv(
        ExportDataSource(exportFixture()).section(
            ExportCategory.grades, ExportFilter(semester: Semester.first)),
        de));
    expect(grades, contains('"6,25"'));
    expect(grades, contains('"8,13"'));
  });

  for (final locale in AppLocalizations.supportedLocales) {
    test('PDF and CSV creation in ${locale.toLanguageTag()} on worker isolates',
        () async {
      final l10n = await AppLocalizations.load(locale);
      final source = ExportDataSource(exportFixture());
      final sections = [
        for (final c in ExportCategory.values)
          source.section(c, const ExportFilter())
      ];
      const service = ExportService();
      final result = await service.create(
          sections: sections,
          format: ExportFormat.pdf,
          l10n: l10n,
          scope: l10n.text('export.allYears'),
          created: DateTime(2026, 10, 23, 15, 30),
          schoolYear: 2025);
      expect(ascii.decode(result.bytes.take(5).toList()), '%PDF-');
      expect(result.name, contains('2025-2026'));
      final zip = await service.create(
          sections: sections, format: ExportFormat.csv, l10n: l10n, scope: '');
      expect(zip.extension, 'zip');
      final archive = ZipDecoder().decodeBytes(zip.bytes);
      expect(archive.length, 8);
      expect(archive.first.content.take(3), [239, 187, 191]);
      const dir = String.fromEnvironment('EXPORT_PREVIEW_DIR');
      if (dir.isNotEmpty) {
        await Directory(dir).create(recursive: true);
        await File('$dir/overview_${locale.toLanguageTag()}.pdf')
            .writeAsBytes(result.bytes);
      }
    });
  }

  test(
      'long messages, huge words, tables and many grades paginate without loss',
      () async {
    final source = ExportDataSource(exportFixture());
    final longMessage = ExportSection(ExportCategory.messages, [
      ExportRecord(
          id: 'long',
          title: 'Grüße e città',
          fields: const {},
          body:
              '${List.filled(150, 'Nachricht über Prüfungen: è, ä, ß und ö. ').join()}\n${'x' * 2500}\nEND_OF_MESSAGE')
    ]);
    final grades = source.section(
        ExportCategory.grades, ExportFilter(semester: Semester.first));
    final manyGrades = ExportSection(
        ExportCategory.grades, List.generate(700, (i) => grades.records[i % 3]),
        semester: Semester.first,
        averages: grades.averages,
        overallAverage: grades.overallAverage);
    final result = await const ExportService().create(
        sections: [manyGrades, longMessage],
        format: ExportFormat.pdf,
        l10n: de,
        scope: de.text('export.allYears'));
    expect(result.bytes.length, greaterThan(20000));
    expect(exportTextChunks('x' * 2500).join(), 'x' * 2500);
    final words = List.filled(100, 'Grüße und città ').join();
    expect(exportTextChunks(words).join(), words);
    expect(exportTextChunks(words).take(2).every((part) => part.endsWith(' ')),
        isTrue);
    const dir = String.fromEnvironment('EXPORT_PREVIEW_DIR');
    if (dir.isNotEmpty)
      await File('$dir/stress.pdf').writeAsBytes(result.bytes);
  });

  test('native file dialog receives bytes; cancel and file errors are explicit',
      () async {
    final previous = FilePickerPlatform.instance;
    final picker = _Picker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final file = ExportFile('test.pdf', Uint8List.fromList([1, 2, 3]));
    const service = ExportService();
    expect(await service.save(file, 'Save'), isTrue);
    expect(picker.received, file.bytes);
    expect(picker.name, 'test.pdf');
    picker.result = null;
    expect(await service.save(file, 'Save'), isFalse);
    picker.fail = true;
    await expectLater(
        service.save(file, 'Save'), throwsA(isA<FileSystemException>()));
  });

  test('empty data and resource limits fail before creation or saving',
      () async {
    const service = ExportService();
    await expectLater(
        service.create(
            sections: [], format: ExportFormat.pdf, l10n: de, scope: ''),
        throwsA(isA<ExportEmptyException>()));
    await expectLater(
        service.create(sections: [
          ExportSection(
              ExportCategory.messages,
              List.filled(
                  20001, const ExportRecord(id: '1', title: 'x', fields: {})))
        ], format: ExportFormat.pdf, l10n: de, scope: ''),
        throwsA(isA<ExportTooLargeException>()));
  });
}
