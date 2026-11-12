// Copyright (C) 2021 Michael Debertol
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

part of 'middleware.dart';

enum Pages {
  homework,
  grades,
  absences,
  calendar,
  examCalendar,
  classRegister,
  courseMaterials,
  homeworkSummary,
  certificate,
  messages,
  settings,
  debug,
  extras,
}

// This allows tests to just include the routingMiddleware
@visibleForTesting
final routingMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(RoutingActionsNames.showLogin, _showLogin)
      ..add(RoutingActionsNames.showRequestPassReset, _showRequestPassReset)
      ..add(RoutingActionsNames.showPassReset, _showPassReset)
      ..add(RoutingActionsNames.showChangeEmail, _showChangeEmail)
      ..add(RoutingActionsNames.showProfile, _showProfile)
      ..add(RoutingActionsNames.showNotifications, _showNotifications)
      ..add(RoutingActionsNames.showSettings, _showSettings)
      ..add(RoutingActionsNames.showDebug, _showDebug)
      ..add(RoutingActionsNames.showEditCalendarSubjectNicks,
          _showEditCalendarSubjectNicks)
      ..add(RoutingActionsNames.showEditCalendarSubstituteSettings,
          _showEditCalendarSubstituteSettings)
      ..add(RoutingActionsNames.showEditGradesAverageSettings,
          _showEditGradesAverageSettings)
      ..add(RoutingActionsNames.showCalendar, _showCalendar)
      ..add(RoutingActionsNames.showAbsences, _showAbsences)
      ..add(RoutingActionsNames.showExtras, _showExtras)
      ..add(RoutingActionsNames.showGradesChart, _showGradesChart)
      ..add(RoutingActionsNames.showGrades, _showGrades)
      ..add(RoutingActionsNames.showGradeCalculator, _showGradeCalculator)
      ..add(RoutingActionsNames.showCertificate, _showCertificate)
      ..add(RoutingActionsNames.showMessages, _showMessages)
      ..add(RoutingActionsNames.showMessage, _showMessage);

const _notificationsRoute = "/notifications";

Future<void> _showLogin(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  // The home route stays below the login page. A drawer left open there (the
  // logout button is in it) would still be open after the next sign-in, and
  // _popAll only removes routes. Close it before the login page covers it.
  final homeScaffold = scaffoldKey?.currentState?.scaffoldKey.currentState;
  if (homeScaffold != null && homeScaffold.isDrawerOpen) {
    homeScaffold.closeDrawer();
  }
  // hack since the current route is not exposed otherwise
  Route? currentRoute;
  navigatorKey!.currentState?.popUntil((route) {
    currentRoute = route;
    // by returning true here no route is actually popped.
    return true;
  });

  if (currentRoute?.settings.name != "/login") {
    unawaited(navigatorKey!.currentState?.pushNamed("/login"));
  }
}

Future<void> _showRequestPassReset(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<String> action) async {
  await api.actions.setUrl(action.payload);
  unawaited(navigatorKey!.currentState!.pushNamed("/request_pass_reset"));
  await next(action);
}

Future<void> _showPassReset(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  unawaited(navigatorKey!.currentState!.pushNamed("/pass_reset"));
  await next(action);
}

const _profileRoute = "/profile";
const _changeEmailRoute = "/change_email";
const _settingsRoute = "/settings";

/// The navigator of the new design's shell, below its navigation. Null while
/// the legacy design is chosen or there is no shell (signed out, on the login
/// page, during startup); pages then open on the root navigator as before.
NavigatorState? _shellNavigator(AppState state) =>
    state.settingsState.legacyDesign || !state.loginState.loggedIn
        ? null
        : nestedNavKey.currentState;

Route<dynamic>? _topRoute(NavigatorState navigator) {
  Route<dynamic>? top;
  // popUntil is the only way to read the current route; returning true pops
  // nothing.
  navigator.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

/// How many pages of the Profile destination (profile, change email) are open
/// in the shell. The navigation highlights "Profil" while there are any.
final ValueNotifier<int> openProfileShellPages = ValueNotifier(0);

/// A page of the Profile destination in the shell. It is pushed on top of the
/// current page like the notification center, so that going back returns
/// there and choosing a destination closes it.
class _ProfileShellRoute extends MaterialPageRoute<void> {
  _ProfileShellRoute({required String name, required super.builder})
      : super(settings: RouteSettings(name: name));

  bool _counted = false;

  @override
  void install() {
    super.install();
    if (!_counted) {
      _counted = true;
      openProfileShellPages.value++;
    }
  }

  @override
  bool didPop(void result) {
    final popped = super.didPop(result);
    // At once, as the navigation follows a pop at once as well.
    if (popped) _release();
    return popped;
  }

  @override
  void dispose() {
    // Removed without a pop, for example with the whole navigator.
    _release();
    super.dispose();
  }

  void _release() {
    if (!_counted) return;
    _counted = false;
    openProfileShellPages.value--;
  }
}

void _pushProfileShellPage(
  NavigatorState shell,
  String name,
  WidgetBuilder builder,
) {
  // Chosen again from the profile menu while it is open.
  if (_topRoute(shell)?.settings.name == name) return;
  unawaited(shell.push(_ProfileShellRoute(name: name, builder: builder)));
}

/// Closes the change-email page after the address was changed.
void _closeChangeEmail() {
  final shell = nestedNavKey.currentState;
  final root = navigatorKey?.currentState;
  if (root != null && _topRoute(root)?.settings.name == _changeEmailRoute) {
    root.pop();
  } else if (shell != null &&
      _topRoute(shell)?.settings.name == _changeEmailRoute) {
    shell.pop();
  } else {
    root?.pop();
  }
}

Future<void> _showChangeEmail(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  final shell = _shellNavigator(api.state);
  if (shell != null) {
    _pushProfileShellPage(
        shell, _changeEmailRoute, (_) => ChangeEmailContainer());
  } else {
    unawaited(navigatorKey!.currentState!.pushNamed(_changeEmailRoute));
  }
  await next(action);
}

Future<void> _showProfile(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  final shell = _shellNavigator(api.state);
  if (shell != null) {
    _pushProfileShellPage(shell, _profileRoute, (_) => ProfileContainer());
  } else {
    unawaited(navigatorKey!.currentState!.pushNamed(_profileRoute));
  }
  await api.actions.profileActions.load();
  await next(action);
}

Future<void> _showNotifications(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  // Inside the home route, so that the navigation stays in reach.
  final nested = nestedNavKey.currentState;
  if (nested != null) {
    final focus = takeNotificationCenterFocus();
    unawaited(nested.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: _notificationsRoute),
      builder: (_) => NotificationPageContainer(focusSchoolId: focus),
    )));
  } else {
    unawaited(navigatorKey!.currentState!.pushNamed(_notificationsRoute));
  }
  await next(action);
}

Future<void> _showSettings(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(const SettingsPageContainer(), Pages.settings);
  await next(action);
}

Future<void> _showDebug(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(const DebugPageContainer(), Pages.debug);
  await next(action);
}

/// Opens one page of the settings straight from the page that offers it, on
/// top of that page in the shell, so that going back returns there. Legacy
/// opens the whole settings on the root navigator, which then opens the page.
void _pushSettingsShortcut(NavigatorState shell, SettingsShortcut shortcut) {
  unawaited(shell.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: _settingsRoute),
    builder: (_) => SettingsPageContainer(shortcut: shortcut),
  )));
}

Future<void> _showEditCalendarSubjectNicks(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  final shell = _shellNavigator(api.state);
  if (shell != null) {
    _pushSettingsShortcut(shell, SettingsShortcut.subjectNicks);
  } else {
    unawaited(navigatorKey!.currentState!.pushNamed(_settingsRoute));
  }
}

Future<void> _showEditGradesAverageSettings(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  final shell = _shellNavigator(api.state);
  if (shell != null) {
    _pushSettingsShortcut(shell, SettingsShortcut.grades);
  } else {
    unawaited(navigatorKey!.currentState!.pushNamed(_settingsRoute));
  }
  await next(action);
}

Future<void> _showEditCalendarSubstituteSettings(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  final shell = _shellNavigator(api.state);
  if (shell != null) {
    _pushSettingsShortcut(shell, SettingsShortcut.substituteTeachers);
  } else {
    unawaited(navigatorKey!.currentState!.pushNamed(_settingsRoute));
  }
}

Future<void> _showCalendar(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  final monday = toMonday(now);
  await api.actions.calendarActions.setCurrentMonday(monday);
  scaffoldKey!.currentState!
      .selectContentWidget(CalendarContainer(), Pages.calendar);
  await next(action);

  // Rendering the visible week must not await the full school-year scan.
  await api.actions.calendarActions.load(monday);
  _startCalendarBackgroundLoad(api);
}

Future<void> _showGrades(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(const GradesPageContainer(), Pages.grades);
  await api.actions.gradesActions.load(api.state.gradesState.semester);
  await next(action);
}

Future<void> _showAbsences(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(const AbsencesPageContainer(), Pages.absences);
  await api.actions.absencesActions.load();
  await next(action);
}

Future<void> _showExtras(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(const ExtrasPageContainer(), Pages.extras);
  await next(action);
}

Future<void> _showCertificate(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(CertificateContainer(), Pages.certificate);
  await api.actions.certificateActions.load();
  await next(action);
}

Future<void> _showMessages(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  scaffoldKey!.currentState!
      .selectContentWidget(MessagesPageContainer(), Pages.messages);
  await api.actions.messagesActions.load();
  await next(action);
}

Future<void> _showMessage(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<int> action) async {
  for (final navigator in [
    navigatorKey?.currentState,
    nestedNavKey.currentState
  ]) {
    navigator?.popUntil((route) => route.settings.name != _notificationsRoute);
  }
  await api.actions.routingActions.showMessages();
  await next(action);
}

const _gradesChartRoute = "/gradesChart";
const _gradeCalculatorRoute = "/gradeCalculator";

/// Opens a tool of the grades page (the chart in full screen, the calculator)
/// on top of the page that offers it in the shell, so that the navigation
/// stays and going back returns there. Legacy and the app without a shell keep
/// the root routes.
void _pushGradesTool(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  String name,
  WidgetBuilder builder,
) {
  final shell = _shellNavigator(api.state);
  if (shell == null) {
    unawaited(navigatorKey!.currentState!.pushNamed(name));
    return;
  }
  // Asked for again while it is open.
  if (_topRoute(shell)?.settings.name == name) return;
  unawaited(shell.push(MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: builder,
  )));
}

Future<void> _showGradesChart(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  _pushGradesTool(api, _gradesChartRoute, (_) => const GradesChartPage());
  await next(action);
}

Future<void> _showGradeCalculator(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  _pushGradesTool(api, _gradeCalculatorRoute, (_) => const GradeCalculator());
  await api.actions.gradesActions.load(Semester.all);
  await next(action);
}
