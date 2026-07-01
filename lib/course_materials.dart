// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:dr/util.dart';

class CourseMaterialsLoadException implements Exception {
  const CourseMaterialsLoadException();

  @override
  String toString() => 'Course materials request returned no calendar data.';
}

class CourseMaterialSource {
  const CourseMaterialSource({
    required this.classId,
    required this.className,
    required this.subjectId,
    required this.subjectName,
  });

  final int classId;
  final String className;
  final int subjectId;
  final String subjectName;

  Map<String, Object?> toJson() => <String, Object?>{
        'classId': classId,
        'className': className,
        'subjectId': subjectId,
        'subjectName': subjectName,
      };

  factory CourseMaterialSource.fromJson(Map json) {
    return CourseMaterialSource(
      classId: getInt(json['classId']) ?? 0,
      className: getString(json['className']) ?? '',
      subjectId: getInt(json['subjectId']) ?? 0,
      subjectName: getString(json['subjectName']) ?? '',
    );
  }
}

class CourseMaterialCourse {
  const CourseMaterialCourse({
    required this.id,
    required this.title,
    required this.classId,
    required this.className,
    required this.subjectId,
    required this.subjectName,
    required this.topics,
  });

  final int id;
  final String title;
  final int classId;
  final String className;
  final int subjectId;
  final String subjectName;
  final List<CourseMaterialTopic> topics;

  int get entryCount =>
      topics.fold<int>(0, (sum, topic) => sum + topic.entries.length);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'source': CourseMaterialSource(
          classId: classId,
          className: className,
          subjectId: subjectId,
          subjectName: subjectName,
        ).toJson(),
        'topics': topics.map((topic) => topic.toJson()).toList(),
      };

  factory CourseMaterialCourse.fromJson(Map json, CourseMaterialSource source) {
    final course = getMap(json['course']);
    final courseId = getInt(json['id']) ?? getInt(course?['id']) ?? 0;
    final topics = (getList(json['topics']) ?? const <dynamic>[])
        .map((topic) => getMap(topic))
        .nonNulls
        .map((topic) => CourseMaterialTopic.fromJson(topic))
        .where((topic) => topic.entries.isNotEmpty)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return CourseMaterialCourse(
      id: courseId,
      title: getString(course?['title']) ?? '',
      classId: source.classId,
      className: source.className,
      subjectId: source.subjectId,
      subjectName: source.subjectName,
      topics: topics,
    );
  }

  factory CourseMaterialCourse.fromCacheJson(Map json) {
    return CourseMaterialCourse(
      id: getInt(json['id']) ?? 0,
      title: getString(json['title']) ?? '',
      classId: getInt(json['classId']) ??
          getInt(getMap(json['source'])?['classId']) ??
          0,
      className: getString(json['className']) ??
          getString(getMap(json['source'])?['className']) ??
          '',
      subjectId: getInt(json['subjectId']) ??
          getInt(getMap(json['source'])?['subjectId']) ??
          0,
      subjectName: getString(json['subjectName']) ??
          getString(getMap(json['source'])?['subjectName']) ??
          '',
      topics: (getList(json['topics']) ?? const <dynamic>[])
          .map((topic) => getMap(topic))
          .nonNulls
          .map((topic) => CourseMaterialTopic.fromCacheJson(topic))
          .toList(),
    );
  }
}

class CourseMaterialTopic {
  const CourseMaterialTopic({
    required this.id,
    required this.title,
    required this.number,
    required this.entries,
  });

  final int id;
  final String title;
  final int number;
  final List<CourseMaterialEntry> entries;

  String get displayTitle => number > 0 ? '$number. $title' : title;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'number': number,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory CourseMaterialTopic.fromJson(Map json) {
    final entries = (getList(json['entries']) ?? const <dynamic>[])
        .map((entry) => getMap(entry))
        .nonNulls
        .map((entry) => CourseMaterialEntry.fromJson(entry))
        .where((entry) => !entry.hidden)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return CourseMaterialTopic(
      id: getInt(json['id']) ?? 0,
      title: getString(json['title']) ?? '',
      number: getInt(json['number']) ?? 0,
      entries: entries,
    );
  }

  factory CourseMaterialTopic.fromCacheJson(Map json) {
    return CourseMaterialTopic(
      id: getInt(json['id']) ?? 0,
      title: getString(json['title']) ?? '',
      number: getInt(json['number']) ?? 0,
      entries: (getList(json['entries']) ?? const <dynamic>[])
          .map((entry) => getMap(entry))
          .nonNulls
          .map((entry) => CourseMaterialEntry.fromJson(entry))
          .toList(),
    );
  }
}

class CourseMaterialEntry {
  const CourseMaterialEntry({
    required this.id,
    required this.courseContentId,
    required this.title,
    required this.type,
    required this.link,
    required this.file,
    required this.originalName,
    required this.hidden,
    required this.number,
    required this.lastModified,
    required this.typeName,
  });

  final int id;
  final int courseContentId;
  final String title;
  final String type;
  final String? link;
  final String? file;
  final String originalName;
  final bool hidden;
  final int number;
  final String lastModified;
  final String typeName;

  bool get isLink => type == 'link';

  String get uniqueName {
    final name = originalName.isNotEmpty ? originalName : file ?? '$title.bin';
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return 'course_${courseContentId}_${id}_$safeName';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'courseContentId': courseContentId,
        'title': title,
        'type': type,
        'link': link,
        'file': file,
        'originalName': originalName,
        'hidden': hidden ? 1 : 0,
        'number': number,
        'lastmodified': lastModified,
        'typeName': typeName,
      };

  factory CourseMaterialEntry.fromJson(Map json) {
    return CourseMaterialEntry(
      id: getInt(json['id']) ?? 0,
      courseContentId: getInt(json['courseContentId']) ?? 0,
      title: getString(json['title']) ?? '',
      type: getString(json['type']) ?? '',
      link: getString(json['link']),
      file: getString(json['file']),
      originalName: getString(json['originalName']) ?? '',
      hidden: (getInt(json['hidden']) ?? 0) != 0,
      number: getInt(json['number']) ?? 0,
      lastModified: getString(json['lastmodified']) ?? '',
      typeName: getString(json['typeName']) ?? '',
    );
  }
}
