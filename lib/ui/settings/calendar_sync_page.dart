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

part of '../settings_page_widget.dart';

// The details page of the synchronization with the device calendar.

class _CalendarSyncSettingsDetailPage extends StatelessWidget {
  const _CalendarSyncSettingsDetailPage({
    required this.calendarSyncEnabled,
    required this.calendarSyncCalendarId,
    required this.calendarsFuture,
    required this.onChangeCalendar,
    required this.onRemoveCalendarSyncEvents,
    required this.onRecreateMissingEvents,
  });

  final bool calendarSyncEnabled;
  final int? calendarSyncCalendarId;
  final Future<List<CalendarSyncCalendar>> calendarsFuture;
  final Future<void> Function() onChangeCalendar;
  final Future<void> Function() onRemoveCalendarSyncEvents;
  final Future<void> Function() onRecreateMissingEvents;

  Widget _newDesignBuild(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-calendar-sync-page'),
      title: l10n.text('settings.calendarSync.title'),
      children: [
        FutureBuilder<List<CalendarSyncCalendar>>(
          future: calendarsFuture,
          builder: (context, snapshot) {
            final calendars = snapshot.data ?? <CalendarSyncCalendar>[];
            final selectedCalendar =
                _selectedSyncCalendar(calendars, calendarSyncCalendarId);
            final missing =
                _isSyncCalendarMissing(snapshot, calendarSyncCalendarId);
            final canChange = calendarSyncEnabled && calendars.isNotEmpty;
            return SettingsSectionNew(
              title: null,
              children: [
                ListTile(
                  key: const Key('calendar-sync-calendar-picker'),
                  enabled: canChange,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(l10n.text('settings.calendarSync.select.title')),
                  subtitle: Text(
                    missing
                        ? l10n.text('settings.calendarSync.select.missing')
                        : selectedCalendar == null
                            ? l10n.text('settings.calendarSync.select.none')
                            : '${selectedCalendar.displayName}\n${selectedCalendar.accountLabel}',
                    style: missing
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                  trailing: snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: canChange
                      ? () async {
                          await onChangeCalendar();
                        }
                      : null,
                ),
              ],
            );
          },
        ),
        ValueListenableBuilder<int>(
          valueListenable: CalendarSyncService.missingEventCount,
          builder: (context, missing, _) => missing == 0 || !calendarSyncEnabled
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SettingsSectionNew(
                    title: null,
                    children: [
                      ListTile(
                        key: const Key('calendar-sync-missing-events'),
                        leading: const Icon(Icons.event_busy_outlined),
                        title: Text(l10n.missingCalendarEventsLabel(missing)),
                        subtitle: Text(
                          l10n.text('settings.calendarSync.missing.body'),
                        ),
                      ),
                      ListTile(
                        key: const Key(
                          'calendar-sync-recreate-missing-events',
                        ),
                        leading: const Icon(Icons.restore),
                        title: Text(l10n.text(
                          'settings.calendarSync.missing.recreate',
                        )),
                        onTap: () async {
                          await onRecreateMissingEvents();
                        },
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        SettingsSectionNew(
          title: null,
          children: [
            ListTile(
              key: const Key('calendar-sync-remove-events-tile'),
              leading: const Icon(Icons.delete_sweep_outlined),
              title: Text(l10n.text('settings.calendarSync.disable.remove')),
              subtitle: Text(
                l10n.text('settings.calendarSync.disable.body'),
              ),
              enabled: calendarSyncEnabled,
              onTap: calendarSyncEnabled
                  ? () async {
                      await onRemoveCalendarSyncEvents();
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _newDesignBuild(context);
    }
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-calendar-sync-page'),
      title: l10n.text('settings.calendarSync.title'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: FutureBuilder<List<CalendarSyncCalendar>>(
            future: calendarsFuture,
            builder: (context, snapshot) {
              final calendars = snapshot.data ?? <CalendarSyncCalendar>[];
              final selectedCalendar =
                  _selectedSyncCalendar(calendars, calendarSyncCalendarId);
              final missing =
                  _isSyncCalendarMissing(snapshot, calendarSyncCalendarId);
              return Column(
                children: [
                  ListTile(
                    key: const Key('calendar-sync-calendar-picker'),
                    enabled: calendarSyncEnabled && calendars.isNotEmpty,
                    title:
                        Text(l10n.text('settings.calendarSync.select.title')),
                    subtitle: Text(
                      missing
                          ? l10n.text('settings.calendarSync.select.missing')
                          : selectedCalendar == null
                              ? l10n.text('settings.calendarSync.select.none')
                              : '${selectedCalendar.displayName}\n${selectedCalendar.accountLabel}',
                    ),
                    isThreeLine: selectedCalendar != null,
                    trailing: snapshot.connectionState ==
                            ConnectionState.waiting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: calendarSyncEnabled && calendars.isNotEmpty
                        ? () async {
                            await onChangeCalendar();
                          }
                        : null,
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: CalendarSyncService.missingEventCount,
                    builder: (context, missing, _) => missing == 0 ||
                            !calendarSyncEnabled
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              ListTile(
                                key: const Key('calendar-sync-missing-events'),
                                leading: const Icon(Icons.event_busy_outlined),
                                title: Text(
                                    l10n.missingCalendarEventsLabel(missing)),
                                subtitle: Text(l10n.text(
                                    'settings.calendarSync.missing.body')),
                              ),
                              ListTile(
                                key: const Key(
                                    'calendar-sync-recreate-missing-events'),
                                title: Text(l10n.text(
                                    'settings.calendarSync.missing.recreate')),
                                onTap: () async {
                                  await onRecreateMissingEvents();
                                },
                              ),
                            ],
                          ),
                  ),
                  ListTile(
                    title:
                        Text(l10n.text('settings.calendarSync.disable.remove')),
                    subtitle: Text(
                      l10n.text('settings.calendarSync.disable.body'),
                    ),
                    enabled: calendarSyncEnabled,
                    onTap: calendarSyncEnabled
                        ? () async {
                            await onRemoveCalendarSyncEvents();
                          }
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
