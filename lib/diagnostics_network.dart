import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dr/diagnostics_service.dart';

class DiagnosticsInterceptor extends Interceptor {
  DiagnosticsInterceptor({DiagnosticsService? service})
      : _diagnostics = service ?? diagnostics;
  final DiagnosticsService _diagnostics;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final endpoint = DiagnosticSanitizer.endpoint(options.path);
    _diagnostics.resetRequest();
    _diagnostics.values({
      'api_endpoint': endpoint,
      'http_method': options.method,
      'request_type':
          endpoint == '/auth/login' ? 'login' : endpoint.substring(1),
      'feature':
          endpoint == '/auth/login' ? 'authentication' : endpoint.substring(1),
      'operation': 'request',
      'parser':
          endpoint == '/auth/login' ? 'authentication' : endpoint.substring(1),
      'request_retry_count': Zone.current[#diagnosticRetry] as int? ?? 0
    });
    _diagnostics.safeLog('request_started');
    handler.next(options);
  }

  void _response(Response<dynamic> response) {
    _diagnostics.values({
      'api_endpoint':
          DiagnosticSanitizer.endpoint(response.requestOptions.path),
      'http_method': response.requestOptions.method
    });
    final contentType = response.headers.value('content-type') ?? '';
    _diagnostics.values({
      'http_status': response.statusCode ?? 0,
      'backend_reachable': true,
      'network_available': true,
      'data_source': 'remote',
      'response_format': contentType.contains('json')
          ? 'json'
          : contentType.contains('html')
              ? 'html'
              : response.data is List<int>
                  ? 'binary'
                  : 'text'
    });
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    _response(response);
    _diagnostics.safeLog('request_completed');
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _diagnostics.values({
      'api_endpoint': DiagnosticSanitizer.endpoint(error.requestOptions.path),
      'http_method': error.requestOptions.method
    });
    final timeout = {
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout
    }.contains(error.type);
    if (error.response != null) _response(error.response!);
    _diagnostics.values({
      'http_status': error.response?.statusCode ?? 0,
      'request_timeout': timeout
    });
    if (error.type == DioExceptionType.connectionError) {
      _diagnostics
          .values({'backend_reachable': false, 'network_available': false});
    }
    final unexpected = timeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.badCertificate ||
        error.type == DioExceptionType.unknown ||
        (error.response?.statusCode ?? 0) >= 500;
    if (unexpected) {
      _diagnostics.safeLog('request_failed');
      _diagnostics.report(
          error,
          error.stackTrace,
          error.error is FormatException
              ? DiagnosticError.parser
              : DiagnosticSanitizer.endpoint(error.requestOptions.path) ==
                      '/auth/login'
                  ? DiagnosticError.login
                  : DiagnosticError.http);
    }
    handler.next(error);
  }
}
