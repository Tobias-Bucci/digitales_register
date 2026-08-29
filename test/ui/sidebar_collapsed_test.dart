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

import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/app_popup_button.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('collapsed tablet sidebar shows no username text',
      (tester) async {
    final store = createStore(initialState: AppState(), withMiddleware: true);

    await tester.pumpWidget(
      buildTestApp(
        store: store,
        appNavigatorKey: GlobalKey<NavigatorState>(),
        messengerKey: GlobalKey<ScaffoldMessengerState>(),
        home: const Scaffold(
          body: Sidebar(
            tabletMode: true,
            drawerExpanded: false,
            onDrawerExpansionChange: _noopDrawerCallback,
            username: 'Anna Beispiel',
            userIcon: null,
            goHome: _noopVoidCallback,
            currentSelected: Pages.homework,
            showGrades: _noopVoidCallback,
            showAbsences: _noopVoidCallback,
            showCalendar: _noopVoidCallback,
            showExamCalendar: _noopVoidCallback,
            showClassRegister: _noopVoidCallback,
            showCourseMaterials: _noopVoidCallback,
            showHomeworkSummary: _noopVoidCallback,
            showCertificate: _noopVoidCallback,
            showMessages: _noopVoidCallback,
            showProfile: _noopVoidCallback,
            showSettings: _noopVoidCallback,
            logout: _noopVoidCallback,
            otherAccounts: <String>[],
            selectAccount: _noopSelectAccount,
            addAccount: _noopVoidCallback,
            removeCurrentAccount: _noopVoidCallback,
            passwordSavingEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settleFor(tester);

    expect(find.byType(ProfileAvatar), findsOneWidget);
    expect(find.text('Anna Beispiel'), findsNothing);
  });

  testWidgets('collapsed items are square and labels fade in while dragging',
      (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        store: createStore(initialState: AppState(), withMiddleware: true),
        appNavigatorKey: GlobalKey<NavigatorState>(),
        messengerKey: GlobalKey<ScaffoldMessengerState>(),
        home: const Scaffold(
          body: Sidebar(
            tabletMode: true,
            drawerExpanded: false,
            onDrawerExpansionChange: _noopDrawerCallback,
            username: 'Anna Beispiel',
            userIcon: null,
            goHome: _noopVoidCallback,
            currentSelected: Pages.homework,
            showGrades: _noopVoidCallback,
            showAbsences: _noopVoidCallback,
            showCalendar: _noopVoidCallback,
            showExamCalendar: _noopVoidCallback,
            showClassRegister: _noopVoidCallback,
            showCourseMaterials: _noopVoidCallback,
            showHomeworkSummary: _noopVoidCallback,
            showCertificate: _noopVoidCallback,
            showMessages: _noopVoidCallback,
            showProfile: _noopVoidCallback,
            showSettings: _noopVoidCallback,
            logout: _noopVoidCallback,
            otherAccounts: <String>[],
            selectAccount: _noopSelectAccount,
            addAccount: _noopVoidCallback,
            removeCurrentAccount: _noopVoidCallback,
            passwordSavingEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedButtonSize = tester.getSize(
      find.byKey(const ValueKey('collapsible-sidebar-selected-box')),
    );
    expect(selectedButtonSize.width, selectedButtonSize.height);

    Opacity labelOpacity() => tester.widget<Opacity>(
          find
              .ancestor(
                of: find.text('Noten'),
                matching: find.byType(Opacity),
              )
              .first,
        );

    expect(labelOpacity().opacity, 0);

    final sidebar = find.byType(CollapsibleSidebar);
    final gesture = await tester.startGesture(
      Offset(30, tester.getCenter(sidebar).dy),
    );
    // The first movement wins the horizontal gesture arena; the second one
    // then updates the sidebar width while the pointer is still held down.
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    expect(labelOpacity().opacity, greaterThan(0));
    expect(labelOpacity().opacity, lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('long press on the active account confirms its removal',
      (tester) async {
    var removalRequested = false;

    await tester.pumpWidget(
      buildTestApp(
        store: createStore(initialState: AppState(), withMiddleware: true),
        appNavigatorKey: GlobalKey<NavigatorState>(),
        messengerKey: GlobalKey<ScaffoldMessengerState>(),
        home: Scaffold(
          body: Sidebar(
            tabletMode: false,
            drawerExpanded: true,
            onDrawerExpansionChange: _noopDrawerCallback,
            username: 'Anna Beispiel',
            userIcon: null,
            goHome: _noopVoidCallback,
            currentSelected: Pages.homework,
            showGrades: _noopVoidCallback,
            showAbsences: _noopVoidCallback,
            showCalendar: _noopVoidCallback,
            showExamCalendar: _noopVoidCallback,
            showClassRegister: _noopVoidCallback,
            showCourseMaterials: _noopVoidCallback,
            showHomeworkSummary: _noopVoidCallback,
            showCertificate: _noopVoidCallback,
            showMessages: _noopVoidCallback,
            showProfile: _noopVoidCallback,
            showSettings: _noopVoidCallback,
            logout: _noopVoidCallback,
            otherAccounts: const <String>[],
            selectAccount: _noopSelectAccount,
            addAccount: _noopVoidCallback,
            removeCurrentAccount: () => removalRequested = true,
            passwordSavingEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppPopupButton<int>)).height,
      greaterThanOrEqualTo(38),
    );

    await tester.longPress(find.text('Anna Beispiel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Konto entfernen'));
    await tester.pumpAndSettle();
    expect(removalRequested, isTrue);
  });
}

void _noopVoidCallback() {}

void _noopDrawerCallback(bool _) {}

void _noopSelectAccount(int _) {}
