import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dr/school_proxy.dart';
import 'package:dr/web_app/web_routing.dart';
import 'package:flutter_test/flutter_test.dart';

const origin = 'https://app.digitalesregister.com';
const slot = 's-abcdefgh12345678';

void main() {
  group('proxiedSchoolUrl', () {
    test('maps a school address into the proxy, with path and query', () {
      expect(
        proxiedSchoolUrl(
            'https://vinzentinum.digitalesregister.it/v2/api/auth/login', slot,
            origin: origin),
        '$origin/proxy/vinzentinum.digitalesregister.it/$slot/v2/api/auth/login',
      );
      expect(
        proxiedSchoolUrl(
            'https://tfobz.digitalesregister.it/v2/x?a=1&b=%20', slot,
            origin: origin),
        '$origin/proxy/tfobz.digitalesregister.it/$slot/v2/x?a=1&b=%20',
      );
    });

    test('keeps the encoded profile picture path as it is', () {
      expect(
        proxiedSchoolUrl(
            'https://a.digitalesregister.it/v2/api/profile/picture&pictureUrl=%2Fp%2Fa.jpg',
            slot,
            origin: origin),
        '$origin/proxy/a.digitalesregister.it/$slot/v2/api/profile/picture&pictureUrl=%2Fp%2Fa.jpg',
      );
    });

    test('leaves every other address alone', () {
      for (final url in [
        'http://vinzentinum.digitalesregister.it/v2/',
        'https://vinzentinum.digitalesregister.it:8443/v2/',
        'https://user@vinzentinum.digitalesregister.it/v2/',
        'https://digitalesregister.it/',
        'https://a.b.digitalesregister.it/v2/',
        'https://evil.com/v2/',
        'https://vinzentinum.digitalesregister.it.evil.com/v2/',
        'https://api.digitalesregister.com/api/v1/notifications',
        'not a url',
      ]) {
        expect(proxiedSchoolUrl(url, slot, origin: origin), isNull,
            reason: url);
      }
    });
  });

  test('slots are random and match what the proxy accepts', () {
    final a = newProxySlot(Random(1));
    final b = newProxySlot(Random(2));
    expect(a, matches(RegExp(r'^s-[a-z0-9]{16}$')));
    expect(a, isNot(b));
  });

  group('SchoolProxyInterceptor', () {
    late Dio dio;
    late List<String> seen;
    var unavailable = 0;

    setUp(() {
      seen = [];
      unavailable = 0;
      onSchoolProxyUnavailable = () => unavailable++;
      dio = Dio()
        ..interceptors.add(SchoolProxyInterceptor(() => slot,
            onProxied: seen.add, origin: () => origin))
        ..httpClientAdapter = _FakeAdapter();
    });

    tearDown(() => onSchoolProxyUnavailable = null);

    test('rewrites school requests and reports the host', () async {
      final r = await dio.get<String>(
          'https://vinzentinum.digitalesregister.it/v2/',
          queryParameters: {'x': '1'});
      expect(r.realUri.toString(),
          '$origin/proxy/vinzentinum.digitalesregister.it/$slot/v2/?x=1');
      expect(seen, ['vinzentinum.digitalesregister.it']);
    });

    test('a request without a school address fails without leaving the app',
        () async {
      await expectLater(
        dio.post<String>('/v2/?semesterWechsel=1'),
        throwsA(isA<DioException>()),
      );
      expect(seen, isEmpty);
    });

    test('an answer from Cloudflare instead of the proxy means "unavailable"',
        () async {
      _FakeAdapter.next = (status: 429, marker: false);
      await expectLater(
        dio.get<String>('https://vinzentinum.digitalesregister.it/v2/'),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<SchoolProxyUnavailable>())),
      );
      expect(unavailable, 1);
    });

    test('errors from the proxy itself stay ordinary errors', () async {
      _FakeAdapter.next = (status: 502, marker: true);
      await expectLater(
        dio.get<String>('https://vinzentinum.digitalesregister.it/v2/'),
        throwsA(isA<DioException>().having(
            (e) => e.error, 'error', isNot(isA<SchoolProxyUnavailable>()))),
      );
      expect(unavailable, 0);
    });
  });

  test('isProxyQuotaResponse', () {
    expect(isProxyQuotaResponse(429, null), isTrue);
    expect(isProxyQuotaResponse(500, null), isTrue);
    expect(isProxyQuotaResponse(429, '1'), isFalse);
    expect(isProxyQuotaResponse(200, null), isFalse);
    expect(isProxyQuotaResponse(404, null), isFalse);
  });

  test('web paths map to pages', () {
    expect(WebRoutes.destinationForPath('/grades'), 'grades');
    expect(WebRoutes.destinationForPath('/Grades/'), 'grades');
    expect(WebRoutes.destinationForPath('/exams'), 'examCalendar');
    expect(WebRoutes.destinationForPath('/'), isNull);
    expect(WebRoutes.destinationForPath('/login'), isNull);
    expect(WebRoutes.destinationForPath('/unknown'), isNull);
    for (final path in WebRoutes.pagePaths.values) {
      expect(WebRoutes.destinationKeys.containsKey(path), isTrue, reason: path);
    }
  });
}

class _FakeAdapter implements HttpClientAdapter {
  static ({int status, bool marker}) next = (status: 200, marker: true);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final current = next;
    next = (status: 200, marker: true);
    return ResponseBody.fromString('ok', current.status, headers: {
      if (current.marker) proxyMarkerHeader: ['1'],
    });
  }

  @override
  void close({bool force = false}) {}
}
