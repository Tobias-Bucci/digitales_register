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

// Diagnostics and privacy-preserving product analytics middleware.

NextActionHandler _diagnosticsMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          final name = action.name;
          var feature = 'unknown';
          if (name.startsWith('Grades')) feature = 'grades';
          if (name.startsWith('Calendar')) feature = 'timetable';
          if (name.startsWith('Absences')) feature = 'absences';
          if (name.startsWith('Dashboard')) feature = 'homework';
          if (name.startsWith('Notifications')) feature = 'notifications';
          if (name.startsWith('Login')) feature = 'authentication';
          if (name.startsWith('Settings')) feature = 'settings';
          if (name.startsWith('Messages')) feature = 'messages';
          if (name.startsWith('Profile') || name.startsWith('Certificate')) {
            feature = 'register';
          }
          diagnostics.values(
              {'feature': feature, 'parser': feature, 'operation': 'load'});
          if (feature == 'grades') {
            diagnostics.update(
                'selected_filter',
                api.state.settingsState.typeSorted
                    ? 'type_sorted'
                    : 'date_sorted');
          }
          if (feature == 'homework') {
            diagnostics.update('selected_filter',
                api.state.dashboardState.future ? 'future' : 'past');
          }
          if (feature == 'authentication' && name == 'LoginActions-login') {
            diagnostics.safeLog('login_started');
          }
          if (name.endsWith('-loaded') && feature != 'unknown') {
            diagnostics.safeLog('parser_started');
          }
          if (feature == 'notifications') {
            diagnostics.update('notification_type', 'general');
          }
          try {
            await next(action);
          } catch (e, stack) {
            diagnostics.report(
                e,
                stack,
                e is ParseException || e is FormatException
                    ? DiagnosticError.parser
                    : feature == 'authentication'
                        ? DiagnosticError.login
                        : feature == 'notifications'
                            ? DiagnosticError.notification
                            : DiagnosticError.caught);
            rethrow;
          } finally {
            try {
              diagnostics.auth(
                  loggedIn: api.state.loginState.loggedIn,
                  demo: wrapper.demoMode);
              final screen = diagnostics.context['current_screen'];
              if (screen == 'grades') {
                diagnostics.update(
                    'selected_filter',
                    api.state.settingsState.typeSorted
                        ? 'type_sorted'
                        : 'date_sorted');
              } else if (screen == 'dashboard' || screen == 'homework') {
                diagnostics.update('selected_filter',
                    api.state.dashboardState.future ? 'future' : 'past');
              }
              diagnostics.values({
                'cache_enabled': !api.state.settingsState.noDataSaving,
                'locale': api.state.settingsState.languageCode,
                'semester':
                    api.state.gradesState.semester.n?.toString() ?? 'all',
                'notification_enabled': api.state.loginState.loggedIn,
                'network_available': !api.state.noInternet
              });
            } catch (_) {
              /* Optional context must never break action dispatch. */
            }
          }
        };

Future<void> refreshProductAnalyticsContext(AppState state) async {
  final product = AnalyticsService.product;
  if (state.loginState.loggedIn && state.loginState.username != null) {
    if (state.url != wrapper.url || state.isDemo != wrapper.demoMode) return;
    // This local key is used only by encrypted identity storage, never Firebase.
    // With usage analytics off this only records the open account (nothing
    // is created or sent), so the settings can show its stored identifier
    // and a later consent identifies it at once.
    await product.identifyUser(
        jsonEncode([state.url, state.loginState.username]),
        demo: state.isDemo,
        schoolId: analyticsSchoolIdForUrl(state.url));
  }
  if (!product.enabled) return;
  final year = schoolYearForDate(now);
  await product.updateUserProperties({
    'app_language': state.settingsState.languageCode == 'lld'
        ? 'ld'
        : state.settingsState.languageCode,
    'theme': themeController.themePreference.name,
    'build_flavor':
        const String.fromEnvironment('BUILD_FLAVOR', defaultValue: 'unknown'),
    'release_channel': kDebugMode
        ? 'debug'
        : const String.fromEnvironment('RELEASE_CHANNEL',
            defaultValue: 'unknown'),
    if (state.loginState.loggedIn) 'academic_year': '${year}_${year + 1}',
    if (state.loginState.loggedIn &&
        state.profileState.sendNotificationEmails != null)
      'notifications_enabled':
          state.profileState.sendNotificationEmails.toString(),
  });
}

Future<void> submitAcademicSummary(AppState state) async {
  final product = AnalyticsService.product;
  if (!product.identityReady ||
      state.isDemo ||
      !AnalyticsService.privacy.decision.academicStatsAllowed) {
    return;
  }
  final periods = _semestersFor(state.gradesState.semester)
      .map((semester) => semester.n.toString());
  if (!product.gradeOwnership
      .matches(jsonEncode([state.url, state.loginState.username]), periods)) {
    return;
  }
  final average = overallGradeAverage(state);
  if (average == null || !average.isFinite || average < 0 || average > 10) {
    return;
  }
  final year = schoolYearForDate(now);
  var grades = 0;
  var subjects = 0;
  for (final subject in state.gradesState.subjects) {
    if (state.settingsState.ignoreForGradesAverage
        .any((name) => name.toLowerCase() == subject.name.toLowerCase())) {
      continue;
    }
    final entries = subject.basicGrades(state.gradesState.semester);
    if (entries == null) {
      return; // Never contribute an incomplete semester snapshot.
    }
    var contributes = false;
    for (final grade in entries) {
      if (!grade.cancelled &&
          grade.grade != null &&
          grade.weightPercentage < 0) {
        return;
      }
      if (grade.cancelled ||
          grade.grade == null ||
          grade.weightPercentage <= 0) {
        continue;
      }
      if (schoolYearForDate(grade.date) != year ||
          grade.grade! < 0 ||
          grade.grade! > 1000) {
        return;
      }
      grades++;
      contributes = true;
    }
    if (contributes) subjects++;
  }
  if (grades == 0 || subjects == 0) return;
  await product.logAcademicSummary({
    'academic_year': '${year}_${year + 1}',
    'semester': state.gradesState.semester.n?.toString() ?? 'year',
    'grade_average_tenths': (average * 10).round(),
    'grade_count_bucket': AnalyticsSchema.gradeCount(grades),
    'subject_count_bucket': AnalyticsSchema.subjectCount(subjects),
    // No reliable scale metadata exists; grading_scale is deliberately omitted.
    'snapshot_schema_version': 1,
  });
}

NextActionHandler _productAnalyticsMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          final product = AnalyticsService.product;
          final name = action.name;
          if (!product.enabled) {
            if ({
              'LoginActions-logout',
              'LoginActions-selectAccount',
              'LoginActions-addAccount',
              'LoginActions-removeCurrentAccount'
            }.contains(name)) {
              unawaited(product.clearIdentity());
            }
            await next(action);
            if (name == 'LoginActions-loggedIn' ||
                name == 'AppActions-setUrl') {
              await refreshProductAnalyticsContext(api.state);
            }
            return;
          }
          final before = api.state;
          final stopwatch = Stopwatch()..start();
          const routes = <String, String>{
            'RoutingActions-showLogin': 'login',
            'RoutingActions-showProfile': 'register',
            'RoutingActions-showGrades': 'grades',
            'RoutingActions-showCalendar': 'timetable',
            'RoutingActions-showAbsences': 'absences',
            'RoutingActions-showNotifications': 'notifications',
            'RoutingActions-showSettings': 'settings',
            'RoutingActions-showMessages': 'messages',
            'RoutingActions-showCertificate': 'register',
            'RoutingActions-showGradesChart': 'grades',
            'RoutingActions-showGradeCalculator': 'grade_calculator',
          };
          const loads = <String, String>{
            'GradesActions-load': 'grades',
            'CalendarActions-load': 'timetable',
            'DashboardActions-load': 'homework',
            'AbsencesActions-load': 'absences',
            'NotificationsActions-load': 'notifications',
            'MessagesActions-load': 'messages',
          };
          final feature = loads[name];
          if (name == 'LoginActions-logout' ||
              name == 'LoginActions-selectAccount' ||
              name == 'LoginActions-addAccount' ||
              name == 'LoginActions-removeCurrentAccount') {
            final eventName = name == 'LoginActions-selectAccount'
                ? 'account_switch'
                : 'logout';
            final parameters = name == 'LoginActions-selectAccount'
                ? <String, Object>{}
                : {
                    'reason': name == 'LoginActions-logout'
                        ? 'user_action'
                        : 'account_switch'
                  };
            await product.clearIdentity();
            await product.event(eventName, parameters);
          }
          if (name == 'LoginActions-login') {
            await product.clearIdentity();
            final payload = action.payload as LoginPayload;
            unawaited(product.event('login_attempt', {
              'login_provider':
                  isDemoUser(url: payload.url, username: payload.user)
                      ? 'demo'
                      : 'school_api'
            }));
          }
          final epoch = product.sessionEpoch;
          if (routes.containsKey(name)) {
            unawaited(product.screenView(routes[name]!));
            unawaited(product.event('feature_opened',
                {'feature': routes[name]!, 'source': 'navigation'}));
          }
          if (feature != null) {
            unawaited(product.event('refresh_requested',
                {'feature': feature, 'source': 'automatic'}));
          }
          try {
            await next(action);
            if (!product.isSession(epoch)) return;
            if (name == 'LoginActions-loggedIn' ||
                name == 'AppActions-setUrl') {
              await refreshProductAnalyticsContext(api.state);
              if (name == 'LoginActions-loggedIn' &&
                  !(action.payload as LoggedInPayload).offlineOnly) {
                unawaited(product.event('login_result', {
                  'result': 'success',
                  'login_provider': api.state.isDemo ? 'demo' : 'school_api'
                }));
              }
            }
            if (name == 'LoginActions-loginFailed') {
              unawaited(product.event('login_result',
                  {'result': 'unknown', 'login_provider': 'school_api'}));
            }
            if (name == 'GradesActions-setSemester') {
              unawaited(product.event('semester_changed', {
                'semester':
                    api.state.gradesState.semester.n?.toString() ?? 'year'
              }));
            }
            if (name == 'SettingsActions-setLanguage') {
              await refreshProductAnalyticsContext(api.state);
              unawaited(product.event('language_changed', {
                'language': api.state.settingsState.languageCode == 'lld'
                    ? 'ld'
                    : api.state.settingsState.languageCode
              }));
            }
            if (name == 'SettingsActions-gradesTypeSorted') {
              unawaited(product.event('sort_changed', {
                'feature': 'grades',
                'sort_id': api.state.settingsState.typeSorted
                    ? 'type_sorted'
                    : 'date_sorted'
              }));
            }
            if (name == 'DashboardActions-switchFuture') {
              unawaited(product.event('filter_changed', {
                'feature': 'homework',
                'filter_id': api.state.dashboardState.future ? 'future' : 'past'
              }));
            }
            if (name == 'SettingsActions-calendarSyncEnabled') {
              unawaited(product.event('calendar_sync_changed', {
                'enabled': api.state.settingsState.calendarSyncEnabled ? 1 : 0
              }));
            }
            if (name == 'ProfileActions-loaded' ||
                name == 'ProfileActions-sendNotificationEmails') {
              await refreshProductAnalyticsContext(api.state);
            }
            if (name == 'ProfileActions-sendNotificationEmails') {
              unawaited(product.event('notification_settings_changed', {
                'enabled': api.state.profileState.sendNotificationEmails == true
                    ? 1
                    : 0
              }));
            }
            if (name == 'CalendarActions-setCurrentMonday') {
              unawaited(product.event('feature_action',
                  {'feature': 'timetable', 'action': 'change_day'}));
            }
            if (name == 'RoutingActions-showGradesChart') {
              unawaited(product.event(
                  'tab_changed', {'feature': 'grades', 'tab_id': 'chart'}));
              unawaited(product.event('feature_action',
                  {'feature': 'grades', 'action': 'change_view'}));
            }
            if (name == 'AppActions-noInternet') {
              unawaited(product.event('error_presented',
                  {'feature': 'unknown', 'error_category': 'offline'}));
            }
            if (name == 'NotificationsActions-delete' ||
                name == 'NotificationsActions-deleteAll') {
              unawaited(product.event('feature_action',
                  {'feature': 'notifications', 'action': 'mark_read'}));
            }
            if (name == 'DashboardActions-toggleDone') {
              unawaited(product.event('feature_action',
                  {'feature': 'homework', 'action': 'toggle_done'}));
            }
            if (before.isDemo != api.state.isDemo) {
              unawaited(product.event(
                  'demo_mode_changed', {'enabled': api.state.isDemo ? 1 : 0}));
            }
            if (name == 'GradesActions-loaded' ||
                name == 'GradesActions-setSemester' ||
                name == 'SettingsActions-ignoreSubjectsForAverage') {
              await submitAcademicSummary(api.state);
            }
            if (feature != null) {
              // Dispatcher completion is not always remote completion in this legacy app.
              // Only cache/offline outcomes are asserted here; loaded actions cover remote success.
              if (before.noInternet) {
                unawaited(product.event('offline_usage',
                    {'feature': feature, 'action': 'opened_cached_data'}));
              }
            }
            const loaded = {
              'GradesActions-loaded': 'grades',
              'CalendarActions-loaded': 'timetable',
              'DashboardActions-loaded': 'homework',
              'AbsencesActions-loaded': 'absences',
              'NotificationsActions-loaded': 'notifications',
              'MessagesActions-loaded': 'messages'
            };
            if (loaded.containsKey(name)) {
              unawaited(product.event('data_source_used', {
                'feature': loaded[name]!,
                'data_source': api.state.isDemo ? 'local' : 'remote'
              }));
            }
          } catch (_) {
            if (feature != null) {
              unawaited(product.event('refresh_result', {
                'feature': feature,
                'result': 'failed',
                'data_source': 'unknown',
                'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
              }));
            }
            rethrow;
          }
        };
