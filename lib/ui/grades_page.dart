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

import 'package:dr/analytics_service.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/app_popup_button.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

bool _isFailingAverage(String gradeText) {
  final parsed = double.tryParse(gradeText.replaceAll(',', '.'));
  return parsed != null && parsed < 6;
}

bool _isPassingAverage(String gradeText) {
  final parsed = double.tryParse(gradeText.replaceAll(',', '.'));
  return parsed != null && parsed >= 6;
}

Widget _buildAverageValue(
  BuildContext context,
  String value,
  TextStyle? style,
  bool colorGrades,
) {
  if (!colorGrades) {
    return Text(value, style: style);
  }
  final failing = _isFailingAverage(value);
  final passing = _isPassingAverage(value);
  final foreground = failing
      ? Theme.of(context).colorScheme.onErrorContainer
      : Colors.green.shade900;
  final text = Text(
    value,
    style: (failing || passing)
        ? style?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ) ??
            TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
            )
        : style,
  );
  if (!failing && !passing) {
    return text;
  }
  return DecoratedBox(
    decoration: ShapeDecoration(
      color: failing
          ? Theme.of(context).colorScheme.errorContainer
          : Colors.green.shade100,
      shape: const StadiumBorder(),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: text,
    ),
  );
}

class GradesPage extends StatefulWidget {
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
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  String? _lastLoggedAverage;

  void _showCertificateAverageInfo(BuildContext context) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.text('grades.certificateAverage')),
        content: Text(l10n.text('grades.certificateAverageInfo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.text('common.close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;

    // Logge den Durchschnitt nur, wenn er sich geändert hat und gültig ist
    if (vm.showAllSubjectsAverage &&
        vm.allSubjectsAverage != '/' &&
        vm.allSubjectsAverage != _lastLoggedAverage) {
      _lastLoggedAverage = vm.allSubjectsAverage;
      final parsed =
          double.tryParse(vm.allSubjectsAverage.replaceAll(',', '.'));
      if (parsed != null) {
        AnalyticsService.logCustomEvent(
          'user_average_grade',
          {'average': parsed},
        );
      }
    }

    final l10n = context.l10n;
    final averageStyle = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Text(l10n.text('sidebar.grades')),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SemesterSwitcher(
              selectedSemester: vm.showSemester,
              onChanged: widget.changeSemester,
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
                            _AverageRow(
                              label: l10n.text('grades.average'),
                              icon: Icons.settings,
                              onIconPressed: widget.showGradesSettings,
                              value: _buildAverageValue(
                                context,
                                vm.allSubjectsAverage,
                                averageStyle,
                                vm.colorGrades,
                              ),
                            ),
                            _AverageRow(
                              label: l10n.text('grades.certificateAverage'),
                              icon: Icons.info_outline,
                              onIconPressed: () =>
                                  _showCertificateAverageInfo(context),
                              value: _buildAverageValue(
                                context,
                                vm.certificateAverage,
                                averageStyle,
                                vm.colorGrades,
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

class _AverageRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onIconPressed;
  final Widget value;

  const _AverageRow({
    required this.label,
    required this.icon,
    required this.onIconPressed,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = ListTileTheme.of(context).titleTextStyle ??
        Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 2),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            SizedBox(
              width: 48,
              child: IconButton(
                icon: Icon(icon),
                onPressed: onIconPressed,
              ),
            ),
            SizedBox(
              width: 112,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: value,
              ),
            ),
          ],
        ),
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
    return AppPopupButton<Semester>(
      selectedValue: selectedSemester,
      entries: Semester.values
          .map(
            (semester) => AppPopupButtonEntry<Semester>(
              value: semester,
              label: AppLocalizations.of(context).semesterLabel(semester),
            ),
          )
          .toList(),
      onSelected: onChanged,
      labelBuilder: (semester) =>
          AppLocalizations.of(context).semesterLabel(semester),
    );
  }
}
