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

import 'dart:async';
import 'dart:convert';

import 'package:badges/badges.dart' as badge;
import 'package:built_collection/built_collection.dart';
import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/homework_filter_container.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/tutorial/tutorial_target.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';

typedef AddReminderCallback = void Function(Day day, String reminder);
typedef EditReminderCallback = void Function(
  Homework hw,
  Day day,
  String reminder,
);
typedef AsyncCallback = Future<void> Function();
typedef RemoveReminderCallback = void Function(Homework hw, Day day);
typedef ToggleDoneCallback = void Function(Homework hw, bool done);
typedef MarkAsNotNewOrChangedCallback = void Function(Homework hw);
typedef MarkDeletedHomeworkAsSeenCallback = void Function(Day day);
typedef OpenCalendarAtCallback = Future<void> Function(DateTime date);

const _localReminderAssessmentHintKey = 'localReminderAssessmentHintShown';
const _gradeDeadlineOverridesKey = 'gradeDeadlineOverrides';

class DaysWidget extends StatefulWidget {
  final DaysViewModel vm;

  final MarkAsNotNewOrChangedCallback markAsSeenCallback;
  final MarkDeletedHomeworkAsSeenCallback markDeletedHomeworkAsSeenCallback;
  final VoidCallback markAllAsSeenCallback;
  final AddReminderCallback addReminderCallback;
  final EditReminderCallback editReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final VoidCallback onSwitchFuture;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AsyncCallback refresh;
  final VoidCallback refreshNoInternet;
  final AttachmentCallback onOpenAttachment;
  final OpenCalendarAtCallback openCalendarAt;

  const DaysWidget({
    super.key,
    required this.vm,
    required this.markAsSeenCallback,
    required this.markDeletedHomeworkAsSeenCallback,
    required this.addReminderCallback,
    required this.editReminderCallback,
    required this.removeReminderCallback,
    required this.markAllAsSeenCallback,
    required this.onSwitchFuture,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.refresh,
    required this.refreshNoInternet,
    required this.onOpenAttachment,
    required this.openCalendarAt,
  });
  @override
  _DaysWidgetState createState() => _DaysWidgetState();
}

class _DaysWidgetState extends State<DaysWidget> {
  final controller = AutoScrollController(suggestedRowHeight: 100);
  String? _favoriteSubject;
  bool _showEmptyDays = true;
  Map<String, DateTime> _gradeDeadlineOverrides = <String, DateTime>{};
  int _gradeDeadlineCount = 2;

  bool _afterFirstFrame = false;

  final List<int> _targets = [];
  final List<int> _focused = [];
  final Map<int, int> _dayStartIndices = {};
  final Map<int, Homework> _homeworkIndexes = {};
  final Map<int, Day> _dayIndexes = {};

  final ValueNotifier<bool> _showScrollUp = ValueNotifier(false);
  bool _reachedHomeworksUpdateScheduled = false;

  Future<void> _loadGradeDeadlineOverrides() async {
    final raw = (await SharedPreferences.getInstance())
        .getString(_gradeDeadlinePreferenceStorageKey());
    if (raw == null) return;
    final decoded = getMap(raw);
    if (decoded == null) return;
    final values = <String, DateTime>{};
    for (final entry in decoded.entries) {
      final date = DateTime.tryParse(entry.value.toString());
      if (date != null) values[entry.key.toString()] = date;
    }
    final storedCount = int.tryParse(decoded['count']?.toString() ?? '');
    if (mounted) {
      setState(() {
        _gradeDeadlineOverrides = values;
        _gradeDeadlineCount = storedCount == 1 ? 1 : 2;
      });
    }
  }

  String _gradeDeadlinePreferenceStorageKey() {
    try {
      return userScopedStorageKey(_gradeDeadlineOverridesKey);
    } catch (_) {
      return _gradeDeadlineOverridesKey;
    }
  }

  SchoolTimeline _schoolTimeline() {
    final timeline = SchoolTimeline.fromCalendarData(
      dashboardDays: widget.vm.schoolTimelineDays,
      calendarDays: widget.vm.schoolTimelineCalendarDays,
    ).withGradeDeadlineDefaults(
      appClock.now,
      overrides: _gradeDeadlineOverrides,
    );
    if (_gradeDeadlineCount == 2) return timeline;
    return SchoolTimeline(
      holidays: timeline.holidays,
      gradeDeadlines: timeline.gradeDeadlines
          .where((deadline) => deadline.preferenceKey?.endsWith(':1') ?? true)
          .toList(),
      schoolYearStart: timeline.schoolYearStart,
    );
  }

  Future<void> _editGradeDeadline(GradeDeadline deadline) async {
    var count = _gradeDeadlineCount;
    final candidates = SchoolTimeline.fromCalendarData(
      dashboardDays: widget.vm.schoolTimelineDays,
      calendarDays: widget.vm.schoolTimelineCalendarDays,
    )
        .withGradeDeadlineDefaults(appClock.now,
            overrides: _gradeDeadlineOverrides)
        .gradeDeadlines
        .where((item) => !item.date.isBefore(
            DateTime(appClock.now.year, appClock.now.month, appClock.now.day)))
        .take(2)
        .toList();
    if (candidates.isEmpty) candidates.add(deadline);
    while (candidates.length < 2) {
      final first = candidates.first;
      candidates.add(GradeDeadline(
        name: '2. Notenschluss',
        date: first.date.add(const Duration(days: 120)),
        preferenceKey: first.preferenceKey?.replaceFirst(':1', ':2'),
      ));
    }
    final dates = candidates.map((item) => item.date).toList();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.t('tutorial.deadlineDialog.title')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 1,
                    label: Text(context.t('tutorial.deadlineDialog.one'))),
                ButtonSegment(
                    value: 2,
                    label: Text(context.t('tutorial.deadlineDialog.two'))),
              ],
              selected: {count},
              onSelectionChanged: (value) =>
                  setDialogState(() => count = value.first),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < count; index++)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(context.t('tutorial.deadlineDialog.date',
                    args: {'number': '${index + 1}'})),
                subtitle: Text(MaterialLocalizations.of(context)
                    .formatMediumDate(dates[index])),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: dates[index],
                    firstDate: DateTime(appClock.now.year - 1),
                    lastDate:
                        DateTime(appClock.now.year + 2, DateTime.december, 31),
                  );
                  if (selected != null) {
                    setDialogState(() => dates[index] = selected);
                  }
                },
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.t('common.cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.t('button.save'))),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    final updated = <String, DateTime>{..._gradeDeadlineOverrides};
    for (var index = 0; index < count; index++) {
      final key = candidates[index].preferenceKey;
      if (key != null) {
        updated[key] =
            DateTime(dates[index].year, dates[index].month, dates[index].day);
      }
    }
    setState(() {
      _gradeDeadlineOverrides = updated;
      _gradeDeadlineCount = count;
    });
    await (await SharedPreferences.getInstance()).setString(
      _gradeDeadlinePreferenceStorageKey(),
      jsonEncode(<String, Object>{
        'count': count,
        ...updated.map((key, value) => MapEntry(key, value.toIso8601String())),
      }),
    );
  }

  void _updateShowScrollUp() {
    if (controller.hasClients) {
      _showScrollUp.value = controller.offset > 250;
    }
  }

  double? _distanceToItem(int item) {
    final ctx = controller.tagMap[item]?.context;
    final renderObject = ctx?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) return null;
      var offsetToReveal = viewport.getOffsetToReveal(renderObject, 0.5).offset;
      if (offsetToReveal < 0) offsetToReveal = 0;
      final currentOffset = controller.offset;
      return (offsetToReveal - currentOffset).abs();
    }
    return null;
  }

  void _updateReachedHomeworks() {
    for (final target in _targets.toList()) {
      final distance = _distanceToItem(target);
      if (distance != null && distance < 50) {
        _focused.add(target);
        _targets.remove(target);
        controller.highlight(
          target,
          highlightDuration: const Duration(milliseconds: 500),
          cancelExistHighlights: false,
        );
        if (_targets.isEmpty) setState(() {});
      }
    }
    for (final focusedItem in _focused.toList()) {
      final distance = _distanceToItem(focusedItem);
      if (distance == null || distance > 50) {
        _focused.remove(focusedItem);
        if (_dayIndexes.containsKey(focusedItem)) {
          widget.markDeletedHomeworkAsSeenCallback(_dayIndexes[focusedItem]!);
        } else if (_homeworkIndexes.containsKey(focusedItem)) {
          widget.markAsSeenCallback(_homeworkIndexes[focusedItem]!);
        } else {
          assert(
            false,
            "A target index should either be a new/changed homework or a day (deleted homework)",
          );
        }
      }
    }
  }

  void update() {
    _updateShowScrollUp();
    _updateReachedHomeworks();
  }

  void _scheduleReachedHomeworksUpdate() {
    if (_reachedHomeworksUpdateScheduled) return;
    _reachedHomeworksUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reachedHomeworksUpdateScheduled = false;
      if (mounted) update();
    });
  }

  List<String> _availableFavoriteSubjects() {
    return filterAvailableFavoriteSubjects(
      widget.vm.favoriteSubjects,
      widget.vm.days.expand(
        (day) => [
          ...day.homework.map((homework) => homework.label),
          ...day.deletedHomework.map((homework) => homework.label),
        ],
      ),
    );
  }

  String? _resolvedFavoriteSubject(List<String> availableFavoriteSubjects) {
    final favoriteSubject = _favoriteSubject;
    if (favoriteSubject == null) {
      return null;
    }
    return findSubjectIgnoreCase(availableFavoriteSubjects, favoriteSubject);
  }

  List<Day> _filteredDays(String? favoriteSubject) {
    final shouldHideEmptyDays = !_showEmptyDays || favoriteSubject != null;
    final filteredDays = favoriteSubject == null
        ? widget.vm.days.toList()
        : widget.vm.days
            .map(
              (day) => day.rebuild(
                (b) => b
                  ..homework.replace(
                    day.homework.where(
                      (homework) => matchesFavoriteSubject(
                          homework.label, favoriteSubject),
                    ),
                  )
                  ..deletedHomework.replace(
                    day.deletedHomework.where(
                      (homework) => matchesFavoriteSubject(
                          homework.label, favoriteSubject),
                    ),
                  ),
              ),
            )
            .toList();

    if (!shouldHideEmptyDays) {
      return filteredDays;
    }

    return filteredDays
        .where(
          (day) => day.homework.isNotEmpty || day.deletedHomework.isNotEmpty,
        )
        .toList();
  }

  void updateValues(List<Day> visibleDays) {
    _targets.clear();
    _focused.clear();
    _dayStartIndices.clear();
    _homeworkIndexes.clear();
    _dayIndexes.clear();
    var index = 0;
    var dayIndex = 0;
    for (final day in visibleDays) {
      _dayStartIndices[dayIndex] = index;
      if (day.deletedHomework.any((h) => h.isChanged)) {
        _targets.add(index);
        _dayIndexes[index] = day;
      }
      index++;
      for (final hw in day.homework) {
        if (hw.isNew || hw.isChanged) {
          _targets.add(index);
        }
        _homeworkIndexes[index] = hw;
        index++;
      }
      dayIndex++;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadGradeDeadlineOverrides());
    updateValues(widget.vm.days.toList());
    controller.addListener(() {
      update();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      update();
      _afterFirstFrame = true;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(DaysWidget oldWidget) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tutorialService.observeDashboardDays(widget.vm.days)) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !controller.hasClients) return;
          for (final entry in _homeworkIndexes.entries) {
            final day = widget.vm.days.where((value) =>
                value.homework.any((item) => item.id == entry.value.id));
            if (day.isNotEmpty &&
                tutorialService.isCreatedReminder(day.first, entry.value)) {
              unawaited(controller.scrollToIndex(entry.key,
                  preferPosition: AutoScrollPosition.middle));
              break;
            }
          }
        });
      }
    });
    final availableFavoriteSubjects = _availableFavoriteSubjects();
    updateValues(
        _filteredDays(_resolvedFavoriteSubject(availableFavoriteSubjects)));
    // New dashboard data replaces AutoScrollTag children. Their render boxes
    // are not laid out until the following frame, so geometry must not be read
    // synchronously from didUpdateWidget.
    _scheduleReachedHomeworksUpdate();

    super.didUpdateWidget(oldWidget);
  }

  Widget getItem(
    List<Day> visibleDays,
    int n, {
    required bool isLast,
    required bool showLastFetched,
    required List<String> availableFavoriteSubjects,
    required String? activeFavoriteSubject,
  }) {
    if (n == 0) {
      final timeline = _schoolTimeline();
      return TutorialTarget(
        id: 'dashboard-page',
        child: DashboardHeader(
          future: widget.vm.future,
          onSwitchFuture: widget.onSwitchFuture,
          favoriteSubjects: availableFavoriteSubjects,
          selectedFavoriteSubject: activeFavoriteSubject,
          onFavoriteSubjectChanged: (favoriteSubject) {
            setState(() {
              _favoriteSubject = favoriteSubject;
              updateValues(_filteredDays(favoriteSubject));
              update();
            });
          },
          showEmptyDays: _showEmptyDays,
          onShowEmptyDaysChanged: (value) {
            setState(() {
              _showEmptyDays = value;
              updateValues(_filteredDays(activeFavoriteSubject));
              update();
            });
          },
          subjectThemes: widget.vm.subjectThemes,
          schoolTimeline: timeline,
          openCalendarAt: widget.openCalendarAt,
          editGradeDeadline: _editGradeDeadline,
        ),
      );
    }
    if (isLast) {
      return const SizedBox(
        height: 160,
      );
    }
    if (n.isEven) {
      return const Divider(
        height: 16,
      );
    }
    final itemIndex = (n - 1) ~/ 2;
    return DayWidget(
      day: visibleDays[itemIndex],
      vm: widget.vm,
      controller: controller,
      index: _dayStartIndices[itemIndex]!,
      addReminderCallback: widget.addReminderCallback,
      editReminderCallback: widget.editReminderCallback,
      removeReminderCallback: widget.removeReminderCallback,
      toggleDoneCallback: widget.toggleDoneCallback,
      setDoNotAskWhenDeleteCallback: widget.setDoNotAskWhenDeleteCallback,
      onOpenAttachment: widget.onOpenAttachment,
      colorBorders: widget.vm.colorBorders,
      colorTestsInRed: widget.vm.colorTestsInRed,
      subjectThemes: widget.vm.subjectThemes,
      allSubjects: widget.vm.allSubjects,
      showLastFetched: showLastFetched,
    );
  }

  void _markVisibleAsSeen(List<Day> visibleDays) {
    for (final day in visibleDays) {
      if (day.deletedHomework.any((homework) => homework.isChanged)) {
        widget.markDeletedHomeworkAsSeenCallback(day);
      }
      for (final homework in day.homework) {
        if (homework.isNew || homework.isChanged) {
          widget.markAsSeenCallback(homework);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    tutorialService.dashboardFuture = widget.vm.future;
    final l10n = context.l10n;
    final availableFavoriteSubjects = _availableFavoriteSubjects();
    final activeFavoriteSubject =
        _resolvedFavoriteSubject(availableFavoriteSubjects);
    final visibleDays = _filteredDays(activeFavoriteSubject);
    final noInternet = widget.vm.noInternet;
    final noEntries = visibleDays.isEmpty;
    final schoolTimeline = _schoolTimeline();
    Widget body;
    if (noEntries) {
      Widget fullScreenBody;
      if (widget.vm.loading && widget.vm.days.isEmpty) {
        fullScreenBody = const CircularProgressIndicator();
      } else if (activeFavoriteSubject != null && widget.vm.days.isNotEmpty) {
        fullScreenBody = Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.text('dashboard.noEntriesFavorite'),
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        );
      } else if (noInternet) {
        fullScreenBody = const NoInternet();
      } else {
        fullScreenBody = Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.text('dashboard.noEntries'),
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        );
      }
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
              child: DashboardHeader(
            future: widget.vm.future,
            onSwitchFuture: widget.onSwitchFuture,
            favoriteSubjects: availableFavoriteSubjects,
            selectedFavoriteSubject: activeFavoriteSubject,
            onFavoriteSubjectChanged: (favoriteSubject) {
              setState(() {
                _favoriteSubject = favoriteSubject;
                updateValues(_filteredDays(favoriteSubject));
                update();
              });
            },
            showEmptyDays: _showEmptyDays,
            onShowEmptyDaysChanged: (value) {
              setState(() {
                _showEmptyDays = value;
                updateValues(_filteredDays(activeFavoriteSubject));
                update();
              });
            },
            subjectThemes: widget.vm.subjectThemes,
            schoolTimeline: schoolTimeline,
            openCalendarAt: widget.openCalendarAt,
            editGradeDeadline: _editGradeDeadline,
          )),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: fullScreenBody),
          ),
        ],
      );
    } else {
      UtcDateTime? lastFetched;
      // If not all days were fetched at the same time we want to show a string
      // for each day individually.
      bool daysShouldShowLastFetched = false;
      if (visibleDays.first.lastRequested == visibleDays.last.lastRequested) {
        lastFetched = visibleDays.first.lastRequested;
      } else {
        daysShouldShowLastFetched = true;
      }
      body = LastFetchedOverlay(
        noInternet: widget.vm.noInternet,
        lastFetched: lastFetched,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          controller: controller,
          // Times two for the divider, minus one because there's no divider after the last item.
          // The first item is the DashboardHeader, the last one a SizedBox (a spacer).
          itemCount: (visibleDays.length * 2 - 1) + 2,
          itemBuilder: (context, n) {
            return getItem(
              visibleDays,
              n,
              isLast: n == (visibleDays.length * 2 - 1) + 1,
              showLastFetched:
                  widget.vm.noInternet && daysShouldShowLastFetched,
              availableFavoriteSubjects: availableFavoriteSubjects,
              activeFavoriteSubject: activeFavoriteSubject,
            );
          },
        ),
      );
      if (!noInternet && !widget.vm.loading) {
        body = RefreshIndicator(
          onRefresh: widget.refresh,
          child: body,
        );
      }
      body = Stack(
        children: [
          body,
          AnimatedLinearProgressIndicator(show: widget.vm.loading),
        ],
      );
    }
    return ResponsiveScaffold<Pages>(
      key: scaffoldKey,
      homeBody: body,
      onRouteChanged: (route) {
        if (route == Pages.homework) {
          widget.refresh();
        }
      },
      homeFloatingActionButton: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          ValueListenableBuilder(
            valueListenable: _showScrollUp,
            builder: (context, bool value, child) {
              if (value) {
                return child!;
              } else {
                return const SizedBox();
              }
            },
            child: FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              heroTag: null,
              onPressed: () {
                controller.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.decelerate,
                );
              },
              mini: true,
              child: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
          if (_targets.isNotEmpty || _focused.isNotEmpty)
            FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              heroTag: null,
              onPressed: () {
                _markVisibleAsSeen(visibleDays);
              },
              mini: true,
              child: const Icon(Icons.close),
            ),
          if (_targets.isNotEmpty && _afterFirstFrame)
            FloatingActionButton.extended(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              icon: const Icon(Icons.keyboard_double_arrow_down_rounded),
              label: Text(l10n.text('dashboard.newEntries')),
              onPressed: () async {
                await controller.scrollToIndex(
                  _targets.first,
                  preferPosition: AutoScrollPosition.middle,
                );
              },
            ),
        ],
      ),
      homeAppBar: ResponsiveAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dashboard_customize_outlined),
            const SizedBox(width: 8),
            Flexible(
              child: Text(l10n.text('dashboard.title'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: <Widget>[
          const DashboardCustomizeButton(),
          if (widget.vm.noInternet)
            Tooltip(
              message: l10n.text('dashboard.noConnectionReload'),
              child: IconButton(
                onPressed: widget.refreshNoInternet,
                icon: const Icon(Icons.wifi_off_rounded),
                style: IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          if (widget.vm.showNotifications) NotificationIconContainer(),
        ],
      ),
      drawerBuilder: (widgetSelected, goHome, currentSelected, tabletMode) {
        // _widgetSelected is not passed down because routing is done by
        // accessing the ResponsiveScaffoldState via the GlobalKey and calling
        // selectContentWidget on it.
        return SidebarContainer(
          currentSelected: currentSelected,
          goHome: goHome,
          tabletMode: tabletMode,
        );
      },
      homeId: Pages.homework,
      navKey: nestedNavKey,
    );
  }
}

Future<String?> showEnterReminderDialog(
  BuildContext context, {
  String initialMessage = "",
  bool tutorial = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final showAssessmentHint =
      !(prefs.getBool(_localReminderAssessmentHintKey) ?? false);
  if (showAssessmentHint && !tutorial) {
    await prefs.setBool(_localReminderAssessmentHintKey, true);
  }
  if (!context.mounted) {
    return null;
  }
  return showDialog(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      final controller = TextEditingController(text: initialMessage);
      String message = initialMessage;
      return StatefulBuilder(
        builder: (context, setState) => InfoDialog(
          title: Text(l10n.text('dashboard.reminder')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAssessmentHint)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.text('dashboard.assessmentShortcutHintTitle'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.text(
                              'dashboard.assessmentShortcutHintBody',
                              args: {
                                'test': '/test',
                                'classwork': '/cw',
                                'exam': '/exam',
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: null,
                    onChanged: (msg) {
                      setState(() => message = msg);
                    },
                    decoration: InputDecoration(
                      hintText: l10n.text('dashboard.reminderHint'),
                    ),
                  ),
                  if (localReminderAssessmentSuggestions(message)
                      .isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.text('dashboard.assessmentShortcutSuggestions'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final suggestion
                            in localReminderAssessmentSuggestions(message))
                          ActionChip(
                            label: Text(
                              '/${suggestion.command} - ${_localizedAssessmentSuggestionLabel(l10n, suggestion.type)}',
                            ),
                            onPressed: () {
                              final replaced =
                                  applyLocalReminderAssessmentSuggestion(
                                controller.text,
                                suggestion,
                              );
                              controller.value = controller.value.copyWith(
                                text: replaced,
                                selection: TextSelection.collapsed(
                                  offset: replaced.length,
                                ),
                              );
                              setState(() => message = replaced);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(l10n.text('common.cancel')),
            ),
            ElevatedButton(
              onPressed: message.isNullOrEmpty
                  ? null
                  : () {
                      Navigator.pop(context, message);
                    },
              child: Text(l10n.text('button.save')),
            ),
          ],
        ),
      );
    },
  );
}

String _localizedAssessmentSuggestionLabel(
  AppLocalizations l10n,
  LocalReminderAssessmentType type,
) {
  switch (type) {
    case LocalReminderAssessmentType.test:
      return l10n.text('dashboard.test');
    case LocalReminderAssessmentType.classwork:
      return l10n.text('dashboard.schoolwork');
    case LocalReminderAssessmentType.exam:
      return l10n.text('dashboard.exam');
  }
}

class DashboardHeader extends StatelessWidget {
  final VoidCallback onSwitchFuture;
  final List<String> favoriteSubjects;
  final String? selectedFavoriteSubject;
  final ValueChanged<String?> onFavoriteSubjectChanged;
  final bool showEmptyDays;
  final ValueChanged<bool> onShowEmptyDaysChanged;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final bool future;
  final SchoolTimeline schoolTimeline;
  final OpenCalendarAtCallback openCalendarAt;
  final Future<void> Function(GradeDeadline deadline) editGradeDeadline;
  const DashboardHeader({
    super.key,
    required this.future,
    required this.onSwitchFuture,
    required this.favoriteSubjects,
    required this.selectedFavoriteSubject,
    required this.onFavoriteSubjectChanged,
    required this.showEmptyDays,
    required this.onShowEmptyDaysChanged,
    required this.subjectThemes,
    required this.schoolTimeline,
    required this.openCalendarAt,
    required this.editGradeDeadline,
  });

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, bool>(
        connect: (state) =>
            resolveDashboardItems(state.settingsState.dashboardItems)
                .isNotEmpty,
        builder: (context, hasCards, actions) =>
            _buildHeader(context, hasCards),
      );

  Widget _buildHeader(BuildContext context, bool hasCards) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final favoriteFilter = FavoriteSubjectFilter(
      subjects: favoriteSubjects,
      selectedSubject: selectedFavoriteSubject,
      onSelected: onFavoriteSubjectChanged,
      subjectThemes: subjectThemes,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              key: const ValueKey('dashboard-header-box'),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outline.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.45 : 0.2,
                  ),
                ),
                boxShadow: [
                  if (theme.brightness == Brightness.light)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: DashboardOverview(
                  timeline: schoolTimeline,
                  onOpenCalendarAt: openCalendarAt,
                  onEditGradeDeadline: editGradeDeadline,
                  footer: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(builder: (context, constraints) {
                        final filter = TutorialTarget(
                          id: 'dashboard-filter',
                          action: true,
                          child: HomeworkFilterContainer(
                            showEmptyDays: showEmptyDays,
                            onShowEmptyDaysChanged: onShowEmptyDaysChanged,
                          ),
                        );
                        final past = TutorialTarget(
                          id: 'dashboard-past',
                          action: true,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                    scale: animation, child: child),
                              );
                            },
                            child: FilledButton.tonalIcon(
                              key: ValueKey(future),
                              onPressed: onSwitchFuture,
                              icon: Icon(
                                future
                                    ? Icons.history_toggle_off
                                    : Icons.upcoming_rounded,
                              ),
                              label: Text(future
                                  ? l10n.text('dashboard.past')
                                  : l10n.text('dashboard.future')),
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                        return SizedBox(
                          key: const ValueKey('dashboard-header-controls'),
                          width: constraints.maxWidth,
                          child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                filter,
                                past,
                              ]),
                        );
                      }),
                      if (hasCards && favoriteSubjects.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        favoriteFilter,
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!hasCards && favoriteSubjects.isNotEmpty) ...[
              const SizedBox(height: 8),
              favoriteFilter,
            ],
          ]),
    );
  }
}

class DayWidget extends StatelessWidget {
  final DaysViewModel vm;

  final AddReminderCallback addReminderCallback;
  final EditReminderCallback editReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AttachmentCallback onOpenAttachment;
  final bool colorBorders, colorTestsInRed;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final BuiltList<String> allSubjects;

  final Day day;

  final AutoScrollController controller;
  final int index;

  final bool showLastFetched;

  const DayWidget({
    super.key,
    required this.day,
    required this.vm,
    required this.controller,
    required this.index,
    required this.addReminderCallback,
    required this.editReminderCallback,
    required this.removeReminderCallback,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.onOpenAttachment,
    required this.colorBorders,
    required this.subjectThemes,
    required this.allSubjects,
    required this.colorTestsInRed,
    required this.showLastFetched,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    var i = index;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.dashboardDayLabel(day.date),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (showLastFetched)
                      Text(
                        l10n.text(
                          'dashboard.syncLast',
                          args: {'time': l10n.formatTimeAgo(day.lastRequested)},
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (day.deletedHomework.isNotEmpty)
                AutoScrollTag(
                  controller: controller,
                  index: index,
                  key: ValueKey(index),
                  highlightColor: Colors.grey.withValues(alpha: 0.5),
                  child: IconButton(
                    icon: badge.Badge(
                      badgeContent: Icon(
                        Icons.delete,
                        size: 15,
                        color: day.deletedHomework.any((h) => h.isChanged)
                            ? Colors.white
                            : null,
                      ),
                      badgeStyle: badge.BadgeStyle(
                        badgeColor: day.deletedHomework.any((h) => h.isChanged)
                            ? Colors.red
                            : Theme.of(context).scaffoldBackgroundColor,
                        padding: EdgeInsets.zero,
                        elevation: 0,
                      ),
                      badgeAnimation: badge.BadgeAnimation.scale(
                        toAnimate: day.deletedHomework.any((h) => h.isChanged),
                      ),
                      position: badge.BadgePosition.topStart(),
                      child: const Icon(Icons.info_outline),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) {
                          return InfoDialog(
                            title: Text(l10n.text('dashboard.deletedEntries')),
                            content: SingleChildScrollView(
                              child: Column(
                                children: day.deletedHomework
                                    .map(
                                      (i) => ItemWidget(
                                        item: i,
                                        allSubjects: allSubjects,
                                        isDeletedView: true,
                                        colorBorder: colorBorders,
                                        subjectThemes: subjectThemes,
                                        colorTestsInRed: colorTestsInRed,
                                        askWhenDelete: vm.askWhenDelete,
                                        noInternet: vm.noInternet,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const Spacer(),
              if (vm.showAddReminder)
                TutorialTarget(
                  id: 'dashboard-reminder',
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: vm.noInternet
                        ? null
                        : () async {
                            final message = await showEnterReminderDialog(
                              context,
                              initialMessage: tutorialService.active &&
                                      tutorialService.step.key ==
                                          'assessmentShortcuts'
                                  ? '/cw '
                                  : '',
                            );
                            if (message != null) {
                              tutorialService.reminderSubmitted(day, message);
                              addReminderCallback(day, message);
                            }
                          },
                  ),
                ),
            ],
          ),
        ),
        for (final hw in day.homework)
          ItemWidget(
            item: hw,
            tutorialCreatedReminder: tutorialService.isCreatedReminder(day, hw),
            toggleDone: () => toggleDoneCallback(hw, !hw.checked),
            editReminder: () async {
              final message = await showEnterReminderDialog(
                context,
                initialMessage: hw.subtitle.isNotEmpty ? hw.subtitle : hw.title,
              );
              if (message != null) {
                editReminderCallback(hw, day, message);
              }
            },
            removeThis: () => removeReminderCallback(hw, day),
            setDoNotAskWhenDelete: setDoNotAskWhenDeleteCallback,
            askWhenDelete: vm.askWhenDelete,
            noInternet: vm.noInternet,
            controller: controller,
            index: ++i,
            onOpenAttachment: onOpenAttachment,
            subjectThemes: subjectThemes,
            allSubjects: allSubjects,
            colorBorder: colorBorders,
            colorTestsInRed: colorTestsInRed,
          ),
      ],
    );
  }
}

class ItemWidget extends StatelessWidget {
  final Homework item;
  final bool tutorialCreatedReminder;
  final BuiltList<String> allSubjects;
  final Future<void> Function()? editReminder;
  final VoidCallback? removeThis;
  final VoidCallback? toggleDone;
  final VoidCallback? setDoNotAskWhenDelete;
  final bool askWhenDelete,
      isHistory,
      isDeletedView,
      noInternet,
      isCurrent,
      colorBorder,
      colorTestsInRed;
  final AttachmentCallback? onOpenAttachment;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  final AutoScrollController? controller;
  final int? index;

  const ItemWidget({
    super.key,
    required this.item,
    this.tutorialCreatedReminder = false,
    required this.allSubjects,
    this.editReminder,
    this.removeThis,
    this.toggleDone,
    required this.askWhenDelete,
    this.setDoNotAskWhenDelete,
    this.isHistory = false,
    this.controller,
    this.index,
    this.isDeletedView = false,
    required this.noInternet,
    this.isCurrent = true,
    this.onOpenAttachment,
    required this.colorBorder,
    required this.subjectThemes,
    required this.colorTestsInRed,
  });

  Future<Tuple2<bool, bool>> _showConfirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    var ask = true;
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return InfoDialog(
          content: StatefulBuilder(
            builder: (context, setState) => SwitchListTile.adaptive(
              title: Text(l10n.text('dashboard.neverAsk')),
              onChanged: (bool value) {
                setState(() => ask = !value);
              },
              value: !ask,
            ),
          ),
          title: Text(l10n.text('dashboard.reminder.deleteQuestion')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.text('common.cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.text('button.delete')),
            )
          ],
        );
      },
    );
    return Tuple2(delete ?? false, ask);
  }

  void _showHistory(BuildContext context) {
    final l10n = context.l10n;
    // if we are in the deleted view, show the history for the previous item
    final historyItem = isDeletedView ? item.previousVersion : item;
    showDialog<void>(
      context: context,
      builder: (context) {
        return InfoDialog(
          title: Text(historyItem!.title),
          content: SingleChildScrollView(
            child: Column(
              children: [
                Text(formatChanged(historyItem)),
                if (historyItem.previousVersion != null)
                  ExpansionTile(
                    title: Text(l10n.text('dashboard.versions')),
                    children: <Widget>[
                      ItemWidget(
                        item: historyItem,
                        allSubjects: allSubjects,
                        isHistory: true,
                        colorBorder: colorBorder,
                        subjectThemes: subjectThemes,
                        colorTestsInRed: colorTestsInRed,
                        askWhenDelete: askWhenDelete,
                        noInternet: noInternet,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getBorderColor(BuildContext context) {
    if (item.checked) {
      return Colors.green;
    }
    if (displayedHomeworkWarning(item, allSubjects) && colorTestsInRed) {
      return Colors.red;
    }
    final displayLabel = displayedHomeworkLabel(item, allSubjects);
    if (colorBorder &&
        displayLabel != null &&
        subjectThemes.containsKey(displayLabel)) {
      return Color(subjectThemes[displayLabel]!.color);
    }
    return Theme.of(context).dividerColor.withValues(alpha: 0.3);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCompleted = item.checked && !isHistory && !isDeletedView;
    final displayLabel = displayedHomeworkLabel(item, allSubjects);
    final displayTitle = displayedHomeworkTitle(item, allSubjects);
    final displaySubtitle = displayedHomeworkSubtitle(item, allSubjects);
    final isSelfCreatedAssessment = parseLocalReminderAssessment(
          item.subtitle.isNotEmpty ? item.subtitle : item.title,
          allSubjects,
        ) !=
        null;
    final canEditReminder = !isHistory &&
        !isDeletedView &&
        item.type == HomeworkType.homework &&
        item.deleteable &&
        editReminder != null;
    Future<void> handleDelete(Future<void> Function() delete) async {
      if (askWhenDelete) {
        final confirmationResult = await _showConfirmDelete(context);
        final shouldDelete = confirmationResult.item1;
        final ask = confirmationResult.item2;
        if (shouldDelete == true) {
          if (!ask) {
            setDoNotAskWhenDelete!();
          }
          await delete();
          removeThis!();
          if (tutorialCreatedReminder) tutorialService.reminderDeleted(item.id);
        }
      } else {
        await delete();
        removeThis!();
        if (tutorialCreatedReminder) tutorialService.reminderDeleted(item.id);
      }
    }

    Widget child = Deleteable(
      // this is a new entry or a reminder the user has just entered
      showEntryAnimation:
          realNow.difference(item.firstSeen) < const Duration(seconds: 1),
      builder: (context, delete) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: _getBorderColor(context),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        top: 8,
                        bottom: 6,
                      ),
                      child: Column(
                        children: <Widget>[
                          if (displayLabel != null)
                            Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                Center(
                                  child: Text(
                                    l10n.translateSubjectName(displayLabel),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if ((!isHistory &&
                                        (item.isNew || item.isChanged)) ||
                                    (isHistory && isCurrent))
                                  Positioned(
                                    right: 0,
                                    child: badge.Badge(
                                      badgeStyle: badge.BadgeStyle(
                                        shape: badge.BadgeShape.square,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      badgeContent: Text(
                                        isHistory && isCurrent
                                            ? l10n.text('dashboard.current')
                                            : item.isNew
                                                ? l10n.text('dashboard.new')
                                                : item.deleted
                                                    ? l10n.text(
                                                        'dashboard.deleted')
                                                    : l10n.text(
                                                        'dashboard.changed'),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              l10n.translateDashboardServerText(displayTitle),
                              style: TextStyle(
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: displaySubtitle.isNullOrEmpty
                                ? null
                                : SelectableText(
                                    l10n.translateDashboardServerText(
                                      displaySubtitle,
                                    ),
                                    style: TextStyle(
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                            leading: !isHistory &&
                                    !isDeletedView &&
                                    item.deleteable
                                ? TutorialTarget(
                                    id: tutorialCreatedReminder
                                        ? 'dashboard-created-reminder'
                                        : 'dashboard-item-delete-${item.id}',
                                    child: IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: noInternet
                                          ? null
                                          : () => handleDelete(delete),
                                      padding: EdgeInsets.zero,
                                    ))
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      if (canEditReminder)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: noInternet
                              ? null
                              : () async {
                                  await editReminder!();
                                },
                        ),
                      if (!isHistory &&
                          displayLabel != null &&
                          !isSelfCreatedAssessment)
                        IconButton(
                          icon: (isDeletedView
                                      ? item.previousVersion!.previousVersion
                                      : item.previousVersion) !=
                                  null
                              ? badge.Badge(
                                  badgeContent:
                                      const Icon(Icons.edit, size: 15),
                                  badgeStyle: badge.BadgeStyle(
                                    padding: EdgeInsets.zero,
                                    badgeColor: isDeletedView
                                        ? Theme.of(context)
                                                .dialogTheme
                                                .backgroundColor ??
                                            Theme.of(context).canvasColor
                                        : Theme.of(context)
                                            .scaffoldBackgroundColor,
                                    elevation: 0,
                                  ),
                                  badgeAnimation:
                                      const badge.BadgeAnimation.scale(
                                          toAnimate: false),
                                  child: const Icon(
                                    Icons.info_outline,
                                  ),
                                )
                              : const Icon(
                                  Icons.info_outline,
                                ),
                          onPressed: () {
                            _showHistory(context);
                          },
                        ),
                      if (item.type == HomeworkType.grade)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(
                            item.gradeFormatted!,
                            style: const TextStyle(
                                color: Colors.green, fontSize: 30),
                          ),
                        )
                      else if (!isHistory && !isDeletedView && item.checkable)
                        Checkbox(
                          visualDensity: VisualDensity.standard,
                          activeColor: Colors.green,
                          value: item.checked,
                          onChanged: noInternet
                              ? null
                              : (done) {
                                  toggleDone!();
                                },
                        ),
                    ],
                  ),
                ],
              ),
              if (isHistory || isDeletedView) ...[
                const Divider(height: 0),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    formatChanged(item),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              if (item.gradeGroupSubmissions?.isNotEmpty == true) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(context.l10n.text('ui.attachment'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                for (final attachment in item.gradeGroupSubmissions!)
                  AttachmentWidget(
                    ggs: attachment,
                    noInternet: noInternet,
                    openCallback: onOpenAttachment!,
                  )
              ]
            ],
          ),
        ),
      ),
    );
    if (!isHistory && !isDeletedView) {
      child = AutoScrollTag(
        index: index!,
        key: ValueKey(index),
        controller: controller!,
        highlightColor: Colors.grey.withValues(alpha: 0.5),
        child: child,
      );
    }
    return Column(
      key: ValueKey(item.id),
      children: <Widget>[
        child,
        if (isHistory && item.previousVersion != null)
          ItemWidget(
            isHistory: true,
            isCurrent: false,
            item: item.previousVersion!,
            allSubjects: allSubjects,
            colorBorder: colorBorder,
            subjectThemes: subjectThemes,
            colorTestsInRed: colorTestsInRed,
            askWhenDelete: askWhenDelete,
            noInternet: noInternet,
          ),
      ],
    );
  }
}

String formatChanged(Homework hw) {
  String date;
  if (hw.lastNotSeen == null) {
    date =
        "Vor ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  } else if (toDate(hw.firstSeen) == toDate(hw.lastNotSeen!)) {
    date = "Am ${DateFormat("EEEE, dd.MM,", "de").format(hw.firstSeen)}"
        " zwischen ${DateFormat("HH:mm", "de").format(hw.lastNotSeen!)} und ${DateFormat("HH:mm", "de").format(hw.firstSeen)}";
  } else {
    date =
        "Zwischen ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.lastNotSeen!)} "
        "und ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  }
  if (hw.deleted) {
    return "$date gelöscht.";
  } else if (hw.previousVersion == null) {
    return "$date eingetragen.";
  } else if (hw.previousVersion!.deleted) {
    return "$date wiederhergestellt.";
  } else {
    return "$date geändert.";
  }
}

UtcDateTime toDate(UtcDateTime dateTime) {
  return UtcDateTime(dateTime.year, dateTime.month, dateTime.day);
}

class AttachmentWidget extends StatelessWidget {
  final GradeGroupSubmission ggs;
  final AttachmentCallback openCallback;
  final bool noInternet;

  const AttachmentWidget(
      {super.key,
      required this.ggs,
      required this.noInternet,
      required this.openCallback});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const Divider(
            indent: 16,
            height: 0,
          ),
          ListTile(title: Text(ggs.originalName)),
          AnimatedLinearProgressIndicator(show: ggs.downloading),
          TextButton(
            onPressed: !ggs.fileAvailable && noInternet
                ? null
                : () {
                    openCallback(ggs);
                  },
            child: Text(context.l10n.text('ui.open')),
          )
        ],
      ),
    );
  }
}
