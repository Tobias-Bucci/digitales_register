import 'dart:ui' show PlatformDispatcher;

import 'package:dr/diagnostics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySink implements DiagnosticSink {
  final keys = <String, Object>{};
  final logs = <String>[];
  final errors = <String>[];
  final stacks = <String>[];
  @override
  Future<void> key(String name, Object value) async {
    keys[name] = value;
  }

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> error(String category, StackTrace stack, bool fatal) async {
    errors.add('$category:$fatal');
    stacks.add(stack.toString());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('global handlers preserve previous callbacks and sanitize fatal reports',
      () async {
    final previousFlutter = FlutterError.onError;
    final previousAsync = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousAsync;
    });
    var flutterCalls = 0;
    var asyncCalls = 0;
    FlutterError.onError = (_) {
      flutterCalls++;
    };
    PlatformDispatcher.instance.onError = (_, __) {
      asyncCalls++;
      return true;
    };
    final sink = MemorySink();
    final service = DiagnosticsService(sink)
      ..gate(true)
      ..installGlobalHandlers();
    FlutterError.onError!(FlutterErrorDetails(
        exception: Exception('password=private'), stack: StackTrace.current));
    expect(
        PlatformDispatcher.instance.onError!(
            Exception('Alice'), StackTrace.current),
        true);
    await service.flush();
    expect(flutterCalls, 1);
    expect(asyncCalls, 1);
    expect(sink.errors, ['E01_flutterFatal:true', 'E02_asyncFatal:true']);
    service.gate(false);
    FlutterError
        .onError!(FlutterErrorDetails(exception: Exception('token=private')));
    await service.flush();
    expect(flutterCalls, 2);
    expect(sink.errors, hasLength(2));
  });
  test('disabled wrappers transmit nothing; revoked queue is discarded',
      () async {
    final sink = MemorySink();
    final service = DiagnosticsService(sink);
    service.update('logged_in', true);
    service.safeLog('login_started');
    service.report(
        Exception('password'), StackTrace.current, DiagnosticError.caught);
    await service.flush();
    expect(sink.keys, isEmpty);
    expect(sink.logs, isEmpty);
    expect(sink.errors, isEmpty);
    service.gate(true);
    service.safeLog('request_started');
    service.gate(false);
    await service.flush();
    expect(sink.keys, isEmpty);
    expect(sink.logs, isEmpty);
  });
  test('45 fixed keys; no arbitrary values, payloads or exception messages',
      () async {
    final sink = MemorySink();
    final service = DiagnosticsService(sink);
    expect(DiagnosticsService.defaults.length, 45);
    service.gate(true);
    service.update('username', 'secret');
    service.update('feature', 'Alice 4B grade 8');
    service.update('api_endpoint',
        'https://user:pass@school.example/v2/grades/123?token=secret#secret');
    service.safeLog('Bearer token=password, alice@example.org');
    service.report(
        Exception('Alice password token grade 9'),
        StackTrace.fromString(
            '#0 parse (package:dr/data.dart:1:2)\n#1 secret (file:///C:/Users/Alice/private.dart:3:4)'),
        DiagnosticError.parser);
    await service.flush();
    expect(sink.keys.length, 45);
    expect(sink.keys['feature'], 'unknown');
    expect(sink.keys['api_endpoint'], '/grades');
    expect(sink.logs.last, '[redacted]');
    expect(sink.errors.single, 'E06_parser:false');
    expect(sink.stacks.single, contains('package:dr/data.dart'));
    expect(sink.stacks.single, isNot(contains('Alice')));
  });
  test('endpoint normalization and screen allowlist', () {
    expect(DiagnosticSanitizer.endpoint('/students/238382/grades?studentId=1'),
        '/grades');
    expect(DiagnosticSanitizer.endpoint('/users/Alice/private'), '/unknown');
    expect(
        DiagnosticSanitizer.endpoint(
            'https://school/v2/api/auth/login?password=test'),
        '/auth/login');
    expect(DiagnosticSanitizer.screen('/grades/123?name=Alice'), 'grades');
    expect(DiagnosticSanitizer.screen('/Alice/123'), 'unknown');
    expect(DiagnosticSanitizer.screen('/'), 'dashboard');
  });
  test('screen transition, logout reset and duplicate suppression', () async {
    final sink = MemorySink();
    final service = DiagnosticsService(sink);
    service.gate(true);
    service.screen('/grades');
    service.screen('/settings');
    expect(service.context['previous_screen'], 'grades');
    service
        .values({'http_status': 500, 'request_timeout': true, 'semester': '2'});
    service.auth(loggedIn: false, demo: false);
    expect(service.context['http_status'], 0);
    expect(service.context['request_timeout'], false);
    expect(service.context['semester'], 'unknown');
    final error = Exception('private');
    service.report(error, StackTrace.empty, DiagnosticError.caught);
    service.report(error, StackTrace.empty, DiagnosticError.asyncFatal,
        fatal: true);
    await service.flush();
    expect(sink.errors, hasLength(1));
  });
}
