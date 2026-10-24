import 'package:flutter/foundation.dart';

final _runtimeTraceClock = Stopwatch()..start();

/// Debug timings only. Callers must use fixed event names and metadata, never
/// account identifiers, credentials, URLs, responses or school contents.
void runtimeTrace(String scope, String event,
    {int? durationMs, String detail = ''}) {
  if (!kDebugMode) return;
  debugPrint('[$scope] ${DateTime.now().toUtc().toIso8601String()} '
      '+${_runtimeTraceClock.elapsedMilliseconds}ms $event '
      '${durationMs == null ? '' : 'durationMs=$durationMs'} $detail');
}
