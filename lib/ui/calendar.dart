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

import 'package:dr/analytics_service.dart';
import 'package:dr/calendar_load_log.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/calendar_detail_container.dart';
import 'package:dr/container/calendar_view_switcher.dart';
import 'package:dr/container/calendar_week_container.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

const tabletLayoutBreakPoint = 825;

typedef DayCallback = void Function(UtcDateTime day);

class Calendar extends StatefulWidget {
  final CalendarViewModel vm;

  final Future<void> Function(UtcDateTime day) dayCallback;
  final DayCallback currentMondayCallback;
  final VoidCallback showEditSubjectNicks;
  final VoidCallback showEditSubstituteSettings;
  final VoidCallback closeEditNicksBar;
  final VoidCallback clearSelection;

  const Calendar({
    super.key,
    required this.vm,
    required this.dayCallback,
    required this.currentMondayCallback,
    required this.showEditSubjectNicks,
    required this.showEditSubstituteSettings,
    required this.closeEditNicksBar,
    required this.clearSelection,
  });

  @override
  _CalendarState createState() => _CalendarState();
}

class _CalendarState extends State<Calendar> with TickerProviderStateMixin {
  late PageController _controller;
  late AnimationController _chevronOpacityController;
  late Animation<double> _chevronOpacityAnimation;
  late AnimationController _dateRangeOpacityController;
  late Animation<double> _dateRangeOpacityAnimation;
  final DateFormat _dateFormat = DateFormat("dd.MM.yy");
  final Curve _animatePageCurve = Curves.ease;
  final Duration _animatePageDuration = const Duration(milliseconds: 200);
  late bool tabletMode;
  String? _favoriteSubject;
  final Set<UtcDateTime> _loadingWeeks = {};
  final Set<UtcDateTime> _finishedWeeks = {};

  static final Animatable<double> _chevronOpacityTween =
      Tween<double>(begin: 1.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeInOut));
  static final Animatable<double> _dateRangeOpacityTween =
      Tween<double>(begin: 1.0, end: .25)
          .chain(CurveTween(curve: Curves.easeInOut));

  @override
  void initState() {
    _controller = PageController(
      initialPage: pageOf(widget.vm.currentMonday),
    )..addListener(_pageViewControllerListener);

    animatingPages = [pageOf(widget.vm.currentMonday)];

    _chevronOpacityController = AnimationController(
      duration: _animatePageDuration,
      vsync: this,
    );
    _chevronOpacityAnimation =
        _chevronOpacityController.drive(_chevronOpacityTween);

    _dateRangeOpacityController = AnimationController(
      duration: _animatePageDuration,
      vsync: this,
    );
    _dateRangeOpacityAnimation =
        _dateRangeOpacityController.drive(_dateRangeOpacityTween);

    unawaited(_loadWeek(widget.vm.currentMonday));
    AnalyticsService.logCustomEvent('calendar_viewed');

    super.initState();
  }

  late List<int> animatingPages;

  Future<void> _loadWeek(UtcDateTime monday) async {
    if (!_loadingWeeks.add(monday)) return;
    setState(() {});
    try {
      await widget.dayCallback(monday);
    } catch (_) {
      // The middleware reports the failure; keep the visible week retryable.
      logCalendarLoad(CalendarLoadEvent.weekError);
    } finally {
      if (mounted) {
        setState(() {
          _loadingWeeks.remove(monday);
          _finishedWeeks.add(monday);
        });
      }
    }
  }

  void _pageViewControllerListener() {
    final floor = _controller.page!.floor(), ceil = _controller.page!.ceil();
    if (!animatingPages.contains(floor)) {
      unawaited(_loadWeek(mondayOf(floor)));
    }
    if (ceil != floor && !animatingPages.contains(ceil)) {
      unawaited(_loadWeek(mondayOf(ceil)));
    }
    animatingPages = [floor, ceil];
  }

  void _handlePageChanged(int newPage) {
    final newMonday = mondayOf(newPage);
    if (newMonday != widget.vm.currentMonday) {
      widget.currentMondayCallback(newMonday);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _chevronOpacityController.dispose();
    _dateRangeOpacityController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Calendar oldWidget) {
    _ensureSelectionVisible(
      _resolvedFavoriteSubject(_availableFavoriteSubjects()),
    );
    final page = pageOf(widget.vm.currentMonday);
    if (page != _controller.page?.round()) {
      _controller.animateToPage(
        page,
        curve: _animatePageCurve,
        duration: _animatePageDuration,
      );
    }
    if (!tabletMode &&
        oldWidget.vm.selection == null &&
        widget.vm.selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context)
            .push<void>(
              MaterialPageRoute(
                builder: (context) => const CalendarDetailContainer(
                  isSidebar: false,
                  show: true,
                ),
                fullscreenDialog: true,
              ),
            )
            .then((_) => widget.clearSelection());
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  List<String> _availableFavoriteSubjects() {
    return filterAvailableFavoriteSubjects(
      widget.vm.favoriteSubjects,
      widget.vm.currentDays
          .expand((day) => day.hours.map((hour) => hour.subject)),
    );
  }

  String? _resolvedFavoriteSubject(List<String> availableFavoriteSubjects) {
    final favoriteSubject = _favoriteSubject;
    if (favoriteSubject == null) {
      return null;
    }
    return findSubjectIgnoreCase(availableFavoriteSubjects, favoriteSubject);
  }

  bool _selectionIsVisible(String? favoriteSubject) {
    if (favoriteSubject == null || widget.vm.selection == null) {
      return true;
    }
    final selection = widget.vm.selection!;
    CalendarDay? selectedDay;
    for (final day in widget.vm.currentDays) {
      if (day.date == selection.date) {
        selectedDay = day;
        break;
      }
    }
    if (selectedDay == null) {
      return true;
    }
    if (selection.hour == null) {
      return selectedDay.hours.any(
        (hour) => matchesFavoriteSubject(hour.subject, favoriteSubject),
      );
    }
    return selectedDay.hours.any(
      (hour) =>
          hour.fromHour == selection.hour &&
          matchesFavoriteSubject(hour.subject, favoriteSubject),
    );
  }

  void _ensureSelectionVisible(String? favoriteSubject) {
    if (!_selectionIsVisible(favoriteSubject)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.vm.selection != null) {
          widget.clearSelection();
        }
      });
    }
  }

  void _showCurrentWeek() {
    _controller.animateToPage(pageOf(toMonday(now)),
        curve: _animatePageCurve, duration: _animatePageDuration);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      tabletMode = constraints.maxWidth >= tabletLayoutBreakPoint;
      final newDesign = ResponsiveNavigationScope.isActive(context);
      final availableFavoriteSubjects = _availableFavoriteSubjects();
      final selectedFavoriteSubject =
          _resolvedFavoriteSubject(availableFavoriteSubjects);
      final pageView = PageView.builder(
        itemBuilder: (BuildContext context, int index) {
          return CalendarWeekContainer(
            monday: mondayOf(index),
            favoriteSubject: selectedFavoriteSubject,
            loading: _loadingWeeks.contains(mondayOf(index)) ||
                !_finishedWeeks.contains(mondayOf(index)),
            onRetry: () => unawaited(_loadWeek(mondayOf(index))),
          );
        },
        controller: _controller,
        onPageChanged: _handlePageChanged,
      );
      if (newDesign) {
        return _buildNew(
          context,
          width: constraints.maxWidth,
          pageView: pageView,
          availableFavoriteSubjects: availableFavoriteSubjects,
          selectedFavoriteSubject: selectedFavoriteSubject,
        );
      }
      return Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                Scaffold(
                  appBar: ResponsiveAppBar(
                    title: newDesign
                        ? const CalendarViewSwitcher(exams: false)
                        : Text(context.t('calendar.title')),
                    actions: <Widget>[
                      if (toMonday(now) != widget.vm.currentMonday && newDesign)
                        // An icon leaves the title row to the view switcher.
                        IconButton(
                          key: const Key('calendar-current-week'),
                          tooltip: context.t('calendar.currentWeek'),
                          icon: const Icon(Icons.today_outlined),
                          onPressed: _showCurrentWeek,
                        )
                      else if (toMonday(now) != widget.vm.currentMonday)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onPressed: _showCurrentWeek,
                          child: Text(context.t('calendar.currentWeek')),
                        ),
                    ],
                  ),
                  bottomNavigationBar:
                      ResponsiveNavigationScope.spacerOf(context),
                  body: Column(
                    children: <Widget>[
                      if (!newDesign)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const Key('calendar-open-exam-calendar'),
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const ExamCalendarContainer(
                                  calendarView: true,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.school_outlined),
                            label: Text(context.t('exam.title')),
                          ),
                        ),
                      Material(
                        clipBehavior: Clip.antiAlias,
                        elevation: 4,
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 48,
                              child: FadeTransition(
                                opacity: _chevronOpacityAnimation,
                                child: TextButton(
                                  onPressed: () {
                                    _controller.previousPage(
                                      curve: _animatePageCurve,
                                      duration: _animatePageDuration,
                                    );
                                  },
                                  child: const Icon(Icons.chevron_left),
                                ),
                              ),
                            ),
                            Expanded(
                                child: FadeTransition(
                              opacity: _dateRangeOpacityAnimation,
                              child: TextButton(
                                style: ButtonStyle(
                                  textStyle: WidgetStateProperty.all(
                                      Theme.of(context).textTheme.titleLarge),
                                ),
                                onPressed: () async {
                                  final result = await showDatePicker(
                                    context: context,
                                    firstDate: UtcDateTime(2018),
                                    lastDate: UtcDateTime(2050),
                                    initialDate: widget.vm.currentMonday,
                                    selectableDayPredicate: (day) {
                                      return day.weekday != DateTime.sunday &&
                                          day.weekday != DateTime.saturday;
                                    },
                                  );
                                  if (result == null) return;
                                  final date = toMonday(result.makeUtc());
                                  if (date != widget.vm.currentMonday) {
                                    await _controller.animateToPage(
                                      pageOf(date),
                                      curve: _animatePageCurve,
                                      duration: _animatePageDuration,
                                    );
                                  }
                                },
                                child: widget.vm.first != null &&
                                        widget.vm.last != null
                                    ? Text(
                                        "${_dateFormat.format(widget.vm.first!)} - ${_dateFormat.format(widget.vm.last!)}",
                                        textAlign: TextAlign.center,
                                      )
                                    : Text(
                                        '${_dateFormat.format(widget.vm.currentMonday)} - ${_dateFormat.format(widget.vm.currentMonday.add(const Duration(days: 5)))}',
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            )),
                            SizedBox(
                              width: 48,
                              child: FadeTransition(
                                opacity: _chevronOpacityAnimation,
                                child: TextButton(
                                  onPressed: () {
                                    _controller.nextPage(
                                        curve: _animatePageCurve,
                                        duration: _animatePageDuration);
                                  },
                                  child: const Icon(Icons.chevron_right),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (availableFavoriteSubjects.isNotEmpty)
                        FavoriteSubjectFilter(
                          subjects: availableFavoriteSubjects,
                          selectedSubject: selectedFavoriteSubject,
                          onSelected: (favoriteSubject) {
                            setState(() {
                              _favoriteSubject = favoriteSubject;
                            });
                            _ensureSelectionVisible(favoriteSubject);
                          },
                          subjectThemes: widget.vm.subjectThemes,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        ),
                      const SizedBox(
                        height: 8,
                      ),
                      Expanded(
                        child: NotificationListener<ScrollStartNotification>(
                          onNotification: (n) {
                            _chevronOpacityController.forward();
                            _dateRangeOpacityController.forward();
                            return false;
                          },
                          child: NotificationListener<ScrollEndNotification>(
                            onNotification: (_) {
                              _chevronOpacityController.reverse();
                              _dateRangeOpacityController.reverse();
                              return false;
                            },
                            child: pageView,
                          ),
                        ),
                      ),
                      EditNickBar(
                        show: widget.vm.showEditNicksBar,
                        onShowEditNicks: widget.showEditSubjectNicks,
                        onClose: widget.closeEditNicksBar,
                      ),
                      CalendarSubstituteBar(
                        show: widget.vm.showSubstituteBar,
                        onOpenSettings: widget.showEditSubstituteSettings,
                        enabled: widget.vm.substituteDetectionEnabled,
                      ),
                    ],
                  ),
                ),
                if (tabletMode && widget.vm.selection != null)
                  Positioned(
                    right: 0,
                    top: -4,
                    bottom: -4,
                    child: ClipRect(
                      child: Container(
                        width: 5,
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                          boxShadow: [
                            BoxShadow(
                              offset: Offset(7, 0),
                              blurRadius: 4,
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          CalendarDetailContainer(
            isSidebar: true,
            show: tabletMode,
          ),
        ],
      );
    });
  }

  bool _reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Turns to [page] of the weeks, at once when motion is reduced.
  void _goToPage(BuildContext context, int page) {
    if (_reduceMotion(context)) {
      _controller.jumpToPage(page);
    } else {
      unawaited(
        _controller.animateToPage(
          page,
          curve: _animatePageCurve,
          duration: _animatePageDuration,
        ),
      );
    }
  }

  Future<void> _pickWeek(BuildContext context) async {
    final result = await showDatePicker(
      context: context,
      firstDate: UtcDateTime(2018),
      lastDate: UtcDateTime(2050),
      initialDate: widget.vm.currentMonday,
      selectableDayPredicate: (day) {
        return day.weekday != DateTime.sunday &&
            day.weekday != DateTime.saturday;
      },
    );
    if (result == null || !context.mounted) return;
    final date = toMonday(result.makeUtc());
    if (date != widget.vm.currentMonday) {
      _goToPage(context, pageOf(date));
    }
  }

  /// The calendar in the new design: the glass header with the switch to the
  /// exam calendar, the week navigation as glass controls, the week and, on
  /// wide windows, the day beside it.
  Widget _buildNew(
    BuildContext context, {
    required double width,
    required Widget pageView,
    required List<String> availableFavoriteSubjects,
    required String? selectedFavoriteSubject,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final reduceMotion = _reduceMotion(context);
    final floatingMaxWidth = glassHeaderFloatingWidth(width, twoColumns: true);
    final chevronOpacity =
        reduceMotion ? kAlwaysCompleteAnimation : _chevronOpacityAnimation;
    final rangeOpacity =
        reduceMotion ? kAlwaysCompleteAnimation : _dateRangeOpacityAnimation;
    final vm = widget.vm;
    final first = vm.first ?? vm.currentMonday;
    final last = vm.last ?? vm.currentMonday.add(const Duration(days: 5));
    final range = '${_dateFormat.format(first)} – ${_dateFormat.format(last)}';
    final discStyle = HeaderDiscButton.styleOf(scheme);
    final week = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              FadeTransition(
                opacity: chevronOpacity,
                child: IconButton(
                  key: const Key('calendar-previous-week'),
                  tooltip: l10n.text('exam.previousWeek'),
                  style: discStyle,
                  iconSize: HeaderDiscButton.iconSize,
                  onPressed: () => _goToPage(
                    context,
                    pageOf(vm.currentMonday) - 1,
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: FadeTransition(
                  opacity: rangeOpacity,
                  child: Center(
                    child: FilledButton.icon(
                      key: const Key('calendar-week-range'),
                      style: glassControlStyle(scheme),
                      onPressed: () => unawaited(_pickWeek(context)),
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          range,
                          maxLines: 1,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              FadeTransition(
                opacity: chevronOpacity,
                child: IconButton(
                  key: const Key('calendar-next-week'),
                  tooltip: l10n.text('exam.nextWeek'),
                  style: discStyle,
                  iconSize: HeaderDiscButton.iconSize,
                  onPressed: () => _goToPage(
                    context,
                    pageOf(vm.currentMonday) + 1,
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ],
          ),
        ),
        if (availableFavoriteSubjects.isNotEmpty)
          FavoriteSubjectFilter(
            subjects: availableFavoriteSubjects,
            selectedSubject: selectedFavoriteSubject,
            onSelected: (favoriteSubject) {
              setState(() {
                _favoriteSubject = favoriteSubject;
              });
              _ensureSelectionVisible(favoriteSubject);
            },
            subjectThemes: vm.subjectThemes,
            padding: const EdgeInsets.only(top: 8),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (n) {
              _chevronOpacityController.forward();
              _dateRangeOpacityController.forward();
              return false;
            },
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                _chevronOpacityController.reverse();
                _dateRangeOpacityController.reverse();
                return false;
              },
              child: pageView,
            ),
          ),
        ),
        EditNickBar(
          show: vm.showEditNicksBar,
          onShowEditNicks: widget.showEditSubjectNicks,
          onClose: widget.closeEditNicksBar,
        ),
        CalendarSubstituteBar(
          show: vm.showSubstituteBar,
          onOpenSettings: widget.showEditSubstituteSettings,
          enabled: vm.substituteDetectionEnabled,
        ),
      ],
    );
    return GlassPage(
      scrolls: false,
      loading: _loadingWeeks.contains(vm.currentMonday) && vm.first != null,
      header: GlassPageHeader(
        surfaceKey: const Key('calendar-app-header'),
        title: l10n.text('calendar.title'),
        titleWidget: const CalendarViewSwitcher(exams: false),
        floatingMaxWidth: floatingMaxWidth,
        actions: [
          if (toMonday(now) != vm.currentMonday)
            HeaderDiscButton(
              key: const Key('calendar-current-week'),
              tooltip: l10n.text('calendar.currentWeek'),
              icon: Icons.today_outlined,
              onPressed: () => _goToPage(context, pageOf(toMonday(now))),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: floatingMaxWidth ?? double.infinity,
          ),
          child: Padding(
            // Lines up with the floating header; on phones the days get the
            // room.
            padding: EdgeInsets.fromLTRB(
              floatingMaxWidth == null ? 6 : DesignTokens.gutter,
              0,
              floatingMaxWidth == null ? 6 : DesignTokens.gutter,
              DesignTokens.gutter,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: week),
                CalendarDetailContainer(
                  isSidebar: true,
                  show: tabletMode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int pageOf(UtcDateTime monday) =>
    monday.difference(UtcDateTime(2010, 1, 3, 0, 0, 0, 0, 1)).inDays ~/ 7;

UtcDateTime mondayOf(int page) =>
    UtcDateTime(2010, 1, 4).add(Duration(days: page * 7));

class EditNickBar extends StatelessWidget {
  final bool show;
  final VoidCallback onShowEditNicks, onClose;

  const EditNickBar(
      {super.key,
      required this.show,
      required this.onShowEditNicks,
      required this.onClose});
  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _GlassHelperBar(
        show: show,
        child: Row(
          children: [
            Expanded(
              child: GlassTile(
                icon: Icons.edit_note_rounded,
                title: context.t('calendar.editNicknames'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onShowEditNicks,
              ),
            ),
            const SizedBox(width: 4),
            HeaderDiscButton(
              key: const Key('calendar-close-nicks-bar'),
              tooltip: context.t('common.close'),
              icon: Icons.close_rounded,
              onPressed: onClose,
            ),
          ],
        ),
      );
    }
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      firstChild: Column(
        children: <Widget>[
          const SizedBox(
            height: 8,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  offset: Offset(0, -1.5),
                  spreadRadius: 1.5,
                  blurRadius: 2,
                ),
              ],
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Material(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextButton(
                        onPressed: onShowEditNicks,
                        child: Row(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(context.t('calendar.editNicknames')),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      secondChild: Container(
        height: 8,
      ),
      crossFadeState:
          show ? CrossFadeState.showFirst : CrossFadeState.showSecond,
    );
  }
}

class CalendarSubstituteBar extends StatelessWidget {
  final bool show;
  final bool enabled;
  final VoidCallback onOpenSettings;

  const CalendarSubstituteBar({
    super.key,
    required this.show,
    required this.onOpenSettings,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      // A tile cuts a long text off cleanly instead of overflowing the row.
      return _GlassHelperBar(
        show: show,
        child: GlassTile(
          key: const Key('calendar-substitute-bar'),
          icon: Icons.swap_horiz_rounded,
          title: context.t(
            enabled
                ? 'calendar.reportSubstituteError'
                : 'calendar.configureSubstitute',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onOpenSettings,
        ),
      );
    }
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      firstChild: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  offset: Offset(0, -1.5),
                  spreadRadius: 1.5,
                  blurRadius: 2,
                ),
              ],
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Material(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton(
                  onPressed: onOpenSettings,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          context.t(
                            enabled
                                ? 'calendar.reportSubstituteError'
                                : 'calendar.configureSubstitute',
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      secondChild: Container(height: 8),
      crossFadeState:
          show ? CrossFadeState.showFirst : CrossFadeState.showSecond,
    );
  }
}

/// A helper bar of the new design below the week: [child] slides in while
/// [show] is true, at once when motion is reduced.
class _GlassHelperBar extends StatelessWidget {
  const _GlassHelperBar({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      firstChild: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: child,
      ),
      secondChild: const SizedBox(width: double.infinity),
      crossFadeState:
          show ? CrossFadeState.showFirst : CrossFadeState.showSecond,
    );
  }
}
