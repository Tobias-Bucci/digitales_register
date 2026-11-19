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
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/app_navigation_container.dart';
import 'package:dr/container/dashboard_events_container.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/homework_filter_container.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/data.dart';
import 'package:dr/external_links.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reminders/local_reminder_assessments.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/committed_deleteable.dart';
import 'package:dr/ui/compact_day_list.dart';
import 'package:dr/ui/controlled_text_builder.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/glass_page.dart'
    show GlassPanel, glassHeaderFloatingWidth;
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/linkified_text.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/ui/settings_page_new.dart'
    show SettingsSheetActions, SettingsSheetKeyboardInset;
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/web_app/web_routing.dart';
import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';

part 'days/dashboard_header.dart';
part 'days/day_items.dart';
part 'days/reminder_entry.dart';

typedef AddReminderCallback = void Function(Day day, String reminder);
typedef EditReminderCallback = void Function(
  Homework hw,
  Day day,
  String reminder,
);
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
  final ValueChanged<String?>? onFavoriteSubjectChanged;
  final ValueChanged<bool>? onShowEmptyDaysChanged;

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
    this.onFavoriteSubjectChanged,
    this.onShowEmptyDaysChanged,
  });
  @override
  _DaysWidgetState createState() => _DaysWidgetState();
}

class _DaysWidgetState extends State<DaysWidget> {
  final controller = AutoScrollController(suggestedRowHeight: 100);
  late String? _favoriteSubject = widget.vm.favoriteSubject;
  late bool _showEmptyDays = widget.vm.showEmptyDays;
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
          title: Text(context.t('schoolCountdown.deadlineDialog.title')),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 1,
                    label:
                        Text(context.t('schoolCountdown.deadlineDialog.one'))),
                ButtonSegment(
                    value: 2,
                    label:
                        Text(context.t('schoolCountdown.deadlineDialog.two'))),
              ],
              selected: {count},
              onSelectionChanged: (value) =>
                  setDialogState(() => count = value.first),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < count; index++)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(context.t('schoolCountdown.deadlineDialog.date',
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
                  if (selected != null && context.mounted) {
                    setDialogState(() => dates[index] = selected);
                  }
                },
              ),
          ])),
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
    controller.addListener(update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      update();
      _afterFirstFrame = true;
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller.removeListener(update);
    controller.dispose();
    _showScrollUp.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DaysWidget oldWidget) {
    // A saved state mounted after the first build brings the stored filters.
    if (oldWidget.vm.favoriteSubject != widget.vm.favoriteSubject) {
      _favoriteSubject = widget.vm.favoriteSubject;
    }
    if (oldWidget.vm.showEmptyDays != widget.vm.showEmptyDays) {
      _showEmptyDays = widget.vm.showEmptyDays;
    }
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
    final modern = !widget.vm.legacyDesign;
    if (n == 0) {
      if (_dashboardColumns(modern) != null) return const SizedBox(height: 4);
      final header = _dashboardHeader(
        availableFavoriteSubjects,
        activeFavoriteSubject,
        modern: modern,
      );
      return modern ? _modernTop(header) : header;
    }
    if (isLast) {
      // The list view already ends above the navigation bar.
      return SizedBox(
        height: modern ? 72 : 160,
      );
    }
    if (n.isEven) {
      return modern
          ? const SizedBox(height: 4)
          : const Divider(
              height: 16,
            );
    }
    final itemIndex = (n - 1) ~/ 2;
    if (modern) {
      return ReadableContent(
        maxWidth: DesignTokens.contentMaxWidth,
        child: CompactDayWidget(
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
        ),
      );
    }
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

  /// The two columns of a wide window, or null.
  DashboardColumns? _dashboardColumns(bool modern) => modern
      ? DashboardColumns.forWindow(MediaQuery.sizeOf(context).width)
      : null;

  Widget _dashboardHeader(
    List<String> availableFavoriteSubjects,
    String? activeFavoriteSubject, {
    required bool modern,
  }) {
    return DashboardHeader(
      future: widget.vm.future,
      onSwitchFuture: widget.onSwitchFuture,
      favoriteSubjects: availableFavoriteSubjects,
      selectedFavoriteSubject: activeFavoriteSubject,
      onFavoriteSubjectChanged: (favoriteSubject) {
        setState(() {
          _favoriteSubject = favoriteSubject;
          widget.onFavoriteSubjectChanged?.call(favoriteSubject);
          updateValues(_filteredDays(favoriteSubject));
          update();
        });
      },
      showEmptyDays: _showEmptyDays,
      onShowEmptyDaysChanged: (value) {
        setState(() {
          _showEmptyDays = value;
          widget.onShowEmptyDaysChanged?.call(value);
          updateValues(_filteredDays(activeFavoriteSubject));
          update();
        });
      },
      subjectThemes: widget.vm.subjectThemes,
      schoolTimeline: _schoolTimeline(),
      openCalendarAt: widget.openCalendarAt,
      editGradeDeadline: _editGradeDeadline,
      modern: modern,
    );
  }

  void _scrollToTop() {
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.decelerate,
    );
  }

  Future<void> _showNextNewEntry() => controller.scrollToIndex(
        _targets.first,
        preferPosition: AutoScrollPosition.middle,
      );

  PreferredSizeWidget _modernAppBar(List<Day> visibleDays) {
    final width = MediaQuery.sizeOf(context).width;
    return DashboardAppHeader(
      schoolName: widget.vm.schoolName,
      noInternet: widget.vm.noInternet,
      onRetry: widget.refreshNoInternet,
      showScrollUp: _showScrollUp,
      onScrollUp: visibleDays.isEmpty ? null : _scrollToTop,
      onShowNewEntries:
          _targets.isNotEmpty && _afterFirstFrame ? _showNextNewEntry : null,
      onDismissNewEntries: _targets.isNotEmpty || _focused.isNotEmpty
          ? () => _markVisibleAsSeen(visibleDays)
          : null,
      // The same as on every other page (#140).
      floatingMaxWidth: glassHeaderFloatingWidth(width),
    );
  }

  /// What the new design shows above the day list.
  Widget _modernTop(Widget header) => ReadableContent(
        maxWidth: DesignTokens.contentMaxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [header, const DashboardEventsContainer()],
        ),
      );

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
    final l10n = context.l10n;
    final availableFavoriteSubjects = _availableFavoriteSubjects();
    final activeFavoriteSubject =
        _resolvedFavoriteSubject(availableFavoriteSubjects);
    final visibleDays = _filteredDays(activeFavoriteSubject);
    final noInternet = widget.vm.noInternet;
    final noEntries = visibleDays.isEmpty;
    final modern = !widget.vm.legacyDesign;
    final columns = _dashboardColumns(modern);
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
      final emptyHeader = DashboardHeader(
        modern: modern,
        future: widget.vm.future,
        onSwitchFuture: widget.onSwitchFuture,
        favoriteSubjects: availableFavoriteSubjects,
        selectedFavoriteSubject: activeFavoriteSubject,
        onFavoriteSubjectChanged: (favoriteSubject) {
          setState(() {
            _favoriteSubject = favoriteSubject;
            widget.onFavoriteSubjectChanged?.call(favoriteSubject);
            widget.onFavoriteSubjectChanged?.call(favoriteSubject);
            updateValues(_filteredDays(favoriteSubject));
            update();
          });
        },
        showEmptyDays: _showEmptyDays,
        onShowEmptyDaysChanged: (value) {
          setState(() {
            _showEmptyDays = value;
            widget.onShowEmptyDaysChanged?.call(value);
            updateValues(_filteredDays(activeFavoriteSubject));
            update();
          });
        },
        subjectThemes: widget.vm.subjectThemes,
        schoolTimeline: schoolTimeline,
        openCalendarAt: widget.openCalendarAt,
        editGradeDeadline: _editGradeDeadline,
      );
      // Unlike a list view, a sliver list leaves the padding of the header and
      // the navigation bar to its slivers.
      body = Builder(
        builder: (context) {
          final padding = MediaQuery.paddingOf(context);
          if (columns != null) {
            return DashboardColumnsView(
              columns: columns,
              side: _modernTop(emptyHeader),
              main: Padding(
                padding: EdgeInsets.only(right: columns.margin),
                child: Center(child: fullScreenBody),
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              if (modern)
                SliverPadding(padding: EdgeInsets.only(top: padding.top)),
              SliverToBoxAdapter(
                  child: modern ? _modernTop(emptyHeader) : emptyHeader),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: fullScreenBody),
              ),
              if (modern)
                SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
            ],
          );
        },
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
        child: Builder(builder: (context) {
          return ListView.builder(
            padding: columns?.listPadding(MediaQuery.paddingOf(context)),
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
          );
        }),
      );
      final list = body;
      body = Builder(
        builder: (context) {
          // Below the header of the new design, this is its bottom edge.
          final top = modern ? MediaQuery.paddingOf(context).top : 0.0;
          return Stack(
            children: [
              if (!noInternet && !widget.vm.loading)
                RefreshIndicator(
                  edgeOffset: top,
                  onRefresh: widget.refresh,
                  child: list,
                )
              else
                list,
              Padding(
                padding: EdgeInsets.only(top: top),
                child: AnimatedLinearProgressIndicator(show: widget.vm.loading),
              ),
            ],
          );
        },
      );
      if (columns != null) {
        final days = body;
        body = Builder(
          builder: (context) => DashboardColumnsView(
            columns: columns,
            side: _modernTop(_dashboardHeader(
              availableFavoriteSubjects,
              activeFavoriteSubject,
              modern: modern,
            )),
            main: days,
          ),
        );
      }
    }
    final scaffold = ResponsiveScaffold<Pages>(
      key: scaffoldKey,
      navigation: modern ? appNavigation() : null,
      extendHomeBodyBehindAppBar: modern,
      homeBody: modern ? DashboardBackdrop(child: body) : body,
      onRouteChanged: (route) {
        WebUrlSync.instance.pageChanged(route);
        if (route == Pages.homework) {
          widget.refresh();
        }
      },
      // The new design has these controls in its header, clear of the list.
      homeFloatingActionButton: modern
          ? null
          : Column(
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
                    onPressed: _scrollToTop,
                    mini: true,
                    child: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
                if (_targets.isNotEmpty || _focused.isNotEmpty)
                  FloatingActionButton(
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onErrorContainer,
                    heroTag: null,
                    onPressed: () {
                      _markVisibleAsSeen(visibleDays);
                    },
                    mini: true,
                    child: const Icon(Icons.close),
                  ),
                if (_targets.isNotEmpty && _afterFirstFrame)
                  FloatingActionButton.extended(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    icon: const Icon(Icons.keyboard_double_arrow_down_rounded),
                    label: Text(l10n.text('dashboard.newEntries')),
                    onPressed: _showNextNewEntry,
                  ),
              ],
            ),
      homeAppBar: modern
          ? _modernAppBar(visibleDays)
          : ResponsiveAppBar(
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip:
                      MaterialLocalizations.of(context).openAppDrawerTooltip,
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
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
                const NotificationIconContainer(),
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
    final grouped = BackdropGroup(child: scaffold);
    return modern ? NewDesignTheme(child: grouped) : grouped;
  }
}
