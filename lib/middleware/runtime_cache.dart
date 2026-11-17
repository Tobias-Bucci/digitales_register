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

// In-memory freshness of loaded pages, and loads that run once even
// when several callers ask at the same time.

const Duration _dashboardCacheTtl = Duration(seconds: 45);
const Duration _notificationsCacheTtl = Duration(seconds: 30);
const Duration _profileCacheTtl = Duration(minutes: 5);
const Duration _calendarCacheTtl = Duration(minutes: 5);
const Duration _gradesCacheTtl = Duration(minutes: 1);
const Duration _messagesCacheTtl = Duration(minutes: 1);
const Duration _absencesCacheTtl = Duration(minutes: 2);
const Duration _certificateCacheTtl = Duration(minutes: 5);

final Map<String, Future<void>> _inFlightLoads = <String, Future<void>>{};
final Map<String, UtcDateTime> _runtimeCacheTimes = <String, UtcDateTime>{};
final Set<String> _staleCacheKeys = <String>{};

String _dashboardCacheKey(bool future) => 'dashboard:$future';
String _calendarCacheKey(UtcDateTime monday) =>
    'calendar:${monday.stripTime().toIso8601String()}';

const String _notificationsCacheKey = 'notifications';
const String _profileCacheKey = 'profile';
const String _messagesCacheKey = 'messages';
const String _absencesCacheKey = 'absences';
const String _certificateCacheKey = 'certificate';

/// The analytics feature of each kind of cached page, by the prefix of its key.
const _cacheFeatures = {
  'dashboard': 'homework',
  'calendar': 'timetable',
  'notifications': 'notifications',
  'messages': 'messages',
  'absences': 'absences',
  'profile': 'register',
  'certificate': 'register'
};

bool _isFresh(UtcDateTime? timestamp, Duration ttl) {
  if (timestamp == null) {
    diagnostics.update('cache_hit', false);
    return false;
  }
  final age = realNow.difference(timestamp);
  final fresh = !age.isNegative && age < ttl;
  diagnostics.update('cache_hit', fresh);
  if (fresh) {
    diagnostics.update('data_source', 'cache');
    diagnostics.safeLog('cache_hit');
  }
  return fresh;
}

bool _isRuntimeCacheFresh(String key, Duration ttl) {
  final fresh = _isFresh(_runtimeCacheTimes[key], ttl);
  final feature = _cacheFeatures[key.split(':').first];
  if (fresh && feature != null) {
    unawaited(AnalyticsService.product
        .event('cache_result', {'feature': feature, 'result': 'hit'}));
    unawaited(AnalyticsService.product.event(
        'data_source_used', {'feature': feature, 'data_source': 'cache'}));
  }
  return fresh;
}

/// Marks [key] fresh for the session that loaded it. A load that finishes
/// after the app has switched account must not make the new account's cache
/// look fresh.
void _markRuntimeCacheFresh(String key, _Session session) {
  if (!session.isCurrent) return;
  _runtimeCacheTimes[key] = realNow;
  _staleCacheKeys.remove(key);
}

void _markRuntimeCacheStale(String key) {
  _runtimeCacheTimes.remove(key);
  _staleCacheKeys.add(key);
}

bool _isCacheMarkedStale(String key) {
  return _staleCacheKeys.contains(key);
}

void _clearRuntimeCaches() {
  _inFlightLoads.clear();
  _runtimeCacheTimes.clear();
  _staleCacheKeys.clear();
  _authenticatedBytesInFlight.clear();
  forgetProfilePictures();
  _workingCourseMaterialCandidate = null;
  // A new session (or regenerated demo data) starts on an unknown server-side
  // semester, so the next grades request has to switch explicitly.
  _gradesLock.reset();
}

/// Invalidates only in-memory response caches. Used after demo data changes so
/// freshly generated local data is shown immediately.
void clearRuntimeCaches() => _clearRuntimeCaches();

Future<void> _runCoalescedLoad(String key, Future<void> Function() load) async {
  final existing = _inFlightLoads[key];
  if (existing != null) {
    await existing;
    return;
  }

  final future = Future<void>(() async {
    final product = AnalyticsService.product;
    final epoch = product.sessionEpoch;
    final stopwatch = Stopwatch()..start();
    final previousCacheTime = _runtimeCacheTimes[key];
    final prefix = key.split(':').first;
    final feature = _cacheFeatures[prefix];
    if (feature != null) {
      unawaited(product
          .event('cache_result', {'feature': feature, 'result': 'miss'}));
    }
    diagnostics.update('cache_hit', false);
    diagnostics.safeLog('cache_miss');
    try {
      await load();
      if (feature != null && product.isSession(epoch)) {
        unawaited(product.event('refresh_result', {
          'feature': feature,
          'result': _runtimeCacheTimes[key] != previousCacheTime
              ? 'success'
              : 'failed',
          'data_source': wrapper.demoMode ? 'local' : 'remote',
          'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
        }));
      }
    } on StaleSessionException {
      // The account was left while loading: nothing to report or to retry.
      return;
    } catch (e, stack) {
      if (feature != null && product.isSession(epoch)) {
        unawaited(product.event('refresh_result', {
          'feature': feature,
          'result': 'failed',
          'data_source': 'unknown',
          'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
        }));
      }
      diagnostics.report(
          e,
          stack,
          e is ParseException || e is FormatException
              ? DiagnosticError.parser
              : key == _notificationsCacheKey
                  ? DiagnosticError.notification
                  : DiagnosticError.caught);
      rethrow;
    }
  });
  _inFlightLoads[key] = future;
  try {
    await future;
  } finally {
    if (identical(_inFlightLoads[key], future)) {
      final removed = _inFlightLoads.remove(key);
      assert(identical(removed, future));
    }
  }
}
