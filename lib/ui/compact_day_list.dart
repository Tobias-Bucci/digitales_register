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
import 'package:collection/collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart'
    show AttachmentCallback, DaysViewModel;
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/committed_deleteable.dart';
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/ui/days.dart' hide AsyncCallback;
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/linkified_text.dart';
import 'package:dr/ui/notepad_mark.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// The height of one row. With its gap that is a pitch of 48, about 2.3 times
/// denser than the cards of the legacy list.
const compactRowHeight = 44.0;
const _rowGap = 4.0;

/// How many of the entries that can be ticked off are done.
({int done, int total}) dayProgress(Day day) {
  final checkable = day.homework.where((homework) => homework.checkable);
  return (
    done: checkable.where((homework) => homework.checked).length,
    total: checkable.length,
  );
}

/// Below this width the heading has no room for the words of the progress next
/// to the date and the add button.
const _shortProgressBelowWidth = 380.0;

/// One day of the compact list: heading with progress and a button to add an
/// entry, then the slim rows.
class CompactDayWidget extends StatelessWidget {
  const CompactDayWidget({
    super.key,
    required this.day,
    required this.vm,
    required this.controller,
    required this.index,
    required this.addReminderCallback,
    required this.editReminderCallback,
    required this.removeReminderCallback,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.onOpenAttachment,
    required this.colorBorders,
    required this.colorTestsInRed,
    required this.subjectThemes,
    required this.allSubjects,
    required this.showLastFetched,
  });

  final Day day;
  final DaysViewModel vm;
  final AutoScrollController controller;
  final int index;
  final AddReminderCallback addReminderCallback;
  final EditReminderCallback editReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AttachmentCallback onOpenAttachment;
  final bool colorBorders, colorTestsInRed, showLastFetched;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final BuiltList<String> allSubjects;

  void _showDeletedEntries(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => InfoDialog(
        title: Text(context.t('dashboard.deletedEntries')),
        content: SingleChildScrollView(
          child: Column(
            children: [
              for (final homework in day.deletedHomework)
                ItemWidget(
                  item: homework,
                  allSubjects: allSubjects,
                  isDeletedView: true,
                  onOpenAttachment: onOpenAttachment,
                  colorBorder: colorBorders,
                  subjectThemes: subjectThemes,
                  colorTestsInRed: colorTestsInRed,
                  askWhenDelete: vm.askWhenDelete,
                  noInternet: vm.noInternet,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final progress = dayProgress(day);
    final deletedChanged = day.deletedHomework.any((h) => h.isChanged);
    final progressText = l10n.text('dashboard.progress', args: {
      'done': '${progress.done}',
      'total': '${progress.total}',
    });
    final shortProgress =
        MediaQuery.sizeOf(context).width < _shortProgressBelowWidth;
    return Padding(
      // The add button has the width of the notepad column of the rows and
      // stands right above it, its touch target fills the height of the heading.
      padding: vm.showAddReminder
          ? const EdgeInsets.fromLTRB(16, 0, DesignTokens.gutter, 0)
          : const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.dashboardDayHeading(day.date),
                    key: ValueKey('day-heading-${day.date}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (showLastFetched)
                  Text(
                    l10n.text(
                      'dashboard.syncLast',
                      args: {'time': l10n.formatTimeAgo(day.lastRequested)},
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (day.deletedHomework.isNotEmpty)
            AutoScrollTag(
              controller: controller,
              index: index,
              key: ValueKey(index),
              highlightColor: Colors.grey.withValues(alpha: 0.5),
              child: IconButton(
                tooltip: l10n.text('dashboard.deletedEntries'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: deletedChanged ? theme.colorScheme.error : null,
                ),
                onPressed: () => _showDeletedEntries(context),
              ),
            ),
          if (progress.total > 0)
            Text(
              shortProgress
                  ? '${progress.done}/${progress.total}'
                  : progressText,
              key: ValueKey('day-progress-${day.date}'),
              semanticsLabel: progressText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (vm.showAddReminder)
            _AddEntryButton(
              key: ValueKey('day-add-entry-${day.date}'),
              onPressed: vm.noInternet
                  ? null
                  : () async {
                      final message = await showEnterReminderDialog(context);
                      if (message != null) {
                        addReminderCallback(day, message);
                      }
                    },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var i = index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context),
        for (final homework in day.homework)
          CompactEntryRow(
            key: ValueKey(homework.id),
            item: homework,
            day: day,
            controller: controller,
            index: ++i,
            allSubjects: allSubjects,
            colorBorder: colorBorders,
            colorTestsInRed: colorTestsInRed,
            subjectThemes: subjectThemes,
            noInternet: vm.noInternet,
            askWhenDelete: vm.askWhenDelete,
            onOpenAttachment: onOpenAttachment,
            toggleDone: () => toggleDoneCallback(homework, !homework.checked),
            removeThis: () => removeReminderCallback(homework, day),
            setDoNotAskWhenDelete: setDoNotAskWhenDeleteCallback,
            editReminder: () async {
              final message = await showEnterReminderDialog(
                context,
                initialMessage: homework.subtitle.isNotEmpty
                    ? homework.subtitle
                    : homework.title,
              );
              if (message != null) {
                editReminderCallback(homework, day, message);
              }
            },
          ),
      ],
    );
  }
}

/// The "+" of a day: a small disc in a full-sized touch target.
class _AddEntryButton extends StatelessWidget {
  const _AddEntryButton({super.key, required this.onPressed});

  static const double _discSize = 30;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: context.t('dashboard.addEntry'),
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 20),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_discSize),
        minimumSize: const Size.square(_discSize),
        padding: EdgeInsets.zero,
        // The compact density of desktops would shrink the target to 40.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
      ).merge(glassControlStyle(scheme, shape: const CircleBorder())),
    );
  }
}

/// How a row looks, by what it stands for.
enum CompactRowStyle { normal, test, done }

CompactRowStyle compactRowStyle(
  Homework item,
  Iterable<String> allSubjects, {
  required bool colorTestsInRed,
}) {
  if (item.checked) return CompactRowStyle.done;
  return displayedHomeworkWarning(item, allSubjects) && colorTestsInRed
      ? CompactRowStyle.test
      : CompactRowStyle.normal;
}

/// One entry in one line: subject letter, type, title and the notepad checkbox.
class CompactEntryRow extends StatelessWidget {
  const CompactEntryRow({
    super.key,
    required this.item,
    required this.day,
    required this.controller,
    required this.index,
    required this.allSubjects,
    required this.colorBorder,
    required this.colorTestsInRed,
    required this.subjectThemes,
    required this.noInternet,
    required this.askWhenDelete,
    required this.onOpenAttachment,
    required this.toggleDone,
    required this.removeThis,
    required this.setDoNotAskWhenDelete,
    required this.editReminder,
  });

  final Homework item;
  final Day day;
  final AutoScrollController controller;
  final int index;
  final BuiltList<String> allSubjects;
  final bool colorBorder, colorTestsInRed, noInternet, askWhenDelete;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final AttachmentCallback onOpenAttachment;
  final VoidCallback toggleDone, removeThis, setDoNotAskWhenDelete;
  final Future<void> Function() editReminder;

  Future<void> _delete(BuildContext context, Future<void> Function() delete) =>
      deleteReminderWithConfirmation(
        context,
        askWhenDelete: askWhenDelete,
        setDoNotAskWhenDelete: setDoNotAskWhenDelete,
        delete: delete,
      );

  void _openDetails(BuildContext context, Future<void> Function() delete) {
    showGlassSheet<void>(
      context: context,
      builder: (_) => EntryDetailsSheet(
        id: item.id,
        fallback: item,
        allSubjects: allSubjects,
        colorBorder: colorBorder,
        colorTestsInRed: colorTestsInRed,
        subjectThemes: subjectThemes,
        noInternet: noInternet,
        askWhenDelete: askWhenDelete,
        onOpenAttachment: onOpenAttachment,
        toggleDone: toggleDone,
        editReminder: editReminder,
        delete: () => _delete(context, delete),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = displayedHomeworkLabel(item, allSubjects);
    final subject = label == null ? null : l10n.translateSubjectName(label);
    final type = l10n.translateDashboardServerText(
        displayedHomeworkTitle(item, allSubjects));
    final title = l10n.translateDashboardServerText(
        displayedHomeworkSubtitle(item, allSubjects));
    final style =
        compactRowStyle(item, allSubjects, colorTestsInRed: colorTestsInRed);
    final subjectColor = colorBorder &&
            label != null &&
            subjectThemes.containsKey(label) &&
            style == CompactRowStyle.normal
        ? AppPalette.subjectMarker(Color(subjectThemes[label]!.color), scheme)
        : null;
    final (background, foreground, muted) = switch (style) {
      CompactRowStyle.done => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          scheme.onSurfaceVariant,
        ),
      CompactRowStyle.test => (scheme.exam, scheme.onExam, scheme.onExam),
      CompactRowStyle.normal => (
          scheme.surfaceContainerLowest,
          scheme.onSurface,
          scheme.onSurfaceVariant,
        ),
    };
    final border = switch (style) {
      CompactRowStyle.normal => BorderSide(
          color: subjectColor ?? scheme.outlineVariant,
          width: subjectColor == null ? 1 : 1.5,
        ),
      _ => BorderSide.none,
    };
    final hover = foreground.withValues(alpha: 0.1);
    final isNew = item.isNew || item.isChanged;
    final hasAttachments = item.gradeGroupSubmissions?.isNotEmpty == true;
    final canCheck = item.type != HomeworkType.grade && item.checkable;

    return AutoScrollTag(
      index: index,
      key: ValueKey(index),
      controller: controller,
      highlightColor: Colors.grey.withValues(alpha: 0.5),
      child: CommittedDeleteable(
        key: ValueKey(item.id),
        onDeleted: removeThis,
        showEntryAnimation:
            realNow.difference(item.firstSeen) < const Duration(seconds: 1),
        builder: (context, delete) => Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.gutter,
            0,
            DesignTokens.gutter,
            _rowGap,
          ),
          child: GlassFocusRing(
            shape: const StadiumBorder(),
            activeTint: foreground.withValues(alpha: 0.06),
            child: Material(
              key: ValueKey('compact-row-${item.id}'),
              color: background,
              shape: StadiumBorder(side: border),
              clipBehavior: Clip.antiAlias,
              // Text stands on solid colours here, so the row only gets the rim.
              child: GlassEdge(
                shape: const StadiumBorder(),
                sheen: false,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: compactRowHeight),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          onTap: () => _openDetails(context, delete),
                          label: [
                            if (subject != null) subject,
                            type,
                            if (title.isNotEmpty) title,
                            if (isNew)
                              l10n.text(item.isNew
                                  ? 'dashboard.new'
                                  : 'dashboard.changed'),
                            if (item.grade != null) item.gradeFormatted!,
                            if (canCheck)
                              l10n.text(item.checked
                                  ? 'dashboard.entryDone'
                                  : 'dashboard.entryOpen'),
                          ].join(', '),
                          excludeSemantics: true,
                          child: InkWell(
                            key: ValueKey('compact-row-open-${item.id}'),
                            hoverColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            mouseCursor: NewDesignTheme.clickCursor,
                            onTap: () => _openDetails(context, delete),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  minHeight: compactRowHeight),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Row(
                                  children: [
                                    if (subject != null)
                                      Container(
                                        width: 22,
                                        alignment: Alignment.center,
                                        margin: const EdgeInsets.only(right: 8),
                                        child: Text(
                                          subjectLetter(subject),
                                          key: ValueKey(
                                              'compact-row-subject-${item.id}'),
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            color: subjectColor ?? foreground,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: type,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: foreground,
                                              ),
                                            ),
                                            if (title.isNotEmpty)
                                              TextSpan(
                                                text: '  $title',
                                                style: TextStyle(color: muted),
                                              ),
                                          ],
                                        ),
                                        key: ValueKey(
                                            'compact-row-text-${item.id}'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                    if (hasAttachments)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.attach_file_rounded,
                                          size: 16,
                                          color: muted,
                                        ),
                                      ),
                                    if (isNew)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: _NewBadge(
                                          text: l10n.text(item.isNew
                                              ? 'dashboard.new'
                                              : 'dashboard.changed'),
                                          onExam: style == CompactRowStyle.test,
                                        ),
                                      ),
                                    if (!canCheck) const SizedBox(width: 10),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (item.type == HomeworkType.grade)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GradeBadge(
                            text: item.gradeFormatted!,
                            hundredths: parseBackendGradeHundredths(item.grade),
                            colorized: true,
                            style: theme.textTheme.labelLarge,
                          ),
                        )
                      else if (canCheck)
                        Tooltip(
                          message: l10n.text(item.checked
                              ? 'dashboard.markOpen'
                              : 'dashboard.markDone'),
                          child: Semantics(
                            checked: item.checked,
                            enabled: !noInternet,
                            onTap: noInternet ? null : toggleDone,
                            label: l10n.text('dashboard.markDone'),
                            excludeSemantics: true,
                            child: InkWell(
                              key: ValueKey('compact-row-check-${item.id}'),
                              customBorder: const CircleBorder(),
                              hoverColor: hover,
                              focusColor: hover,
                              mouseCursor: NewDesignTheme.clickCursor,
                              onTap: noInternet ? null : toggleDone,
                              child: SizedBox(
                                width: 48,
                                height: compactRowHeight,
                                child: Center(
                                  child: Opacity(
                                    opacity: noInternet ? 0.5 : 1,
                                    child: NotepadMark(
                                      checked: item.checked,
                                      outline: foreground,
                                      accent: style == CompactRowStyle.test
                                          ? foreground
                                          : scheme.success,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge({required this.text, required this.onExam});

  final String text;
  final bool onExam;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: onExam ? scheme.onExam : scheme.primary,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: onExam ? scheme.exam : scheme.onPrimary,
              ),
        ),
      ),
    );
  }
}

/// Everything a row has no room for: the full text, its history, attachments
/// and the actions on the entry. Follows the entry while the sheet is open.
class EntryDetailsSheet extends StatelessWidget {
  const EntryDetailsSheet({
    super.key,
    required this.id,
    required this.fallback,
    required this.allSubjects,
    required this.colorBorder,
    required this.colorTestsInRed,
    required this.subjectThemes,
    required this.noInternet,
    required this.askWhenDelete,
    required this.onOpenAttachment,
    required this.toggleDone,
    required this.editReminder,
    required this.delete,
  });

  final int id;
  final Homework fallback;
  final BuiltList<String> allSubjects;
  final bool colorBorder, colorTestsInRed, noInternet, askWhenDelete;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final AttachmentCallback onOpenAttachment;
  final VoidCallback toggleDone;
  final Future<void> Function() editReminder, delete;

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, Homework?>(
        connect: (state) => (state.dashboardState.allDays ?? const <Day>[])
            .expand((day) => day.homework)
            .firstWhereOrNull((homework) => homework.id == id),
        builder: (context, current, actions) =>
            _buildSheet(context, current ?? fallback),
      );

  Widget _buildSheet(BuildContext context, Homework item) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = displayedHomeworkLabel(item, allSubjects);
    final type = l10n.translateDashboardServerText(
        displayedHomeworkTitle(item, allSubjects));
    final title = l10n.translateDashboardServerText(
        displayedHomeworkSubtitle(item, allSubjects));
    final selfCreated = isLocalReminderAssessmentHomework(item, allSubjects);
    final canEdit = item.type == HomeworkType.homework && item.deleteable;
    final canCheck = item.type != HomeworkType.grade && item.checkable;
    final navigator = Navigator.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              Text(
                l10n.translateSubjectName(label),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
            Text(type, style: theme.textTheme.titleLarge),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 6),
              LinkifiedText(title, style: theme.textTheme.bodyLarge),
            ],
            if (item.type == HomeworkType.grade) ...[
              const SizedBox(height: 8),
              GradeBadge(
                text: item.gradeFormatted!,
                hundredths: parseBackendGradeHundredths(item.grade),
                colorized: true,
                style: theme.textTheme.titleMedium,
              ),
            ],
            if (!selfCreated && label != null) ...[
              const SizedBox(height: 10),
              Text(
                formatChanged(l10n, item),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (item.previousVersion != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(l10n.text('dashboard.versions')),
                children: [
                  ItemWidget(
                    item: item,
                    allSubjects: allSubjects,
                    isHistory: true,
                    onOpenAttachment: onOpenAttachment,
                    colorBorder: colorBorder,
                    subjectThemes: subjectThemes,
                    colorTestsInRed: colorTestsInRed,
                    askWhenDelete: askWhenDelete,
                    noInternet: noInternet,
                  ),
                ],
              ),
            if (item.gradeGroupSubmissions?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(l10n.text('ui.attachment'),
                  style: theme.textTheme.titleMedium),
              for (final attachment in item.gradeGroupSubmissions!)
                AttachmentWidget(
                  ggs: attachment,
                  noInternet: noInternet,
                  openCallback: onOpenAttachment,
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canCheck)
                  FilledButton.tonalIcon(
                    key: const Key('entry-details-toggle'),
                    onPressed: noInternet ? null : toggleDone,
                    icon: NotepadMark(
                      checked: item.checked,
                      size: 20,
                      outline: scheme.onSecondaryContainer,
                    ),
                    label: Text(l10n.text(item.checked
                        ? 'dashboard.markOpen'
                        : 'dashboard.markDone')),
                  ),
                if (canEdit)
                  OutlinedButton.icon(
                    key: const Key('entry-details-edit'),
                    onPressed: noInternet
                        ? null
                        : () {
                            navigator.pop();
                            editReminder();
                          },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l10n.text('dashboard.editEntry')),
                  ),
                if (item.deleteable)
                  OutlinedButton.icon(
                    key: const Key('entry-details-delete'),
                    onPressed: noInternet
                        ? null
                        : () {
                            navigator.pop();
                            delete();
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.text('button.delete')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
