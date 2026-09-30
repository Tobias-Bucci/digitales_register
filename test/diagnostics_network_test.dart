import 'package:dio/dio.dart';
import 'package:dr/diagnostics_network.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class NetworkSink implements DiagnosticSink {
  final keys = <String, Object>{};
  final errors = <String>[];
  @override
  Future<void> key(String name, Object value) async {
    keys[name] = value;
  }

  @override
  Future<void> log(String message) async {}
  @override
  Future<void> error(String category, StackTrace stack, bool fatal) async {
    errors.add(category);
  }
}

class ForwardedErrorHandler extends ErrorInterceptorHandler {
  @override
  void next(DioException error) {}
}

void main() {
  test(
      'safe request/response context ignores credentials, school host and payload',
      () async {
    final sink = NetworkSink();
    final service = DiagnosticsService(sink)..gate(true);
    final interceptor = DiagnosticsInterceptor(service: service);
    final options = RequestOptions(
        path: 'https://school.example/v2/api/student/grades/123?token=private',
        method: 'GET',
        headers: {'Authorization': 'Bearer private'},
        data: {'grade': 9, 'username': 'Alice'});
    interceptor.onRequest(options, RequestInterceptorHandler());
    interceptor.onResponse(
        Response(
            requestOptions: options,
            statusCode: 200,
            data: {'studentName': 'Alice'},
            headers: Headers.fromMap({
              'content-type': ['application/json']
            })),
        ResponseInterceptorHandler());
    await service.flush();
    expect(sink.keys['api_endpoint'], '/grades');
    expect(sink.keys['request_type'], 'grades');
    expect(sink.keys['response_format'], 'json');
    expect(sink.keys['http_status'], 200);
    expect(sink.keys['backend_reachable'], true);
    expect(sink.keys.toString(), isNot(contains('Alice')));
    expect(sink.errors, isEmpty);
  });
  test(
      'expected 401, 404 and cancellation are not reported; technical errors are',
      () async {
    final sink = NetworkSink();
    final service = DiagnosticsService(sink)..gate(true);
    final interceptor = DiagnosticsInterceptor(service: service);
    final options = RequestOptions(path: '/api/grade');
    for (final status in [401, 404]) {
      interceptor.onError(
          DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: status)),
          ForwardedErrorHandler());
    }
    interceptor.onError(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
        ForwardedErrorHandler());
    await service.flush();
    expect(sink.errors, isEmpty);
    interceptor.onError(
        DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
                requestOptions: options,
                statusCode: 500,
                data: {'private': 'payload'})),
        ForwardedErrorHandler());
    await service.flush();
    expect(sink.errors.single, 'E05_http');
    final login = RequestOptions(path: '/api/auth/login');
    interceptor.onError(
        DioException(
            requestOptions: login,
            type: DioExceptionType.connectionTimeout,
            message: 'password=private'),
        ForwardedErrorHandler());
    await service.flush();
    expect(sink.errors.last, 'E08_login');
    expect(sink.keys['request_timeout'], true);
    interceptor.onRequest(options, RequestInterceptorHandler());
    await service.flush();
    expect(sink.keys['request_timeout'], false);
    expect(sink.keys['http_status'], 0);
  });
}
