import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'package:dr/telemetry_capabilities.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum DiagnosticError {
  flutterFatal,
  asyncFatal,
  isolateFatal,
  caught,
  http,
  parser,
  storage,
  login,
  notification,
  background
}

abstract class DiagnosticSink {
  Future<void> key(String name, Object value);
  Future<void> log(String message);
  Future<void> error(String category, StackTrace stack, bool fatal);
}

class FirebaseDiagnosticSink implements DiagnosticSink {
  FirebaseDiagnosticSink({TelemetryCapabilities? capabilities})
      : _capabilities = capabilities;

  final TelemetryCapabilities? _capabilities;
  bool get _supported =>
      (_capabilities ?? TelemetryCapabilities.current()).supportsCrashlytics;

  @override
  Future<void> key(String name, Object value) async {
    if (_supported) {
      await FirebaseCrashlytics.instance.setCustomKey(name, value);
    }
  }

  @override
  Future<void> log(String message) async {
    if (_supported) {
      await FirebaseCrashlytics.instance.log(message);
    }
  }

  @override
  Future<void> error(String category, StackTrace stack, bool fatal) async {
    if (_supported) {
      await FirebaseCrashlytics.instance.recordError(Exception(category), stack,
          fatal: fatal, reason: category);
    }
  }
}

// Only predefined values may cross the telemetry boundary. Redaction alone
// cannot reliably identify names, school content, or arbitrary free text.
// ignore: avoid_classes_with_only_static_members
class DiagnosticSanitizer {
  static const screens = {
    'dashboard',
    'login',
    'request_pass_reset',
    'pass_reset',
    'change_email',
    'profile',
    'notifications',
    'settings',
    'grades',
    'absences',
    'calendar',
    'examCalendar',
    'classRegister',
    'courseMaterials',
    'homeworkSummary',
    'privacy_consent',
    'homework',
    'certificate',
    'messages',
    'debug',
    'grade_calculator',
    'privacy_details',
    'unknown'
  };
  static String screen(String? raw) {
    final value = (raw ?? '')
        .split('?')
        .first
        .split('#')
        .first
        .split('/')
        .where((e) => e.isNotEmpty)
        .firstOrNull;
    if (raw == '/') return 'dashboard';
    return screens.contains(value) ? value! : 'unknown';
  }

  static String endpoint(String raw) {
    final path = Uri.tryParse(raw)?.path.toLowerCase() ?? '';
    // Never forward the host, path segments, IDs, query, or raw input.
    final parts = path.split('/').toSet();
    if (parts.contains('auth')) {
      return '/auth/login';
    }
    if (parts.contains('grade') ||
        parts.contains('grades') ||
        parts.contains('evaluation')) {
      return '/grades';
    }
    if (parts.contains('calendar') || parts.contains('timetable')) {
      return '/timetable';
    }
    if (parts.contains('absence') || parts.contains('absences')) {
      return '/absences';
    }
    if (parts.contains('notification') || parts.contains('notifications')) {
      return '/notifications';
    }
    if (parts.contains('dashboard') ||
        parts.contains('homework&klasse') ||
        parts.contains('homework')) {
      return '/homework';
    }
    if (parts.contains('message') || parts.contains('messages')) {
      return '/messages';
    }
    if (parts.contains('coursecontent') || parts.contains('materials')) {
      return '/materials';
    }
    if (parts.contains('certificate')) {
      return '/certificate';
    }
    return '/unknown';
  }

  static const breadcrumbs = {
    'app_initialized',
    'screen_opened',
    'request_started',
    'request_completed',
    'request_failed',
    'request_retry',
    'login_started',
    'login_completed',
    'logout',
    'parser_started',
    'parser_failed',
    'cache_hit',
    'cache_miss',
    'cache_write',
    'sync_started',
    'sync_completed',
    'sync_failed',
    'developer_test'
  };
  static String log(String input) =>
      breadcrumbs.contains(input) ? input : '[redacted]';

  static StackTrace stack(StackTrace input) {
    // SDK receives symbol frames only. Drop absolute paths and unknown frames,
    // which may contain Windows usernames or isolate error message text.
    final frames = input.toString().split('\n').where((line) => RegExp(
            r'^#\d+\s+(?:new )?[a-zA-Z0-9_.$<>]+(?:\.<anonymous closure>)?\s+\((?:package:[a-zA-Z0-9_./-]+|dart:[a-zA-Z0-9_./-]+):\d+:\d+\)\s*$')
        .hasMatch(line));
    return StackTrace.fromString(frames.take(80).join('\n'));
  }
}

class DiagnosticsService {
  DiagnosticsService(this.sink);
  final DiagnosticSink sink;
  bool enabled = false;
  int _epoch = 0;
  Future<void> _tail = Future<void>.value();
  final _reported = Queue<Object>();
  final Map<String, Object> context = Map.of(defaults);

  static const Map<String, Object> defaults = {
    'current_screen': 'unknown',
    'previous_screen': 'unknown',
    'app_state': 'unknown',
    'demo_mode': false,
    'logged_in': false,
    'login_provider': 'unknown',
    'api_version': 'v2',
    'api_environment': 'unknown',
    'api_endpoint': '/unknown',
    'http_method': 'unknown',
    'http_status': 0,
    'request_type': 'unknown',
    'response_format': 'unknown',
    'network_available': 'unknown',
    'connection_type': 'unknown',
    'request_retry_count': 0,
    'request_timeout': false,
    'cache_enabled': true,
    'cache_hit': false,
    'local_db_version': 'not_applicable',
    'migration_version': 'not_applicable',
    'semester': 'unknown',
    'selected_tab': 'unknown',
    'selected_filter': 'unknown',
    'theme': 'unknown',
    'locale': 'unknown',
    'notification_enabled': false,
    'notification_type': 'unknown',
    'background_task': 'none',
    'sync_running': false,
    'last_sync_result': 'unknown',
    'data_source': 'unknown',
    'parser': 'unknown',
    'feature': 'unknown',
    'operation': 'unknown',
    'is_first_launch': false,
    'upgrade_detected': false,
    'previous_app_version': 'unknown',
    'installation_source': 'unknown',
    'build_flavor': 'unknown',
    'release_channel': 'unknown',
    'flutter_version': 'unknown',
    'dart_version': 'unknown',
    'backend_reachable': 'unknown',
    'school_api_type': 'digital_register_api',
  };
  static const _enums = <String, Set<String>>{
    'app_state': {
      'foreground',
      'background',
      'inactive',
      'detached',
      'hidden',
      'unknown'
    },
    'login_provider': {'school_api', 'demo', 'unknown'},
    'api_environment': {'production', 'staging', 'development', 'unknown'},
    'http_method': {
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'HEAD',
      'OPTIONS',
      'unknown'
    },
    'request_type': {
      'login',
      'grades',
      'timetable',
      'absences',
      'homework',
      'notifications',
      'messages',
      'materials',
      'certificate',
      'unknown'
    },
    'response_format': {'json', 'html', 'text', 'binary', 'unknown'},
    'connection_type': {
      'wifi',
      'mobile',
      'ethernet',
      'vpn',
      'none',
      'other',
      'unknown'
    },
    'semester': {'1', '2', 'all', 'unknown'},
    'selected_filter': {
      'all',
      'current',
      'open',
      'completed',
      'future',
      'past',
      'type_sorted',
      'date_sorted',
      'unknown'
    },
    'theme': {'light', 'dark', 'system', 'unknown'},
    'locale': {'de', 'it', 'en', 'lld', 'de_LLD', 'unknown'},
    'notification_type': {
      'grade',
      'absence',
      'timetable',
      'general',
      'sync',
      'unknown'
    },
    'background_task': {'sync', 'refresh', 'notification_processing', 'none'},
    'last_sync_result': {
      'success',
      'failed',
      'partial',
      'cancelled',
      'unknown'
    },
    'data_source': {'remote', 'cache', 'local', 'mixed', 'unknown'},
    'parser': {
      'grades',
      'timetable',
      'absences',
      'homework',
      'notifications',
      'authentication',
      'register',
      'unknown'
    },
    'feature': {
      'grades',
      'timetable',
      'absences',
      'homework',
      'settings',
      'authentication',
      'notifications',
      'messages',
      'materials',
      'certificate',
      'storage',
      'calendar',
      'register',
      'unknown'
    },
    'operation': {
      'request',
      'parse',
      'load',
      'save',
      'sync',
      'login',
      'logout',
      'open',
      'unknown'
    },
    'installation_source': {
      'play_store',
      'manual',
      'other',
      'unknown',
      'not_applicable'
    },
    'build_flavor': {'production', 'staging', 'development', 'unknown'},
    'release_channel': {
      'production',
      'closed_beta',
      'internal',
      'debug',
      'testflight',
      'unknown'
    },
    'school_api_type': {'digital_register_api', 'demo', 'unknown'},
    'api_version': {'v2', 'unknown'},
    'local_db_version': {'not_applicable', 'unknown'},
    'migration_version': {'not_applicable', 'unknown'},
  };

  void gate(bool value) {
    enabled = value;
    _epoch++;
    if (value) {
      for (final entry in context.entries) {
        _enqueue(() => sink.key(entry.key, entry.value));
      }
      safeLog('app_initialized');
    }
  }

  void _enqueue(Future<void> Function() action) {
    if (!enabled) return;
    final epoch = _epoch;
    _tail = _tail.then((_) async {
      if (!enabled || epoch != _epoch) return;
      try {
        await action();
      } catch (_) {/* Diagnostics never breaks the app. */}
    });
  }

  Future<void> flush() => _tail;

  void update(String key, Object value) {
    if (!defaults.containsKey(key)) return;
    Object safe;
    if (key == 'api_endpoint') {
      safe = DiagnosticSanitizer.endpoint(value.toString());
    } else if (key == 'current_screen' ||
        key == 'previous_screen' ||
        key == 'selected_tab') {
      safe = DiagnosticSanitizer.screen(value.toString());
    } else if (key == 'network_available' || key == 'backend_reachable') {
      safe = value is bool ? value : 'unknown';
    } else if (defaults[key] is bool) {
      safe = value is bool ? value : defaults[key]!;
    } else if (defaults[key] is int) {
      safe = value is int && value >= 0 && value <= 999 ? value : 0;
    } else if (key.endsWith('_version') && !_enums.containsKey(key)) {
      safe = RegExp(r'^\d+\.\d+\.\d+(?:\+\d+)?$').hasMatch(value.toString())
          ? value
          : (value == 'none' ? 'none' : 'unknown');
    } else {
      safe = _enums[key]?.contains(value) == true ? value : defaults[key]!;
    }
    if (context[key] == safe) return;
    context[key] = safe;
    _enqueue(() => sink.key(key, safe));
  }

  void values(Map<String, Object> values) => values.forEach(update);
  void safeLog(String message) =>
      _enqueue(() => sink.log(DiagnosticSanitizer.log(message)));

  void report(Object error, StackTrace stack, DiagnosticError category,
      {bool fatal = false}) {
    if (!enabled || _reported.any((value) => identical(value, error))) return;
    _reported.add(error);
    if (_reported.length > 32) _reported.removeFirst();
    // Never call error.toString(), inspect exception fields, or serialize input.
    final code =
        'E${(category.index + 1).toString().padLeft(2, '0')}_${category.name}';
    _enqueue(() => sink.error(code, DiagnosticSanitizer.stack(stack), fatal));
  }

  void screen(String? raw) {
    final name = DiagnosticSanitizer.screen(raw);
    if (context['current_screen'] == name) return;
    update('previous_screen', context['current_screen']!);
    update('current_screen', name);
    update('selected_tab', name);
    resetRequest();
    safeLog('screen_opened');
  }

  void resetRequest() => values({
        for (final name in [
          'api_endpoint',
          'http_method',
          'http_status',
          'request_type',
          'response_format',
          'request_retry_count',
          'request_timeout',
          'parser',
          'feature',
          'operation',
          'cache_hit'
        ])
          name: defaults[name]!
      });
  void auth({required bool loggedIn, required bool demo}) {
    final changed = loggedIn != context['logged_in'];
    values({
      'logged_in': loggedIn,
      'demo_mode': demo,
      'login_provider': loggedIn ? (demo ? 'demo' : 'school_api') : 'unknown',
      'school_api_type': demo ? 'demo' : 'digital_register_api'
    });
    if (changed) {
      safeLog(loggedIn ? 'login_completed' : 'logout');
    }
    if (!loggedIn) {
      resetRequest();
      values({
        'semester': 'unknown',
        'selected_filter': 'unknown',
        'notification_type': 'unknown',
        'data_source': 'unknown',
        'backend_reachable': 'unknown'
      });
    }
  }

  bool _handlersInstalled = false;
  void installGlobalHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      report(details.exception, details.stack ?? StackTrace.empty,
          DiagnosticError.flutterFatal,
          fatal: true);
      previousFlutter?.call(details);
    };
    final previousAsync = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, DiagnosticError.asyncFatal, fatal: true);
      return previousAsync?.call(error, stack) ?? enabled;
    };
  }

  /// Attach only to a worker whose failures do not reach the global handlers.
  /// The caller owns the port and must close it when the worker exits.
  ReceivePort listenToWorker(Isolate worker) {
    final port = ReceivePort();
    port.listen((dynamic event) {
      if (event is List && event.length == 2) {
        report(_IsolateFailure(), StackTrace.fromString(event[1].toString()),
            DiagnosticError.isolateFatal,
            fatal: true);
      }
    });
    worker.addErrorListener(port.sendPort);
    return port;
  }

  Future<void> developerTest({bool nativeCrash = false}) async {
    if (!kDebugMode || !enabled) return;
    safeLog('developer_test');
    report(Exception('test'), StackTrace.current, DiagnosticError.caught);
    await flush();
    if (nativeCrash && (Platform.isAndroid || Platform.isIOS)) {
      FirebaseCrashlytics.instance.crash();
    }
  }
}

class _IsolateFailure {
  _IsolateFailure();
}

final diagnostics = DiagnosticsService(FirebaseDiagnosticSink());

class DiagnosticsNavigatorObserver extends NavigatorObserver {
  DiagnosticsNavigatorObserver({this.onScreen});
  final void Function(String)? onScreen;
  void _screen(Route<dynamic>? route) {
    if (route?.settings.name == null) return;
    final name = DiagnosticSanitizer.screen(route!.settings.name);
    diagnostics.screen(name);
    onScreen?.call(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _screen(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _screen(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _screen(newRoute);
}
