import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:dr/ui/homework_summary_page.dart';
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
