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

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

const _url = 'https://example.org/picture';

/// A red pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIA'
  'X8jx0gAAAABJRU5ErkJggg==',
);

/// Claims to be a picture, but is none.
final _broken = utf8.encode('GIF89a this is not really a picture');

final _loginPage = utf8.encode(
  '<!DOCTYPE html><html><head><title>Login</title></head> '
  '<body><form id="login" action="/v2/api/auth/login"></form></body></html>',
);

typedef _Reply = (int, String, List<int>);
typedef _Answer = FutureOr<_Reply> Function(String url);

_Reply _picture(String _) => (200, 'image/png', _png);
_Reply _offline(String _) => throw StateError('offline');

/// A session that answers picture requests from a script.
class _PictureWrapper extends MockWrapper {
  _PictureWrapper(this.answer) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final url = options.uri.toString();
        requests.add(url);
        try {
          final (status, type, bytes) = await answer(url);
          handler.resolve(Response<List<int>>(
            requestOptions: options,
            statusCode: status,
            data: bytes,
            headers: Headers.fromMap({
              'content-type': [type],
            }),
          ));
        } catch (error) {
          handler.reject(DioException(requestOptions: options, error: error));
        }
      },
    ));
  }

  _Answer answer;
  bool signedIn = true;
  final List<String> requests = <String>[];
  final List<bool> logins = <bool>[];
  final Dio _dio = Dio();

  @override
  String? get user => 'anna';
  @override
  String? get url => 'https://example.org';
  @override
  Dio get dio => _dio;
  @override
  bool get noInternet => false;
  @override
  Future<bool> ensureLoggedIn({
    bool isRetryAfterUnexpectedLogout = false,
    bool forceRelogin = false,
  }) async {
    logins.add(isRetryAfterUnexpectedLogout);
    return signedIn;
  }
}

Widget _app(String? url, {double size = 32, bool showProgress = false}) =>
    MaterialApp(
      home: Center(
        child: ProfileAvatar(
          imageUrl: url,
          size: size,
          showProgress: showProgress,
        ),
      ),
    );

/// Lets real asynchronous work such as decoding finish, then shows its result.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
  }
  await tester.pump();
}

void _expectFigure(WidgetTester tester) {
  expect(find.byKey(ProfileAvatar.figureKey), findsOneWidget);
  expect(find.byKey(ProfileAvatar.pictureKey), findsNothing);
}

/// That a decoded picture is really on the screen.
void _expectPicture(WidgetTester tester) {
  expect(find.byKey(ProfileAvatar.figureKey), findsNothing);
  expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
}

void main() {
  late _PictureWrapper session;

  // Has to happen outside of the fake time of a widget test.
  setUp(() async {
    session = _PictureWrapper(_picture);
    await bootstrapTestEnvironment(wrapperOverride: session);
  });

  void start(_Answer answer) => session.answer = answer;

  tearDown(resetTestState);

  group('no picture to show', () {
    for (final (name, url) in const [('none', null), ('empty', '')]) {
      testWidgets('shows the figure without asking the server ($name)',
          (tester) async {
        start(_picture);
        await tester.pumpWidget(_app(url));
        await _settle(tester);

        _expectFigure(tester);
        expect(session.requests, isEmpty);
      });
    }

    test('an empty profile has no address', () {
      expect(
        buildProfilePictureUrl(baseUrl: 'https://a.example', picture: ' '),
        isNull,
      );
      expect(buildProfilePictureUrl(baseUrl: null, picture: 'a.png'), isNull);
    });
  });

  group('while loading', () {
    testWidgets('the figure stands and the picture follows by itself',
        (tester) async {
      final answer = Completer<_Reply>();
      start((_) => answer.future);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      _expectFigure(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      answer.complete(_picture(_url));
      await _settle(tester);

      _expectPicture(tester);
    });

    testWidgets('a load that never ends leaves a still figure in the bar',
        (tester) async {
      start((_) => Completer<_Reply>().future);
      await tester.pumpWidget(buildTestApp(
        store: createStore(newDesign: true),
        home: Scaffold(
          body: FloatingNavigationBar(
            selected: AppDestination.dashboard,
            onSelected: (_) {},
            unreadMessages: 0,
            userIcon: _url,
          ),
        ),
      ));
      await _settle(tester);

      expect(find.byKey(ProfileAvatar.figureKey), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('pages with room for it keep their spinner', (tester) async {
      start((_) => Completer<_Reply>().future);
      await tester.pumpWidget(_app(_url, size: 104, showProgress: true));
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('a wrong answer', () {
    testWidgets('a login page is not taken for the picture', (tester) async {
      start((_) => (200, 'text/html', _loginPage));
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      _expectFigure(tester);
      expect(cachedProfilePicture(_url), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a login page leads to a new login and then the picture',
        (tester) async {
      var answers = 0;
      start((url) =>
          answers++ == 0 ? (200, 'text/html', _loginPage) : _picture(url));
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      expect(session.logins, [false, true]);
      _expectPicture(tester);
    });

    testWidgets('something that does not decode leaves the figure',
        (tester) async {
      start((_) => (200, 'image/gif', _broken));
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      _expectFigure(tester);
      expect(cachedProfilePicture(_url), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty answer leaves the figure', (tester) async {
      start((_) => (200, 'image/png', const <int>[]));
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      _expectFigure(tester);
    });

    testWidgets('a picture that goes bad later falls back to the figure',
        (tester) async {
      start(_picture);
      cacheProfilePicture(_url, MemoryImage(_broken));
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      expect(find.byKey(ProfileAvatar.figureKey), findsOneWidget);
      tester.takeException();
    });
  });

  group('after a failure', () {
    testWidgets('it tries again by itself, without any rebuild',
        (tester) async {
      start(_offline);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      _expectFigure(tester);
      expect(session.requests, hasLength(1));

      session.answer = _picture;
      await tester.pump(ProfileAvatar.retryDelays.first);
      await _settle(tester);

      expect(session.requests, hasLength(2));
      _expectPicture(tester);
    });

    testWidgets('it stops asking after a while', (tester) async {
      start(_offline);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      for (final delay in ProfileAvatar.retryDelays) {
        await tester.pump(delay);
        await _settle(tester);
      }
      final asked = session.requests.length;
      expect(asked, ProfileAvatar.retryDelays.length + 1);

      await tester.pump(const Duration(hours: 1));
      await _settle(tester);

      expect(session.requests, hasLength(asked));
      _expectFigure(tester);
    });

    testWidgets('coming back online loads it at once', (tester) async {
      start(_offline);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      for (final delay in ProfileAvatar.retryDelays) {
        await tester.pump(delay);
        await _settle(tester);
      }

      session.answer = _picture;
      retryProfilePictures();
      await _settle(tester);

      _expectPicture(tester);
    });

    testWidgets('a pending retry does not outlive the avatar', (tester) async {
      start(_offline);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      final asked = session.requests.length;

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
      await _settle(tester);

      expect(session.requests, hasLength(asked));
    });
  });

  group('after a restart', () {
    testWidgets('a saved address waits for the session, then shows the picture',
        (tester) async {
      start(_picture);
      session.signedIn = false;
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      _expectFigure(tester);
      expect(session.requests, isEmpty);

      session.signedIn = true;
      retryProfilePictures();
      await _settle(tester);

      _expectPicture(tester);
    });
  });

  group('cache', () {
    testWidgets(
        'a known picture is there in the first frame, without a request',
        (tester) async {
      start(_picture);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      expect(session.requests, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(_url, size: 48));

      _expectPicture(tester);
      expect(session.requests, hasLength(1));
    });

    testWidgets('avatars of the same picture share one request',
        (tester) async {
      final answer = Completer<_Reply>();
      start((_) => answer.future);
      await tester.pumpWidget(const MaterialApp(
        home: Column(
          children: [
            ProfileAvatar(imageUrl: _url, size: 32),
            ProfileAvatar(imageUrl: _url, size: 48),
          ],
        ),
      ));
      await _settle(tester);
      answer.complete(_picture(_url));
      await _settle(tester);

      expect(session.requests, hasLength(1));
      expect(find.byKey(ProfileAvatar.pictureKey), findsNWidgets(2));
    });

    testWidgets('a new picture at the same address replaces the old one',
        (tester) async {
      start(_picture);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);
      final old = tester.widget<Image>(find.byKey(ProfileAvatar.pictureKey));

      forgetProfilePictures();
      retryProfilePictures();
      await _settle(tester);

      final current =
          tester.widget<Image>(find.byKey(ProfileAvatar.pictureKey));
      expect(session.requests, hasLength(2));
      expect(identical(old.image, current.image), isFalse);
    });

    testWidgets('a retry leaves a picture on the screen alone', (tester) async {
      start(_picture);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      retryProfilePictures();
      await _settle(tester);

      expect(session.requests, hasLength(1));
    });
  });

  group('another account', () {
    testWidgets('the old picture goes as soon as the address changes',
        (tester) async {
      final next = Completer<_Reply>();
      start((url) async =>
          url.endsWith('-a') ? _picture(url) : await next.future);
      await tester.pumpWidget(_app('$_url-a'));
      await _settle(tester);
      _expectPicture(tester);

      await tester.pumpWidget(_app('$_url-b'));
      await tester.pump();
      _expectFigure(tester);

      next.complete(_picture(_url));
      await _settle(tester);
      _expectPicture(tester);
    });

    testWidgets('a late answer for the old account is dropped', (tester) async {
      final late = Completer<_Reply>();
      start((url) async => url.endsWith('-a')
          ? await late.future
          : (200, 'text/plain', const <int>[]));
      await tester.pumpWidget(_app('$_url-a'));
      await _settle(tester);
      await tester.pumpWidget(_app('$_url-b'));
      await _settle(tester);

      late.complete(_picture(_url));
      await _settle(tester);

      _expectFigure(tester);
      expect(cachedProfilePicture('$_url-b'), isNull);
    });

    testWidgets('signing out leaves the figure', (tester) async {
      start(_picture);
      await tester.pumpWidget(_app(_url));
      await _settle(tester);

      await tester.pumpWidget(_app(null));
      await tester.pump();

      _expectFigure(tester);
    });
  });

  group('in the bar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required AppDestination selected,
      required Brightness brightness,
    }) async {
      final theme = ThemeData(
        colorScheme: AppPalette.scheme(brightness: brightness, amoled: false),
      );
      await tester.pumpWidget(buildTestApp(
        store: createStore(newDesign: true),
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavigationBar(
              selected: selected,
              onSelected: (_) {},
              unreadMessages: 0,
              userIcon: _url,
            ),
          ),
        ),
      ));
      await _settle(tester);
    }

    for (final brightness in Brightness.values) {
      for (final selected in const [
        AppDestination.dashboard,
        AppDestination.profile,
      ]) {
        testWidgets(
            'the picture has its full size on the '
            '${brightness.name} bar with ${selected.name} selected',
            (tester) async {
          start(_picture);
          await pumpBar(tester, selected: selected, brightness: brightness);

          _expectPicture(tester);
          final picture = find.byKey(ProfileAvatar.pictureKey);
          expect(tester.getSize(picture), const Size.square(32));
          expect(
            find.ancestor(of: picture, matching: find.byType(Opacity)),
            findsNothing,
          );
          expect(
            find.ancestor(of: picture, matching: find.byType(ColorFiltered)),
            findsNothing,
          );
          final item = find.byKey(const ValueKey('app-navigation-profile'));
          expect(tester.getCenter(picture), tester.getCenter(item));
          // It lies above the lens, which comes first in the stack.
          final lens = find.byKey(const Key('app-navigation-lens'));
          final stack = find.ancestor(of: lens, matching: find.byType(Stack));
          final children = tester.widget<Stack>(stack.first).children;
          expect(children.first.key, const Key('app-navigation-lens'));
        });
      }
    }

    test('the figure stands out on the bar and on the lens', () {
      for (final accent in AppAccent.values) {
        for (final (brightness, amoled) in const [
          (Brightness.light, false),
          (Brightness.dark, false),
          (Brightness.dark, true),
        ]) {
          final scheme = AppPalette.scheme(
            brightness: brightness,
            amoled: amoled,
            accent: accent,
          );
          final behind = brightness == Brightness.dark
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF000000);
          final bar = Color.alphaBlend(
            navigationBarTint(scheme)
                .withValues(alpha: DesignTokens.navigationBarOpacity),
            behind,
          );
          final lens = Color.alphaBlend(navigationLensFill(scheme), bar);
          for (final below in [bar, lens, navigationBarTint(scheme)]) {
            final disc = Color.alphaBlend(
              scheme.surfaceContainerHighest.withValues(alpha: 0.9),
              below,
            );
            expect(
              AppPalette.contrastRatio(scheme.onSurfaceVariant, disc),
              greaterThanOrEqualTo(3),
              reason: '$accent $brightness amoled: $amoled',
            );
          }
        }
      }
    });
  });
}
