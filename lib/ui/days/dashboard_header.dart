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

part of '../days.dart';

// The header of the dashboard above the list of days.

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

  /// Shows the translucent box of the new design with editable cards.
  final bool modern;
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
    this.modern = false,
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
            GlassEdgeIf(
              enabled: modern,
              sheen: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                key: const ValueKey('dashboard-header-box'),
                decoration: BoxDecoration(
                  color: modern
                      ? scheme.surfaceContainerLowest
                          .withValues(alpha: DesignTokens.cardOpacity)
                      : scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outline.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.45 : 0.2,
                    ),
                  ),
                  boxShadow: [
                    if (theme.brightness == Brightness.light && !modern)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                  ],
                ),
                child: GlassEdgeIf(
                  enabled: modern,
                  rim: GlassRim.none,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: DashboardOverview(
                      editable: modern,
                      timeline: schoolTimeline,
                      onOpenCalendarAt: openCalendarAt,
                      onEditGradeDeadline: editGradeDeadline,
                      footer: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(builder: (context, constraints) {
                            final filter = HomeworkFilterContainer(
                              showEmptyDays: showEmptyDays,
                              onShowEmptyDaysChanged: onShowEmptyDaysChanged,
                            );
                            final past = AnimatedSwitcher(
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
                            );
                            final controls = SizedBox(
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
                            return modern
                                ? FilledButtonTheme(
                                    data: FilledButtonThemeData(
                                      style: glassControlStyle(scheme),
                                    ),
                                    child: controls,
                                  )
                                : controls;
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
