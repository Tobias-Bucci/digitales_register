// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:dr/course_materials.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses course content getCourse response', () {
    final course = CourseMaterialCourse.fromJson(
      {
        'id': 83,
        'course': {
          'id': 83,
          'title': '2. Gymnasium D 2025/2026',
          'ownerId': 19,
        },
        'topics': [
          {
            'id': 169,
            'courseContentId': 83,
            'title': 'Klassenlektüre "Über den Dächern von Jerusalem"',
            'number': 1,
            'entries': [
              {
                'id': 657,
                'courseContentId': 83,
                'courseContentTopicId': 169,
                'title': 'Über den Dächern von Jerusalem 1',
                'type': 'file',
                'link': null,
                'file':
                    'f_19_VVr3ADuxKuZFSmuFVGeGwtAStwBXQwKMGcAPX9x4ZDRDPdGT.pdf',
                'originalName': 'UEber den Daechern von Jerusalem 1.pdf',
                'hidden': 0,
                'number': 1,
                'lastmodified': '2026-02-16 18:43:47',
                'typeName': 'pdf',
              },
            ],
          },
        ],
        'copyOptions': [],
        'resetOptions': false,
      },
      const CourseMaterialSource(
        classId: 775,
        className: '2. Gymnasium',
        subjectId: 3,
        subjectName: 'Deutsch',
      ),
    );

    expect(course.id, 83);
    expect(course.entryCount, 1);
    expect(course.topics.single.displayTitle,
        '1. Klassenlektüre "Über den Dächern von Jerusalem"');
    expect(course.topics.single.entries.single.originalName,
        'UEber den Daechern von Jerusalem 1.pdf');
  });

  test('serializes course materials for page payload cache', () {
    final course = CourseMaterialCourse.fromJson(
      {
        'id': 83,
        'course': {'id': 83, 'title': '2. Gymnasium D 2025/2026'},
        'topics': [
          {
            'id': 169,
            'title': 'Thema',
            'number': 1,
            'entries': [
              {
                'id': 657,
                'courseContentId': 83,
                'title': 'Arbeitsblatt',
                'type': 'file',
                'hidden': 0,
                'number': 1,
                'typeName': 'pdf',
              },
            ],
          },
        ],
      },
      const CourseMaterialSource(
        classId: 775,
        className: '2. Gymnasium',
        subjectId: 3,
        subjectName: 'Deutsch',
      ),
    );
    final snapshot =
        PagePayloadSnapshot<List<Map<String, dynamic>>>.fromPayload(
      [Map<String, dynamic>.from(course.toJson())],
      fetchedAt: DateTime(2026, 6, 12, 8),
    );
    final restored =
        CourseMaterialCourse.fromCacheJson(snapshot.payload.single);

    expect(restored.subjectName, 'Deutsch');
    expect(restored.entryCount, 1);
    expect(restored.topics.single.entries.single.title, 'Arbeitsblatt');
    expect(
      PagePayloadSnapshot<List<Map<String, dynamic>>>.fromPayload(
        [Map<String, dynamic>.from(course.toJson())],
        fetchedAt: DateTime(2026, 6, 12, 9),
      ).fingerprint,
      snapshot.fingerprint,
    );
  });
}
