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

import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reminder_link.dart';
import 'package:dr/reminder_notifications.dart';
import 'package:dr/reminder_schedule.dart';
import 'package:dr/runtime_trace.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

const mensaReminderPayload = 'dr-reminder:mensa';

Future<bool> _openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Reacts to a tapped reminder, whether the app was running or the tap started
/// it. The mensa reminder opens [mensaUrl], the user's own link. Without a link,
/// or if it cannot be opened, the dashboard is shown instead. A value that is
/// not a valid link is never opened.
Future<void> openReminderTarget(
  String? payload, {
  required String mensaUrl,
  required VoidCallback openDashboard,
  Future<bool> Function(Uri uri) launch = _openExternally,
}) async {
  if (payload != mensaReminderPayload) return;
  final link = normalizeReminderLink(mensaUrl);
  if (link == null || link.isEmpty) return openDashboard();
  var opened = false;
  try {
    opened = await launch(Uri.parse(link));
  } catch (error) {
    runtimeTrace('Reminders', 'open-link-failed',
        detail: 'type=${error.runtimeType}');
  }
  if (!opened) openDashboard();
}

/// Reminders of all upcoming tests and exams. Ids depend on the assessment and
/// the day, so a moved assessment replaces its reminders and a deleted one
/// loses them. Times that have passed are not planned.
List<PlannedReminder> planAssessmentReminders(
  AppState state,
  AppLocalizations l10n,
  DateTime now,
) {
  final reminders = <int, PlannedReminder>{};
  for (final assessment in examAssessments(state)) {
    final type = assessment.type?.trim() ?? '';
    final name =
        type.isEmpty ? l10n.text('reminders.assessment.fallback') : type;
    final subject = assessment.subject?.trim() ?? '';
    for (final days in state.settingsState.assessmentReminderDays) {
      final at = assessmentReminderTime(
        assessment.date,
        days,
        state.settingsState.assessmentReminderMinuteOfDay,
      );
      if (!at.isAfter(now)) continue;
      final id = reminderNotificationId(
        [state.url, state.loginState.username, assessment.id, days],
      );
      reminders[id] = PlannedReminder(
        id: id,
        channel: ReminderChannel.assessment,
        channelName: l10n.text('reminders.assessment.setting'),
        at: at,
        title: l10n.text(
          days == 1
              ? 'reminders.assessment.tomorrow'
              : 'reminders.assessment.inDays',
          args: {'type': name, 'days': '$days'},
        ),
        body: subject.isEmpty
            ? l10n.text('reminders.assessment.noSubject')
            : subject,
      );
    }
  }
  return reminders.values.toList();
}

/// Everything the user should currently be reminded of.
List<PlannedReminder> planReminders(
  AppState state,
  AppLocalizations l10n, {
  DateTime? now,
}) {
  final settings = state.settingsState;
  return [
    // The dates of the demo guest are made up.
    if (settings.assessmentRemindersEnabled && !appClock.isDemoMode)
      ...planAssessmentReminders(state, l10n, now ?? DateTime.now()),
    if (settings.mensaReminderEnabled)
      PlannedReminder(
        id: reminderNotificationId('mensa'),
        channel: ReminderChannel.daily,
        channelName: l10n.text('reminders.mensa.setting'),
        at: DateTime(
          2000,
          1,
          1,
          settings.mensaReminderMinuteOfDay ~/ 60,
          settings.mensaReminderMinuteOfDay % 60,
        ),
        title: l10n.text('reminders.mensa.title'),
        body: l10n.text('reminders.mensa.body'),
        repeatsDaily: true,
        payload: mensaReminderPayload,
      ),
  ];
}

final reminderSync = ReminderSync(sync: reminderNotifications.sync);

/// Keeps the scheduled reminders equal to the app state. Listening to the state
/// instead of single actions covers every way data can change: loading, adding,
/// editing and deleting entries, settings, and switching accounts.
class ReminderSync {
  ReminderSync({
    required this.sync,
    Future<AppLocalizations> Function(AppState state)? localizations,
    this.debounce = const Duration(seconds: 1),
  }) : _localizations = localizations ?? _localizationsFor;

  final Future<void> Function(List<PlannedReminder> reminders) sync;
  final Future<AppLocalizations> Function(AppState state) _localizations;
  final Duration debounce;

  StreamSubscription<AppState>? _subscription;
  Timer? _timer;
  AppState? _state;

  /// Whether a session was seen since the app started. Before the automatic
  /// sign-in is done, being signed out says nothing about the reminders.
  bool _hadSession = false;

  static Future<AppLocalizations> _localizationsFor(AppState state) =>
      AppLocalizations.load(
        AppLanguage.fromCode(state.settingsState.languageCode).locale,
      );

  void attach(Stream<AppState> states, AppState initial) {
    _state = initial;
    unawaited(_subscription?.cancel());
    _subscription = states.listen((state) {
      final changed = _inputs(state) != _inputs(_state!);
      _state = state;
      if (changed) {
        _timer?.cancel();
        _timer = Timer(debounce, () => unawaited(refresh()));
      }
    });
  }

  /// Only what can change a reminder, so that the frequent unrelated state
  /// changes cost one comparison.
  Object _inputs(AppState state) {
    final settings = state.settingsState;
    return (
      state.loginState.loggedIn,
      state.loginState.username,
      state.url,
      state.dashboardState.allDays,
      settings.languageCode,
      settings.mensaReminderEnabled,
      settings.mensaReminderMinuteOfDay,
      settings.assessmentRemindersEnabled,
      settings.assessmentReminderDays,
      settings.assessmentReminderMinuteOfDay,
    );
  }

  /// Plans again. Also used when the app returns to the foreground, because
  /// the date or the time zone may have changed in the meantime.
  Future<void> refresh() async {
    final state = _state;
    if (state == null) return;
    try {
      if (state.loginState.loggedIn) {
        _hadSession = true;
        await sync(planReminders(state, await _localizations(state)));
      } else if (_hadSession) {
        // Reminders belong to whoever uses the app; nobody does after a logout.
        _hadSession = false;
        await sync(const []);
      }
    } catch (error) {
      // Optional functionality must never disturb the app.
      runtimeTrace('Reminders', 'sync-failed',
          detail: 'type=${error.runtimeType}');
    }
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
  }
}
