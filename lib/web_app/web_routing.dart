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

import 'package:dr/middleware/middleware.dart' show Pages;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Browser addresses of the web app.
///
/// The app navigates with its own pages (Navigator 1.0 and the shell's
/// [Pages]). In the browser each page also gets a readable path, so a page
/// can be bookmarked, shared and reloaded:
///
/// - The path follows the open page (`/grades`, `/calendar`, ...).
/// - Opening or reloading a path signs in as usual (stored login or the login
///   page) and then opens that page. Unknown paths open the dashboard.
/// - The browser's back button goes back inside the app, like Android's.
///
/// None of this runs in the native app.
// ignore: avoid_classes_with_only_static_members
abstract final class WebRoutes {
  /// Path for each page; the keys of [destinationKeys] open them.
  static const Map<Pages, String> pagePaths = {
    Pages.homework: '/',
    Pages.grades: '/grades',
    Pages.absences: '/absences',
    Pages.calendar: '/calendar',
    Pages.examCalendar: '/exams',
    Pages.classRegister: '/class-register',
    Pages.courseMaterials: '/course-materials',
    Pages.homeworkSummary: '/homework',
    Pages.certificate: '/certificate',
    Pages.messages: '/messages',
    Pages.settings: '/settings',
    Pages.extras: '/extras',
  };

  /// Route keys of `serverNotificationDestinations` for each path.
  static const Map<String, String> destinationKeys = {
    '/': 'homework',
    '/grades': 'grades',
    '/absences': 'absences',
    '/calendar': 'calendar',
    '/exams': 'examCalendar',
    '/class-register': 'classRegister',
    '/course-materials': 'courseMaterials',
    '/homework': 'homeworkSummary',
    '/certificate': 'certificate',
    '/messages': 'messages',
    '/settings': 'settings',
    '/extras': 'extras',
    '/profile': 'profile',
  };

  /// The destination key for a browser path, or null (dashboard).
  static String? destinationForPath(String path) {
    var p = path.toLowerCase();
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    final key = destinationKeys[p];
    return key == 'homework' ? null : key;
  }
}

/// Keeps the address bar in step with the app and opens the page of the
/// address the web app was started with. A no-op in native builds.
class WebUrlSync extends NavigatorObserver {
  WebUrlSync._();

  static final WebUrlSync instance = WebUrlSync._();

  Pages _page = Pages.homework;
  String? _pendingDestination;
  bool _started = false;

  /// Reads the address the app was opened with. Call once before runApp.
  void start() {
    if (!kIsWeb || _started) return;
    _started = true;
    _pendingDestination = WebRoutes.destinationForPath(Uri.base.path);
  }

  /// The page that a start-up address asks for, once. Null afterwards.
  String? takePendingDestination() {
    final d = _pendingDestination;
    _pendingDestination = null;
    return d;
  }

  bool get hasPendingDestination => _pendingDestination != null;

  /// The shell switched to [page].
  void pageChanged(Pages page) {
    if (!kIsWeb) return;
    _page = page;
    _publish();
  }

  /// Back on the login page or signed out: the address shows the login.
  void signedOut() {
    if (!kIsWeb) return;
    _page = Pages.homework;
  }

  void _publish() {
    final path = WebRoutes.pagePaths[_page] ?? '/';
    unawaited(SystemNavigator.routeInformationUpdated(
      uri: Uri(path: path),
      replace: true,
    ));
  }

  // The root navigator reports its own route names ('/', '/login', ...) to the
  // browser. Once the home route is on top again, show the page path instead.
  void _afterRootChange(Route<dynamic>? top) {
    if (!kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (top?.settings.name == '/') _publish();
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _afterRootChange(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _afterRootChange(previousRoute);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // A new session starts on the dashboard, whatever the last one showed.
    if (route.settings.name == '/login') signedOut();
    _afterRootChange(route);
  }
}
