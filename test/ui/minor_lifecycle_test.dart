import 'package:dio/dio.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/login_page.dart';
import 'package:dr/ui/change_email.dart';
import 'package:dr/ui/controlled_text_builder.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/login_page_content.dart';
import 'package:dr/ui/pass_reset.dart';
import 'package:dr/ui/request_pass_reset.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  for (final dismissal in ['confirm', 'cancel', 'navigation']) {
    testWidgets('2FA controller is released after $dismissal', (tester) async {
      await pumpApp(tester, store: createStore(), home: const Scaffold());
      final client = Wrapper();
      addTearDown(() => client.dio.close(force: true));
      final codes = <String?>[];
      client.dio.interceptors.insert(0, InterceptorsWrapper(
        onRequest: (options, handler) {
          final code = (options.data as Map)['two_factor'] as String?;
          codes.add(code);
          handler.resolve(Response<Object>(
            requestOptions: options,
            data: {
              'loggedIn': false,
              'error':
                  code == null ? 'two_factor_needed' : 'credentialsRejected',
            },
          ));
        },
      ));
      final login = client.login(
        'user',
        'pass',
        null,
        'https://example.com',
        logout: () {},
        configLoaded: () {},
        relogin: () {},
        addProtocolItem: (_) {},
      );
      await tester.pumpAndSettle();
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      await tester.enterText(find.byType(TextField), '123456');
      if (dismissal == 'navigation') {
        await tester.pumpWidget(const SizedBox());
      } else if (dismissal == 'confirm') {
        await tester.tap(find.byType(ElevatedButton));
      } else {
        await tester.tap(find.byType(TextButton));
      }
      await tester.pumpAndSettle();
      if (dismissal != 'navigation') await login;
      expect(codes, dismissal == 'confirm' ? [null, '123456'] : [null]);
      expect(() => controller.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    });
  }

  final pages = <String, Widget Function()>{
    'password reset': () => PassReset(
          resetPass: (_) {},
          failure: false,
          onClose: () {},
        ),
    'change email': () => ChangeEmail(changeEmail: (_, __) {}),
    'request password reset': () => RequestPassReset(
          resetPass: (_, __) {},
          failure: false,
        ),
    for (final changePassword in [false, true])
      'login changePassword=$changePassword': () => LoginPageContent(
            vm: LoginPageViewModel.from(AppState(
              (b) => b.loginState.changePassword = changePassword,
            )),
            onLogin: (_, __, ___) {},
            onChangePass: (_, __, ___, ____) {},
            setSaveNoPass: (_) {},
            onReload: () {},
            onRequestPassReset: (_) {},
            onSelectAccount: (_) {},
            onRemoveAccount: (_) {},
          ),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key} disposes owned controllers and focus nodes',
        (tester) async {
      await pumpApp(tester, store: createStore(), home: entry.value());
      await settleFor(tester);
      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      final controllers = fields.map((f) => f.controller).nonNulls.toSet();
      final nodes = fields.map((f) => f.focusNode).nonNulls.toSet();
      expect(controllers, isNotEmpty);
      await tester.enterText(find.byType(TextField).first, 'test');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      for (final controller in controllers) {
        expect(() => controller.addListener(() {}), throwsFlutterError);
      }
      for (final node in nodes) {
        expect(() => node.addListener(() {}), throwsFlutterError);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('calculator focused dialog inputs dispose on route teardown',
      (tester) async {
    await pumpApp(tester, store: createStore(), home: const GradeCalculator());
    await tester.tap(find.text('Note hinzufügen'));
    await tester.pumpAndSettle();
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    await tester.enterText(find.byType(TextField).first, '6,94');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    for (final field in fields) {
      expect(() => field.controller!.addListener(() {}), throwsFlutterError);
      expect(() => field.focusNode!.addListener(() {}), throwsFlutterError);
    }
    expect(tester.takeException(), isNull);
  });

  for (final dismissal in ['save', 'cancel', 'back', 'barrier', 'navigation']) {
    testWidgets('reminder dialog releases controller after $dismissal',
        (tester) async {
      late BuildContext hostContext;
      await pumpApp(
        tester,
        store: createStore(),
        home: Builder(builder: (context) {
          hostContext = context;
          return const Scaffold();
        }),
      );
      final result =
          showEnterReminderDialog(hostContext, initialMessage: 'Hello');
      await tester.pumpAndSettle();
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      await tester.enterText(find.byType(TextField), 'Changed');
      await tester.pump();
      if (dismissal == 'navigation') {
        await tester.pumpWidget(const SizedBox());
      } else if (dismissal == 'back') {
        Navigator.of(tester.element(find.byType(TextField))).pop();
      } else if (dismissal == 'barrier') {
        await tester.tapAt(const Offset(5, 5));
      } else {
        await tester
            .tap(find.text(dismissal == 'save' ? 'Speichern' : 'Abbrechen'));
      }
      await tester.pumpAndSettle();
      if (dismissal != 'navigation') {
        expect(await result, dismissal == 'save' ? 'Changed' : null);
      }
      expect(() => controller.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dialog controller survives result until exit transition ends',
      (tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      hostContext = context;
      return const Scaffold();
    })));
    final result = showDialog<void>(
      context: hostContext,
      builder: (_) => ControlledTextBuilder(
        builder: (context, controller) => AlertDialog(
          content: TextField(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await result;
    controller.text = 'Still mounted during exit';
    await tester.pumpAndSettle();
    expect(() => controller.addListener(() {}), throwsFlutterError);
    expect(tester.takeException(), isNull);
  });
}
