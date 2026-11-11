// Copyright (C) 2021 Michael Debertol
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

import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_card_container.dart';
import 'package:dr/container/calendar_detail_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/ui/calendar_week.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:responsive_scaffold/size_transition.dart' as rsc;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _pageViewAnimationDuration = Duration(milliseconds: 500);
const _sidebarAnimationDuration = Duration(milliseconds: 300);

class RightSidebar extends StatefulWidget {
  final Widget child;
  final bool show;
  const RightSidebar({
    super.key,
    required this.child,
    required this.show,
  });

  @override
  State<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends State<RightSidebar>
    with SingleTickerProviderStateMixin {
  late final _animationController = AnimationController(
    vsync: this,
    duration: _sidebarAnimationDuration,
    value: widget.show ? 1 : 0,
  );
  @override
  void didUpdateWidget(RightSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.show != widget.show) {
      _animationController.animateTo(
        widget.show ? 1.0 : 0.0,
        duration: _sidebarAnimationDuration,
        curve: Curves.ease,
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rsc.SizeTransition(
      axis: Axis.horizontal,
      sizeFactor: _animationController,
      axisAlignment: -1,
      child: SizedBox(
        width: 350,
        child: widget.child,
      ),
    );
  }
}

int _pageViewIndex(UtcDateTime date) {
  return (date.difference(UtcDateTime(1970)).inHours / 24).round();
}

UtcDateTime _dateForPageViewIndex(int idx) {
  final date = UtcDateTime(1970).add(Duration(days: idx));
  // Prevent daylight saving times to interfere.
  // Should have used utc from the beginning...
  return UtcDateTime(date.year, date.month, date.day);
}

class CalendarDetailPage extends StatefulWidget {
  final UtcDateTime? selectedDay;
  final int? selectedHour;
  final bool isSidebar, show;
  const CalendarDetailPage({
    super.key,
    required this.selectedDay,
    required this.selectedHour,
    required this.isSidebar,
    required this.show,
  });

  @override
  _CalendarDetailPageState createState() => _CalendarDetailPageState();
}

class _CalendarDetailPageState extends State<CalendarDetailPage> {
  late PageController _controller;
  UtcDateTime? selectedDate;
  int programmaticPageAnimations = 0;

  void _pageBack() {
    _controller.previousPage(
      duration: _pageViewAnimationDuration,
      curve: Curves.ease,
    );
  }

  void _pageForward() {
    _controller.nextPage(
      duration: _pageViewAnimationDuration,
      curve: Curves.ease,
    );
  }

  void _handlePageChanged(int index) {
    if (programmaticPageAnimations != 0) {
      return;
    }
    final date = _dateForPageViewIndex(index);
    actions.calendarActions.select(
      CalendarSelection((b) => b..date = date),
    );
    setState(() {
      selectedDate = date;
    });
  }

  @override
  void didUpdateWidget(CalendarDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.show && oldWidget.show) {
      // clear the selection
      actions.calendarActions.select(null);
    }
    if (widget.selectedDay == null) {
      return;
    }
    selectedDate = widget.selectedDay;
    if (!widget.show) {
      return;
    }
    final pageViewIndex = _pageViewIndex(widget.selectedDay!);
    if (!_controller.hasClients) {
      _controller = PageController(
        initialPage: pageViewIndex,
      );
    } else if (pageViewIndex != _controller.page?.round()) {
      if (oldWidget.selectedDay != null) {
        programmaticPageAnimations++;
        _controller
            .animateToPage(
          pageViewIndex,
          duration: _pageViewAnimationDuration,
          curve: Curves.ease,
        )
            .then((_) {
          programmaticPageAnimations--;
        });
      } else {
        // We were previously closed, so we don't want to show a page animation.
        programmaticPageAnimations++;
        _controller.jumpToPage(pageViewIndex);
        programmaticPageAnimations--;
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _controller = PageController(
      initialPage:
          widget.selectedDay != null ? _pageViewIndex(widget.selectedDay!) : 0,
    );

    selectedDate = widget.selectedDay;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Turns the days, at once when motion is reduced.
  void _page(BuildContext context, int delta) {
    if (MediaQuery.disableAnimationsOf(context)) {
      final page = _controller.page?.round();
      if (page != null) _controller.jumpToPage(page + delta);
    } else if (delta < 0) {
      _pageBack();
    } else {
      _pageForward();
    }
  }

  /// The day in the new design: a page of its own with the glass header on
  /// phones, a panel beside the week on wide windows.
  Widget _buildNew(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final title = selectedDate != null
        ? DateFormat.MMMEd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(selectedDate!)
        : l10n.text('calendar.detailTitle');
    final paging = [
      HeaderDiscButton(
        key: const Key('calendar-detail-previous'),
        tooltip: l10n.text('calendar.previousDay'),
        icon: Icons.chevron_left_rounded,
        onPressed: () => _page(context, -1),
      ),
      HeaderDiscButton(
        key: const Key('calendar-detail-next'),
        tooltip: l10n.text('calendar.nextDay'),
        icon: Icons.chevron_right_rounded,
        onPressed: () => _page(context, 1),
      ),
    ];
    final pages = PageView.builder(
      key: const Key('calendar-detail-pages'),
      itemBuilder: (BuildContext context, int index) {
        final date = _dateForPageViewIndex(index);
        return CalendarDetailItemContainer(
          date: date,
          isSidebar: widget.isSidebar,
        );
      },
      controller: _controller,
      onPageChanged: _handlePageChanged,
    );
    if (!widget.isSidebar) {
      return GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('calendar-detail-header'),
          title: title,
          floatingMaxWidth:
              glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
          actions: paging,
        ),
        body: pages,
      );
    }
    return RightSidebar(
      show: widget.selectedDay != null && widget.show,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: DesignTokens.gutter),
        child: Column(
          key: const Key('calendar-detail-panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            GlassCard(
              padding: const EdgeInsets.all(2),
              child: Row(
                children: [
                  HeaderDiscButton(
                    key: const Key('calendar-detail-close'),
                    tooltip: l10n.text('common.close'),
                    icon: Icons.close_rounded,
                    onPressed: () => actions.calendarActions.select(null),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  ...paging,
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: pages),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _buildNew(context);
    }
    final l10n = context.l10n;
    return maybeWrap(
      Scaffold(
        appBar: AppBar(
          leading: widget.isSidebar
              ? IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  onPressed: () {
                    actions.calendarActions.select(null);
                  },
                )
              : null,
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              selectedDate != null
                  ? DateFormat.MMMEd(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(selectedDate!)
                  : l10n.text('calendar.detailTitle'),
              key: ValueKey(selectedDate),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _pageBack,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: _pageForward,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        body: PageView.builder(
          itemBuilder: (BuildContext context, int index) {
            final date = _dateForPageViewIndex(index);
            return CalendarDetailItemContainer(
              date: date,
              isSidebar: widget.isSidebar,
            );
          },
          controller: _controller,
          onPageChanged: _handlePageChanged,
        ),
      ),
      (scaffold) => RightSidebar(
        show: widget.selectedDay != null && widget.show,
        child: scaffold,
      ),
      wrap: widget.isSidebar,
    );
  }
}

class CalendarDetailWrapper extends StatelessWidget {
  final UtcDateTime date;
  final CalendarDay? day;
  final CalendarHour? targetHour;
  final bool noInternet;
  final bool loading;
  final bool isSidebar;
  const CalendarDetailWrapper({
    super.key,
    required this.day,
    required this.targetHour,
    required this.noInternet,
    required this.date,
    required this.loading,
    required this.isSidebar,
  });

  Widget _buildNew(BuildContext context) {
    final l10n = context.l10n;
    final day = this.day;
    final Widget child;
    if (day == null && noInternet) {
      child = GlassStateCard(
        key: const Key('calendar-detail-offline'),
        icon: Icons.wifi_off_rounded,
        title: l10n.text('offline.title'),
        body: l10n.text('offline.body'),
      );
    } else if (day == null && loading) {
      return const Center(child: CircularProgressIndicator());
    } else if (day == null || day.hours.isEmpty) {
      child = GlassStateCard(
        key: const Key('calendar-detail-no-school'),
        icon: date.weekday >= DateTime.saturday
            ? Icons.weekend_rounded
            : Icons.celebration_rounded,
        title: l10n.text('calendar.noSchool'),
        body: DateFormat.yMMMMEEEEd(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(date),
      );
    } else {
      final UtcDateTime? lastFetched = day.lastFetched;
      child = CalendarDetail(
        day: day,
        targetHour: targetHour,
        noInternet: noInternet,
        isSidebar: isSidebar,
        offlineHint: noInternet && !isSidebar
            ? GlassOfflineHint(
                key: const Key('calendar-detail-last-fetched'),
                message: lastFetched == null
                    ? l10n.text('offline.title')
                    : l10n.text(
                        'grades.offlineMode',
                        args: {'time': l10n.formatTimeAgo(lastFetched)},
                      ),
                onRetry: () => actions.calendarActions.load(toMonday(day.date)),
              )
            : null,
      );
    }
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _buildNew(context);
    }
    Widget child;
    if (day == null && noInternet) {
      child = const NoInternet();
    } else if (day == null && loading) {
      return const Center(child: CircularProgressIndicator());
    } else if (day?.hours.isEmpty ?? true) {
      child = _NoSchool(date: date);
    } else {
      child = CalendarDetail(
        day: day!,
        targetHour: targetHour,
        noInternet: noInternet,
      );
    }
    if (day != null && !isSidebar) {
      child = LastFetchedOverlay(
        noInternet: noInternet,
        lastFetched: day!.lastFetched,
        child: child,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: child,
    );
  }
}

class CalendarDetail extends StatefulWidget {
  final CalendarDay day;
  final CalendarHour? targetHour;
  final bool noInternet;

  /// New design only: whether the day is the panel beside the week.
  final bool isSidebar;

  /// New design only: shown above the lessons.
  final Widget? offlineHint;
  const CalendarDetail({
    super.key,
    required this.day,
    required this.targetHour,
    required this.noInternet,
    this.isSidebar = false,
    this.offlineHint,
  });

  @override
  State<CalendarDetail> createState() => _CalendarDetailState();
}

class _CalendarDetailState extends State<CalendarDetail> {
  final ItemScrollController itemScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    final targetHour = widget.targetHour;
    if (targetHour != null) {
      // Run this after the next frame
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          itemScrollController.jumpTo(
            index: widget.day.hours.indexOf(targetHour) + _leadingItems,
            alignment: 0.10,
          );
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant CalendarDetail oldWidget) {
    final targetHour = widget.targetHour;
    if (targetHour != null &&
        targetHour != oldWidget.targetHour &&
        ResponsiveNavigationScope.isActive(context) &&
        MediaQuery.disableAnimationsOf(context)) {
      itemScrollController.jumpTo(
        index: widget.day.hours.indexOf(targetHour) + _leadingItems,
        alignment: 0.10,
      );
    } else if (targetHour != null && targetHour != oldWidget.targetHour) {
      itemScrollController.scrollTo(
        index: widget.day.hours.indexOf(targetHour) + _leadingItems,
        alignment: 0.10,
        duration: const Duration(milliseconds: 500),
        curve: Curves.ease,
      );
    }

    super.didUpdateWidget(oldWidget);
  }

  /// What comes before the lessons in the list.
  int get _leadingItems => widget.offlineHint == null ? 0 : 1;

  Widget _buildNew(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final offlineHint = widget.offlineHint;
    final list = ScrollablePositionedList.builder(
      key: const Key('calendar-detail-list'),
      itemScrollController: itemScrollController,
      padding: EdgeInsets.fromLTRB(
        widget.isSidebar ? 0 : DesignTokens.gutter,
        widget.isSidebar ? 0 : padding.top + 8,
        widget.isSidebar ? 0 : DesignTokens.gutter,
        padding.bottom + DesignTokens.gutter,
      ),
      itemCount: widget.day.hours.length + _leadingItems,
      itemBuilder: (context, index) {
        if (offlineHint != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: offlineHint,
          );
        }
        final hourIndex = index - _leadingItems;
        return Padding(
          padding: EdgeInsets.only(top: hourIndex == 0 ? 0 : 8),
          child: RepaintBoundary(
            child: CalendarCardContainer(
              hourIndex: hourIndex,
              day: widget.day.date,
            ),
          ),
        );
      },
    );
    if (widget.isSidebar) return list;
    return ReadableContent(
      maxWidth: DesignTokens.contentMaxWidth,
      child: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _buildNew(context);
    }
    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemCount: widget.day.hours.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 8.0,
            vertical: 4,
          ),
          child: CalendarCardContainer(
            hourIndex: index,
            day: widget.day.date,
          ),
        );
      },
    );
  }
}

class _NoSchool extends StatelessWidget {
  final UtcDateTime date;
  const _NoSchool({
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        findHolidayIconForSeason(
          date,
          Theme.of(context).iconTheme.color!,
          150,
        ),
        Text(
          context.l10n.text('calendar.noSchool'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    );
  }
}
