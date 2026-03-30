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
import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class GradesPage extends StatelessWidget {
  final GradesPageViewModel vm;
  final ValueChanged<Semester> changeSemester;
  final VoidCallback showGradesSettings;

  const GradesPage({
    super.key,
    required this.vm,
    required this.changeSemester,
    required this.showGradesSettings,
  });

  @override
  Widget build(BuildContext context) {
    final averageStyle = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: const Text("Noten"),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SemesterSwitcher(
              selectedSemester: vm.showSemester,
              onChanged: changeSemester,
            ),
          ),
        ],
      ),
      body: !vm.hasData && vm.noInternet
          ? const NoInternet()
          : vm.loading && !vm.hasData
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : Stack(
                  children: [
                    AnimatedLinearProgressIndicator(show: vm.loading),
                    RawLastFetchedOverlay(
                      message: vm.lastFetchedMessage,
                      child: ListView(
                        children: <Widget>[
                          if (vm.showGradesDiagram)
                            const SizedBox(
                              height: 150,
                              width: 250,
                              child: GradesChartContainer(isFullscreen: false),
                            ),
                          if (vm.showAllSubjectsAverage) ...[
                            ListTile(
                              title: Row(
                                children: [
                                  const Text("Notendurchschnitt"),
                                  IconButton(
                                    icon: const Icon(Icons.settings),
                                    onPressed: showGradesSettings,
                                  ),
                                ],
                              ),
                              trailing: Text(
                                vm.allSubjectsAverage,
                                style: averageStyle,
                              ),
                            ),
                            const Divider(
                              height: 0,
                            ),
                          ],
                          SortedGradesContainer(),
                          const SizedBox(height: 50),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SemesterSwitcher extends StatelessWidget {
  final Semester selectedSemester;
  final ValueChanged<Semester> onChanged;

  const _SemesterSwitcher({
    required this.selectedSemester,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final buttonColor = isDark
        ? const Color(0xFF1C1C1E)
        : Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.10),
            colorScheme.surface,
          );
    final menuColor = isDark ? const Color(0xFF141414) : colorScheme.surface;
    final borderColor = isDark
        ? const Color(0xFF323236)
        : colorScheme.primary.withValues(alpha: 0.18);
    final selectedIconColor =
        isDark ? const Color(0xFFB8B8BD) : colorScheme.primary;
    return Builder(
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final button = context.findRenderObject();
            final overlay =
                Overlay.maybeOf(context)?.context.findRenderObject();
            if (button is! RenderBox || overlay is! RenderBox) {
              return;
            }
            final position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(Offset.zero, ancestor: overlay),
                button.localToGlobal(
                  button.size.bottomRight(Offset.zero),
                  ancestor: overlay,
                ),
              ),
              Offset.zero & overlay.size,
            );
            final semester = await showMenu<Semester>(
              context: context,
              position: position,
              elevation: 10,
              color: menuColor,
              surfaceTintColor:
                  isDark ? Colors.transparent : colorScheme.surfaceTint,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              items: Semester.values
                  .map(
                    (semester) => PopupMenuItem<Semester>(
                      value: semester,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              semester.name,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          if (semester == selectedSemester)
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: selectedIconColor,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
            if (semester != null && semester != selectedSemester) {
              onChanged(semester);
            }
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: borderColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Text(selectedSemester.name),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
