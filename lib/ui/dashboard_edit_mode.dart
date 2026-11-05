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

import 'package:dr/dashboard_items.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_customize_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

typedef DashboardCardDecorator = Widget Function(
  BuildContext context,
  DashboardItem item,
  Widget card,
);

/// Wraps the dashboard cards so that they can be edited in place: a long press
/// starts the edit mode, as on an Android home screen. On desktop the same is
/// reachable by right-click and from the keyboard with the context menu key or
/// Shift+F10. Every change is saved at once through [onChanged].
class DashboardCardEditor extends StatefulWidget {
  const DashboardCardEditor({
    super.key,
    required this.items,
    required this.spans,
    required this.onChanged,
    required this.overviewBuilder,
    this.footer,
  });

  final List<DashboardItem> items;
  final Map<String, int> spans;
  final Future<void> Function(DashboardConfiguration) onChanged;

  /// Builds the cards, passing each of them through the decorator.
  final Widget Function(DashboardCardDecorator decorate) overviewBuilder;
  final Widget? footer;

  @override
  State<DashboardCardEditor> createState() => _DashboardCardEditorState();
}

enum _CardMenuAction { edit, moveEarlier, moveLater, remove, width }

class _DashboardCardEditorState extends State<DashboardCardEditor> {
  bool _editing = false;

  List<DashboardItem> get _hidden => DashboardItem.values
      .where((item) => !widget.items.contains(item))
      .toList();

  void _save(List<DashboardItem> items, Map<String, int> spans) {
    widget.onChanged(DashboardConfiguration(
      items: items.map((item) => item.id),
      spans: spans,
    ));
  }

  void _startEditing() => setState(() => _editing = true);

  void _stopEditing() => setState(() => _editing = false);

  void _move(DashboardItem item, int delta) {
    final items = [...widget.items];
    final index = items.indexOf(item);
    final target = index + delta;
    if (target < 0 || target >= items.length) return;
    items.insert(target, items.removeAt(index));
    _save(items, widget.spans);
  }

  /// Moves [dragged] to the position of [target].
  void _moveOnto(DashboardItem dragged, DashboardItem target) {
    final items = [...widget.items];
    final index = items.indexOf(target);
    items
      ..remove(dragged)
      ..insert(index, dragged);
    _save(items, widget.spans);
  }

  void _remove(DashboardItem item) {
    _save([...widget.items]..remove(item), widget.spans);
  }

  void _add(DashboardItem item) {
    _save([...widget.items, item], widget.spans);
  }

  void _setWidth(DashboardItem item, DashboardItemWidth width) {
    final spans = {...widget.spans};
    if (width == DashboardItemWidth.automatic) {
      spans.remove(item.id);
    } else {
      spans[item.id] = width.span;
    }
    _save(widget.items, spans);
  }

  void _cycleWidth(DashboardItem item) {
    const values = DashboardItemWidth.values;
    final current = DashboardItemWidth.fromSpan(widget.spans[item.id]);
    _setWidth(item, values[(current.index + 1) % values.length]);
  }

  Future<void> _showContextMenu(
    BuildContext context,
    DashboardItem item,
    Offset position,
  ) async {
    final index = widget.items.indexOf(item);
    final current = DashboardItemWidth.fromSpan(widget.spans[item.id]);
    final overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject()! as RenderBox;
    final selected = await showMenu<(_CardMenuAction, DashboardItemWidth?)>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: (_CardMenuAction.edit, null),
          child: _MenuLabel(
            icon: Icons.edit_outlined,
            text: context.t('dashboard.edit.start'),
          ),
        ),
        const PopupMenuDivider(),
        for (final width in DashboardItemWidth.values)
          PopupMenuItem(
            value: (_CardMenuAction.width, width),
            child: _MenuLabel(
              icon: width == current ? Icons.check_rounded : null,
              text: context.t('dashboard.edit.widthValue',
                  args: {'width': context.t(width.titleKey)}),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: (_CardMenuAction.moveEarlier, null),
          enabled: index > 0,
          child: _MenuLabel(
            icon: Icons.arrow_back_rounded,
            text: context.t('dashboard.edit.moveEarlier'),
          ),
        ),
        PopupMenuItem(
          value: (_CardMenuAction.moveLater, null),
          enabled: index < widget.items.length - 1,
          child: _MenuLabel(
            icon: Icons.arrow_forward_rounded,
            text: context.t('dashboard.edit.moveLater'),
          ),
        ),
        PopupMenuItem(
          value: (_CardMenuAction.remove, null),
          child: _MenuLabel(
            icon: Icons.remove_circle_outline,
            text: context.t('dashboard.customize.remove'),
          ),
        ),
      ],
    );
    if (selected == null || !mounted) return;
    switch (selected.$1) {
      case _CardMenuAction.edit:
        _startEditing();
      case _CardMenuAction.moveEarlier:
        _move(item, -1);
      case _CardMenuAction.moveLater:
        _move(item, 1);
      case _CardMenuAction.remove:
        _remove(item);
      case _CardMenuAction.width:
        _setWidth(item, selected.$2!);
    }
  }

  Future<void> _showAddSheet() async {
    final selected = await showModalBottomSheet<DashboardItem>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in _hidden)
              ListTile(
                key: ValueKey('dashboard-add-${item.id}'),
                leading: const Icon(Icons.add_circle_outline),
                title: Text(context.t(item.titleKey)),
                onTap: () => Navigator.of(context).pop(item),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _add(selected);
  }

  Future<void> _showAdvancedDialog() => showDialog<void>(
        context: context,
        builder: (context) => DashboardCustomizeDialog(
          items: widget.items.map((item) => item.id),
          spans: widget.spans,
          onSave: widget.onChanged,
        ),
      );

  Widget _decorate(BuildContext context, DashboardItem item, Widget card) {
    if (!_editing) {
      return _CardActivator(
        onEdit: _startEditing,
        onContextMenu: (context, position) =>
            _showContextMenu(context, item, position),
        child: card,
      );
    }
    final index = widget.items.indexOf(item);
    return _EditableCard(
      item: item,
      width: DashboardItemWidth.fromSpan(widget.spans[item.id]),
      onMoveEarlier: index > 0 ? () => _move(item, -1) : null,
      onMoveLater:
          index < widget.items.length - 1 ? () => _move(item, 1) : null,
      onCycleWidth: () => _cycleWidth(item),
      onRemove: () => _remove(item),
      onDropped: (dragged) => _moveOnto(dragged, item),
      child: card,
    );
  }

  Widget _toolbar(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('dashboard-edit-add'),
                  onPressed: _hidden.isEmpty ? null : _showAddSheet,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.t('dashboard.edit.add')),
                ),
                IconButton(
                  key: const Key('dashboard-edit-reset'),
                  tooltip: context.t('dashboard.customize.reset'),
                  onPressed: () => _save(
                    resolveDashboardItems(defaultDashboardItems),
                    const {},
                  ),
                  icon: const Icon(Icons.restore_rounded),
                ),
                IconButton(
                  key: const Key('dashboard-edit-advanced'),
                  tooltip: context.t('dashboard.customize.title'),
                  onPressed: _showAdvancedDialog,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            FilledButton(
              key: const Key('dashboard-edit-done'),
              onPressed: _stopEditing,
              child: Text(context.t('dashboard.edit.done')),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final showOverview = widget.items.isNotEmpty;
    final footer = widget.footer;
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showOverview) widget.overviewBuilder(_decorateBound),
        if (_editing) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.t('dashboard.edit.hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          _toolbar(context),
        ] else if (!showOverview)
          TextButton.icon(
            key: const Key('dashboard-edit-empty'),
            onPressed: _startEditing,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.t('dashboard.edit.add')),
          ),
        if (footer != null) ...[const SizedBox(height: 10), footer],
      ],
    );
    if (_editing) {
      content = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _stopEditing,
        },
        child: Focus(autofocus: true, child: content),
      );
    }
    return content;
  }

  Widget _decorateBound(
          BuildContext context, DashboardItem item, Widget card) =>
      _decorate(context, item, card);
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.text});

  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              width: 32, child: icon == null ? null : Icon(icon, size: 20)),
          Flexible(child: Text(text)),
        ],
      );
}

/// A card outside of the edit mode, listening for the ways to reach it.
class _CardActivator extends StatelessWidget {
  const _CardActivator({
    required this.onEdit,
    required this.onContextMenu,
    required this.child,
  });

  final VoidCallback onEdit;
  final void Function(BuildContext context, Offset position) onContextMenu;
  final Widget child;

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isMenuKey = key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed);
    if (!isMenuKey) return KeyEventResult.ignored;
    final box = context.findRenderObject()! as RenderBox;
    onContextMenu(context, box.localToGlobal(box.size.center(Offset.zero)));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final label = context.t('dashboard.edit.start');
    return Semantics(
      onLongPress: onEdit,
      onLongPressHint: label,
      customSemanticsActions: {CustomSemanticsAction(label: label): onEdit},
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => _onKey(context, event),
        // A long press belongs to the edit mode. The texts of a card stay
        // available by hovering, as manual tooltips ignore the long press.
        child: TooltipTheme(
          data: TooltipTheme.of(context)
              .copyWith(triggerMode: TooltipTriggerMode.manual),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onEdit();
            },
            onSecondaryTapUp: (details) =>
                onContextMenu(context, details.globalPosition),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A card in the edit mode: it can be dragged and carries its own controls, so
/// that everything also works without a drag.
class _EditableCard extends StatelessWidget {
  const _EditableCard({
    required this.item,
    required this.width,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onCycleWidth,
    required this.onRemove,
    required this.onDropped,
    required this.child,
  });

  final DashboardItem item;
  final DashboardItemWidth width;
  final VoidCallback? onMoveEarlier, onMoveLater;
  final VoidCallback onCycleWidth, onRemove;
  final ValueChanged<DashboardItem> onDropped;
  final Widget child;

  IconData get _widthIcon => switch (width) {
        DashboardItemWidth.automatic => Icons.fit_screen_outlined,
        DashboardItemWidth.half => Icons.width_normal_outlined,
        DashboardItemWidth.full => Icons.width_full_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = context.t(item.titleKey);
    final widthLabel = context.t('dashboard.edit.widthValue',
        args: {'width': context.t(width.titleKey)});
    Widget control({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) =>
        SizedBox.square(
          dimension: 32,
          child: IconButton(
            key: key,
            tooltip: '$tooltip: $title',
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurface,
            ),
          ),
        );
    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<DashboardItem>(
        onWillAcceptWithDetails: (details) => details.data != item,
        onAcceptWithDetails: (details) => onDropped(details.data),
        builder: (context, candidates, _) => Draggable<DashboardItem>(
          data: item,
          // The card itself ignores the pointer while it is being edited.
          hitTestBehavior: HitTestBehavior.opaque,
          feedback: SizedBox(
            width: constraints.maxWidth,
            child: Material(
              type: MaterialType.transparency,
              child: Opacity(opacity: 0.9, child: child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: child),
          child: Stack(
            children: [
              ExcludeFocus(
                child: IgnorePointer(
                  child: Opacity(opacity: 0.45, child: child),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: candidates.isNotEmpty
                            ? scheme.primary
                            : scheme.outline,
                        width: candidates.isNotEmpty ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: control(
                  key: ValueKey('dashboard-edit-remove-${item.id}'),
                  icon: Icons.close_rounded,
                  tooltip: context.t('dashboard.customize.remove'),
                  onPressed: onRemove,
                ),
              ),
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    control(
                      key: ValueKey('dashboard-edit-earlier-${item.id}'),
                      icon: Icons.arrow_back_rounded,
                      tooltip: context.t('dashboard.edit.moveEarlier'),
                      onPressed: onMoveEarlier,
                    ),
                    control(
                      key: ValueKey('dashboard-edit-width-${item.id}'),
                      icon: _widthIcon,
                      tooltip: widthLabel,
                      onPressed: onCycleWidth,
                    ),
                    control(
                      key: ValueKey('dashboard-edit-later-${item.id}'),
                      icon: Icons.arrow_forward_rounded,
                      tooltip: context.t('dashboard.edit.moveLater'),
                      onPressed: onMoveLater,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
