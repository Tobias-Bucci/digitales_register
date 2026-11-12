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

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/chart_legend_container.dart';
import 'package:dr/container/chart_legend_entry_container.dart';
import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// What the page needs besides the chart: whether there is anything to draw,
/// whether grades are on their way, and the subjects of the legend.
typedef _ChartPageViewModel = ({
  bool hasGrades,
  bool loading,
  BuiltList<String> subjects,
});

/// The chart of the grades in full screen, in the new design. It opens on top
/// of the grades page inside the shell. Legacy keeps `GradesChartPage`.
///
/// The chart takes what height there is. The legend stands beside it in wide
/// windows and on phones held sideways, and below it, folded, on phones held
/// upright.
class GradesChartPageNew extends StatelessWidget {
  const GradesChartPageNew({super.key});

  /// From here on the legend stands beside the chart.
  static const double _sideLegendWidth = 300;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final floatingWidth = glassHeaderFloatingWidth(width, twoColumns: true);
    return StoreConnection<AppState, AppActions, _ChartPageViewModel>(
      connect: (state) => (
        hasGrades: appSelectors
            .chartGraphs(state)
            .keys
            .any((subject) => subject.grades.isNotEmpty),
        loading: state.gradesState.loading,
        subjects: ChartLegendContainer.subjectsOf(state),
      ),
      builder: (context, vm, actions) => GlassPage(
        scrolls: false,
        loading: vm.loading,
        header: GlassPageHeader(
          surfaceKey: const Key('grades-chart-header'),
          title: context.t('ui.gradeChart'),
          floatingMaxWidth: floatingWidth,
        ),
        body: !vm.hasGrades
            ? GlassStateCard(
                key: const Key('grades-chart-empty'),
                icon: Icons.show_chart_rounded,
                title: context.t('grades.chart.empty'),
                body: '',
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.maxWidth >= tabletLayoutBreakpoint ||
                      constraints.maxWidth > constraints.maxHeight;
                  const chart = _ChartCard();
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: floatingWidth ?? double.infinity,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          DesignTokens.gutter,
                          8,
                          DesignTokens.gutter,
                          // Short windows keep the room for the chart.
                          constraints.maxHeight < 480 ? 8 : DesignTokens.gutter,
                        ),
                        child: side
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Expanded(child: chart),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: constraints.maxWidth < 760
                                        ? constraints.maxWidth * 0.4
                                        : _sideLegendWidth,
                                    child: _LegendCard(
                                      subjects: vm.subjects,
                                      collapsible: false,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Expanded(child: chart),
                                  const SizedBox(height: 8),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: constraints.maxHeight * 0.45,
                                    ),
                                    child: _LegendCard(
                                      subjects: vm.subjects,
                                      collapsible: true,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// The chart on its card. It keeps the painting and the selection of Legacy.
class _ChartCard extends StatelessWidget {
  const _ChartCard();

  @override
  Widget build(BuildContext context) => const GlassCard(
        key: Key('grades-chart-full'),
        padding: EdgeInsets.fromLTRB(4, 8, 8, 4),
        child: RepaintBoundary(
          child: GradesChartContainer(isFullscreen: true),
        ),
      );
}

/// The subjects of the chart, each with its colour and a slider for the
/// thickness of its line; 0 hides it.
class _LegendCard extends StatefulWidget {
  const _LegendCard({required this.subjects, required this.collapsible});

  final BuiltList<String> subjects;

  /// Folded at first, below the chart on upright phones, as in Legacy.
  final bool collapsible;

  @override
  State<_LegendCard> createState() => _LegendCardState();
}

class _LegendCardState extends State<_LegendCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final open = !widget.collapsible || _open;
    final list = ListView.builder(
      key: const Key('grades-chart-legend-list'),
      shrinkWrap: widget.collapsible,
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: widget.subjects.length,
      itemBuilder: (context, index) => ChartLegendEntryContainer(
        subjectName: widget.subjects[index],
      ),
    );
    return GlassCard(
      key: const Key('grades-chart-legend'),
      padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
      child: Column(
        mainAxisSize: widget.collapsible ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSectionHeading(
            title: l10n.text('ui.legend'),
            count: widget.subjects.length,
            trailing: widget.collapsible
                ? IconButton(
                    key: const Key('grades-chart-legend-toggle'),
                    tooltip: l10n.text('ui.legend'),
                    style: HeaderDiscButton.styleOf(scheme),
                    iconSize: HeaderDiscButton.iconSize,
                    isSelected: _open,
                    onPressed: () => setState(() => _open = !_open),
                    icon: const Icon(Icons.expand_more_rounded),
                    selectedIcon: const Icon(Icons.expand_less_rounded),
                  )
                : null,
          ),
          if (open)
            if (widget.collapsible)
              Flexible(child: list)
            else
              Expanded(child: list),
        ],
      ),
    );
  }
}
