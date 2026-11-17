// Copyright (C) 2021 Michael Debertol
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

part of 'middleware.dart';

// Raw page payloads (homework summary, class register lessons) with the
// account-scoped keys of their on-device caches.

Future<PagePayloadSnapshot<String>?> loadCachedHomeworkSummaryHtmlPayload() {
  return pagePayloadCacheService.load(
    _homeworkSummaryCacheKey(),
    parseStringPayload,
  );
}

Future<PagePayloadSnapshot<String>?> refreshHomeworkSummaryHtmlPayload() async {
  if (wrapper.noInternet) {
    return null;
  }
  // The cache key belongs to the account that asks, not to whoever is signed
  // in when the answer arrives.
  final session = _Session.capture(withStorageKey: true);
  try {
    // The official frontend sends a Unix timestamp in milliseconds here.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await session.send(
      'vorstand/homework&klasse?_=$timestamp',
      method: 'GET',
    );
    final html = response?.toString();
    if (html == null) {
      return null;
    }
    final snapshot = PagePayloadSnapshot<String>.fromPayload(html);
    await pagePayloadCacheService.save(
        _homeworkSummaryCacheKey(session), snapshot);
    return snapshot;
  } on StaleSessionException {
    return null;
  }
}

Future<List<Map<String, dynamic>>?> loadClassRegisterLessonPayload() async {
  final snapshot = await refreshClassRegisterLessonPayload();
  return snapshot?.payload;
}

Future<ClassRegisterPayloadSnapshot?> loadCachedClassRegisterLessonPayload() {
  return classRegisterCacheService.load(_classRegisterCacheKey());
}

Future<ClassRegisterPayloadSnapshot?>
    refreshClassRegisterLessonPayload() async {
  try {
    return await _refreshClassRegisterLessonPayload(
        _Session.capture(withStorageKey: true));
  } on StaleSessionException {
    return null;
  }
}

Future<ClassRegisterPayloadSnapshot?> _refreshClassRegisterLessonPayload(
    _Session session) async {
  if (session.wrapper.demoMode) {
    final snapshot = ClassRegisterPayloadSnapshot.fromPayload(
      const <Map<String, dynamic>>[],
    );
    await classRegisterCacheService.save(
        _classRegisterCacheKey(session), snapshot);
    return snapshot;
  }
  await session.send(
    'register/student?_=${DateTime.now().millisecondsSinceEpoch}',
    method: 'GET',
  );
  final response = await session.send('api/lesson/student');
  final rawLessons = switch (response) {
    final List<dynamic> list => list,
    final Map<dynamic, dynamic> map when map['data'] is List =>
      map['data'] as List,
    final Map<dynamic, dynamic> map when map['lessons'] is List =>
      map['lessons'] as List,
    _ => null,
  };
  final payload = rawLessons
      ?.map((item) => getMap(item))
      .nonNulls
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  if (payload == null) {
    return null;
  }
  final snapshot = ClassRegisterPayloadSnapshot.fromPayload(payload);
  await classRegisterCacheService.save(
      _classRegisterCacheKey(session), snapshot);
  return snapshot;
}

/// Cache keys use the account of [session] when given (a load in progress),
/// otherwise whoever is signed in now (a plain read).
String _storageKeyFor(_Session? session) =>
    session?.storageKey ?? getStorageKey(wrapper.user, wrapper.loginAddress);

String _classRegisterCacheKey([_Session? session]) =>
    'classRegisterLessons:${_storageKeyFor(session)}';

String _courseMaterialsCacheKey([_Session? session]) =>
    'courseMaterials:${_storageKeyFor(session)}';

String userScopedStorageKey(String namespace) =>
    '$namespace:${getStorageKey(wrapper.user, wrapper.loginAddress)}';

String _homeworkSummaryCacheKey([_Session? session]) =>
    'homeworkSummary:${_storageKeyFor(session)}';
