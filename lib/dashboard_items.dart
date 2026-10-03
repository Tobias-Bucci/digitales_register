/// Stable persistence IDs. New items remain available in the editor without
/// changing a user's saved selection. Unknown IDs and duplicates are ignored.
enum DashboardItem {
  holidays('holidays', 'schoolCountdown.holidays.title'),
  gradingDeadline('gradingDeadline', 'schoolCountdown.grades.title'),
  absences('absences', 'absences.title');

  const DashboardItem(this.id, this.titleKey);
  final String id;
  final String titleKey;
}

const defaultDashboardItems = ['holidays', 'gradingDeadline'];

/// Stable span values in a two-column layout. Missing/unknown values preserve
/// the previous automatic layout, including its adaptive desktop columns.
enum DashboardItemWidth {
  automatic(0, 'dashboard.customize.widthAutomatic'),
  half(1, 'dashboard.customize.widthHalf'),
  full(2, 'dashboard.customize.widthFull');

  const DashboardItemWidth(this.span, this.titleKey);
  final int span;
  final String titleKey;

  static DashboardItemWidth fromSpan(int? span) => switch (span) {
        1 => half,
        2 => full,
        _ => automatic,
      };
}

/// One save action applies selection, order and sizing atomically to the
/// existing SettingsState. Hidden cards retain their width for re-adding.
class DashboardConfiguration {
  DashboardConfiguration(
      {required Iterable<String> items, Map<String, int> spans = const {}})
      : items = List.unmodifiable(
            resolveDashboardItems(items).map((item) => item.id)),
        spans = Map.unmodifiable({
          for (final item in DashboardItem.values)
            if (DashboardItemWidth.fromSpan(spans[item.id]) !=
                DashboardItemWidth.automatic)
              item.id: DashboardItemWidth.fromSpan(spans[item.id]).span,
        });

  final List<String> items;
  final Map<String, int> spans;
}

List<DashboardItem> resolveDashboardItems(Iterable<String> ids) {
  final known = {for (final item in DashboardItem.values) item.id: item};
  final seen = <String>{};
  final result = <DashboardItem>[];
  for (final id in ids) {
    final item = known[id];
    if (item != null && seen.add(id)) {
      result.add(item);
    }
  }
  return result;
}
