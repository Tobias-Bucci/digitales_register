import 'package:dr/dashboard_items.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

class DashboardCustomizeDialog extends StatefulWidget {
  const DashboardCustomizeDialog(
      {super.key,
      required this.items,
      this.spans = const {},
      required this.onSave});
  final Iterable<String> items;
  final Map<String, int> spans;
  final Future<void> Function(DashboardConfiguration) onSave;

  @override
  State<DashboardCustomizeDialog> createState() =>
      _DashboardCustomizeDialogState();
}

class _DashboardCustomizeDialogState extends State<DashboardCustomizeDialog> {
  late List<DashboardItem> _items;
  late Map<String, int> _spans;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _items = resolveDashboardItems(widget.items);
    _spans = Map.of(widget.spans);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(DashboardConfiguration(
          items: _items.map((item) => item.id), spans: _spans));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.t('dashboard.customize.title')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.t('dashboard.customize.hint')),
              const SizedBox(height: 8),
              Text(context.t('dashboard.customize.widthHint')),
              const SizedBox(height: 12),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _items.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (_saving) return;
                  setState(() {
                    _items.insert(newIndex, _items.removeAt(oldIndex));
                  });
                },
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Column(
                    key: ValueKey(item.id),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.t(item.titleKey)),
                        leading: ReorderableDragStartListener(
                          enabled: !_saving,
                          index: index,
                          child: Tooltip(
                            message: context.t('dashboard.customize.reorder'),
                            child: const SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(Icons.drag_handle_rounded)),
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: context.t('dashboard.customize.remove'),
                          onPressed: _saving
                              ? null
                              : () => setState(() => _items.removeAt(index)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final width in DashboardItemWidth.values)
                            ChoiceChip(
                              key: ValueKey(
                                  'dashboard-width-${item.id}-${width.span}'),
                              label: Text(context.t(width.titleKey)),
                              selected: DashboardItemWidth.fromSpan(
                                      _spans[item.id]) ==
                                  width,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() {
                                        if (width ==
                                            DashboardItemWidth.automatic) {
                                          _spans.remove(item.id);
                                        } else {
                                          _spans[item.id] = width.span;
                                        }
                                      }),
                            ),
                        ]),
                      ),
                    ],
                  );
                },
              ),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(context.t('dashboard.customize.empty')),
                ),
              for (final item in DashboardItem.values
                  .where((item) => !_items.contains(item)))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.t(item.titleKey)),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap:
                      _saving ? null : () => setState(() => _items.add(item)),
                ),
              if (_failed)
                Text(context.t('error.save'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _items = resolveDashboardItems(defaultDashboardItems);
                          _spans.clear();
                        }),
                icon: const Icon(Icons.restore_rounded),
                label: Text(context.t('dashboard.customize.reset')),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(context.t('common.cancel'))),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(context.t('button.save'))),
        ],
      );
}
