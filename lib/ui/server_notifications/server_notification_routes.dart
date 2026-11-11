import 'dart:async';

import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/container/notifications_page_container.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:dr/ui/homework_summary_page.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart'
    show ServerNotificationCenterPage;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum ServerNotificationLinkResult { opened, needsLogin, failed }

/// Opens a validated link. Replaceable for tests.
typedef ServerNotificationLinkOpener = Future<ServerNotificationLinkResult>
    Function(ServerNotificationLink link);

void _select(Widget page, Pages id) =>
    scaffoldKey!.currentState!.selectContentWidget(page, id);

/// What each route key of the contract does. Every key maps to the page the
/// sidebar opens, the same way the sidebar does it.
final Map<String, VoidCallback> serverNotificationDestinations = {
  'homework': () => scaffoldKey!.currentState!.goHome(),
  'grades': () => actions.routingActions.showGrades(),
  'absences': () => actions.routingActions.showAbsences(),
  'calendar': () => actions.routingActions.showCalendar(),
  'examCalendar': () =>
      _select(const ExamCalendarContainer(), Pages.examCalendar),
  'classRegister': () =>
      _select(ClassRegisterPage(key: UniqueKey()), Pages.classRegister),
  'courseMaterials': () =>
      _select(CourseMaterialsPage(key: UniqueKey()), Pages.courseMaterials),
  'homeworkSummary': () =>
      _select(const HomeworkSummaryPage(), Pages.homeworkSummary),
  'certificate': () => actions.routingActions.showCertificate(),
  'messages': () => actions.routingActions.showMessages(),
  'settings': () => actions.routingActions.showSettings(),
  'profile': () => actions.routingActions.showProfile(),
};

/// Opens [link] in the app, or in the external browser for HTTPS links.
Future<ServerNotificationLinkResult> openServerNotificationLink(
  ServerNotificationLink link,
) async {
  switch (link) {
    case ExternalNotificationLink(:final uri):
      // Validated when it was parsed, so only an https URL can arrive here.
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication)
            ? ServerNotificationLinkResult.opened
            : ServerNotificationLinkResult.failed;
      } catch (_) {
        return ServerNotificationLinkResult.failed;
      }
    case InternalNotificationLink(:final routeKey):
      final destination = serverNotificationDestinations[routeKey];
      if (destination == null) return ServerNotificationLinkResult.failed;
      // Every target is a page of a signed-in register session.
      if (!serverNotifications.isLoggedIn() ||
          scaffoldKey?.currentState == null) {
        return ServerNotificationLinkResult.needsLogin;
      }
      navigatorKey?.currentState?.popUntil((route) => route.isFirst);
      destination();
      return ServerNotificationLinkResult.opened;
  }
}

/// The name the bell and the dashboard give the center in the shell
/// (`_showNotifications` in `lib/middleware/routing.dart`). Opening a message
/// from the center closes it by this name.
const _shellCenterRouteName = '/notifications';

/// The route of the center that is open in [navigator], covered or not.
Route<dynamic>? _openCenter(NavigatorState navigator) {
  Route<dynamic>? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget is ServerNotificationCenterPage) {
      found = ModalRoute.of(element);
      return;
    }
    element.visitChildren(visit);
  }

  navigator.context.visitChildElements(visit);
  return found;
}

/// Opens the center of a signed-in session inside the shell, with both
/// sources and the navigation in reach, the way the bell and the dashboard
/// open it. [initialId] opens that announcement: as a page on phones, in the
/// pane beside the list on wide windows.
///
/// An open center is not stacked a second time: without [initialId] it comes
/// to the front, with one it is replaced by a center that shows it.
///
/// Returns false where there is no shell, as while signed out; the caller
/// then opens the center the way it did before.
bool showNotificationCenterInShell({String? initialId}) {
  final nested = nestedNavKey.currentState;
  if (nested == null ||
      scaffoldKey?.currentState == null ||
      !serverNotifications.isLoggedIn()) {
    return false;
  }
  // Pages on the root navigator would cover the shell.
  navigatorKey?.currentState?.popUntil((route) => route.isFirst);
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: _shellCenterRouteName),
    builder: (_) => NotificationPageContainer(focusAppId: initialId),
  );
  final open = _openCenter(nested);
  if (open == null) {
    unawaited(nested.push(route));
    return true;
  }
  // What lies above it, such as an open detail, goes.
  nested.popUntil((candidate) => candidate == open);
  if (initialId != null) nested.replace(oldRoute: open, newRoute: route);
  return true;
}
