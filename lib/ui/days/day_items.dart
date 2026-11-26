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

// One day of the dashboard, its entries, their history and attachments,
// and deleting a reminder.

class DayWidget extends StatelessWidget {
  final DaysViewModel vm;

  final AddReminderCallback addReminderCallback;
  final EditReminderCallback editReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AttachmentCallback onOpenAttachment;
  final bool colorBorders, colorTestsInRed;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final BuiltList<String> allSubjects;

  final Day day;

  final AutoScrollController controller;
  final int index;

  final bool showLastFetched;

  const DayWidget({
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
    required this.subjectThemes,
    required this.allSubjects,
    required this.colorTestsInRed,
    required this.showLastFetched,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    var i = index;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.dashboardDayLabel(day.date),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (showLastFetched)
                      Text(
                        l10n.text(
                          'dashboard.syncLast',
                          args: {'time': l10n.formatTimeAgo(day.lastRequested)},
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
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
                    icon: badge.Badge(
                      badgeContent: Icon(
                        Icons.delete,
                        size: 15,
                        color: day.deletedHomework.any((h) => h.isChanged)
                            ? Colors.white
                            : null,
                      ),
                      badgeStyle: badge.BadgeStyle(
                        badgeColor: day.deletedHomework.any((h) => h.isChanged)
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).scaffoldBackgroundColor,
                        padding: EdgeInsets.zero,
                        elevation: 0,
                      ),
                      badgeAnimation: badge.BadgeAnimation.scale(
                        toAnimate: day.deletedHomework.any((h) => h.isChanged),
                      ),
                      position: badge.BadgePosition.topStart(),
                      child: const Icon(Icons.info_outline),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) {
                          return InfoDialog(
                            title: Text(l10n.text('dashboard.deletedEntries')),
                            content: SingleChildScrollView(
                              child: Column(
                                children: day.deletedHomework
                                    .map(
                                      (i) => ItemWidget(
                                        item: i,
                                        allSubjects: allSubjects,
                                        isDeletedView: true,
                                        onOpenAttachment: onOpenAttachment,
                                        colorBorder: colorBorders,
                                        subjectThemes: subjectThemes,
                                        colorTestsInRed: colorTestsInRed,
                                        askWhenDelete: vm.askWhenDelete,
                                        noInternet: vm.noInternet,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const Spacer(),
              if (vm.showAddReminder)
                IconButton(
                  tooltip: l10n.text('dashboard.addEntry'),
                  icon: const Icon(Icons.add),
                  onPressed: vm.noInternet
                      ? null
                      : () async {
                          final message = await showEnterReminderDialog(
                            context,
                          );
                          if (message != null) {
                            addReminderCallback(day, message);
                          }
                        },
                ),
            ],
          ),
        ),
        for (final hw in day.homework)
          ItemWidget(
            item: hw,
            toggleDone: () => toggleDoneCallback(hw, !hw.checked),
            editReminder: () async {
              final message = await showEnterReminderDialog(
                context,
                initialMessage: hw.subtitle.isNotEmpty ? hw.subtitle : hw.title,
              );
              if (message != null) {
                editReminderCallback(hw, day, message);
              }
            },
            removeThis: () => removeReminderCallback(hw, day),
            setDoNotAskWhenDelete: setDoNotAskWhenDeleteCallback,
            askWhenDelete: vm.askWhenDelete,
            noInternet: vm.noInternet,
            controller: controller,
            index: ++i,
            onOpenAttachment: onOpenAttachment,
            subjectThemes: subjectThemes,
            allSubjects: allSubjects,
            colorBorder: colorBorders,
            colorTestsInRed: colorTestsInRed,
          ),
      ],
    );
  }
}

class ItemWidget extends StatelessWidget {
  final Homework item;
  final BuiltList<String> allSubjects;
  final Future<void> Function()? editReminder;
  final VoidCallback? removeThis;
  final VoidCallback? toggleDone;
  final VoidCallback? setDoNotAskWhenDelete;
  final bool askWhenDelete,
      isHistory,
      isDeletedView,
      noInternet,
      isCurrent,
      colorBorder,
      colorTestsInRed;
  final AttachmentCallback? onOpenAttachment;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  final AutoScrollController? controller;
  final int? index;

  const ItemWidget({
    super.key,
    required this.item,
    required this.allSubjects,
    this.editReminder,
    this.removeThis,
    this.toggleDone,
    required this.askWhenDelete,
    this.setDoNotAskWhenDelete,
    this.isHistory = false,
    this.controller,
    this.index,
    this.isDeletedView = false,
    required this.noInternet,
    this.isCurrent = true,
    this.onOpenAttachment,
    required this.colorBorder,
    required this.subjectThemes,
    required this.colorTestsInRed,
  });

  void _showHistory(BuildContext context) {
    final l10n = context.l10n;
    // if we are in the deleted view, show the history for the previous item
    final historyItem = isDeletedView ? item.previousVersion : item;
    showDialog<void>(
      context: context,
      builder: (context) {
        return InfoDialog(
          title: Text(historyItem!.title),
          content: SingleChildScrollView(
            child: Column(
              children: [
                Text(formatChanged(l10n, historyItem)),
                if (historyItem.previousVersion != null)
                  ExpansionTile(
                    title: Text(l10n.text('dashboard.versions')),
                    children: <Widget>[
                      ItemWidget(
                        item: historyItem,
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
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getBorderColor(BuildContext context) {
    if (item.checked) {
      return Theme.of(context).colorScheme.success;
    }
    if (displayedHomeworkWarning(item, allSubjects) && colorTestsInRed) {
      return Theme.of(context).colorScheme.exam;
    }
    final displayLabel = displayedHomeworkLabel(item, allSubjects);
    if (colorBorder &&
        displayLabel != null &&
        subjectThemes.containsKey(displayLabel)) {
      return AppPalette.subjectMarker(
        Color(subjectThemes[displayLabel]!.color),
        Theme.of(context).colorScheme,
      );
    }
    return Theme.of(context).dividerColor.withValues(alpha: 0.3);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCompleted = item.checked && !isHistory && !isDeletedView;
    final displayLabel = displayedHomeworkLabel(item, allSubjects);
    final displayTitle = displayedHomeworkTitle(item, allSubjects);
    final displaySubtitle = displayedHomeworkSubtitle(item, allSubjects);
    final isSelfCreatedAssessment = parseLocalReminderAssessment(
          item.subtitle.isNotEmpty ? item.subtitle : item.title,
          allSubjects,
        ) !=
        null;
    final canEditReminder = !isHistory &&
        !isDeletedView &&
        item.type == HomeworkType.homework &&
        item.deleteable &&
        editReminder != null;
    Future<void> handleDelete(Future<void> Function() delete) =>
        deleteReminderWithConfirmation(
          context,
          askWhenDelete: askWhenDelete,
          setDoNotAskWhenDelete: setDoNotAskWhenDelete,
          delete: delete,
        );

    Widget child = CommittedDeleteable(
      key: ValueKey(item.id),
      onDeleted: () {
        removeThis!();
      },
      // this is a new entry or a reminder the user has just entered
      showEntryAnimation:
          realNow.difference(item.firstSeen) < const Duration(seconds: 1),
      builder: (context, delete) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: _getBorderColor(context),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        top: 8,
                        bottom: 6,
                      ),
                      child: Column(
                        children: <Widget>[
                          if (displayLabel != null)
                            Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                Center(
                                  child: Text(
                                    l10n.translateSubjectName(displayLabel),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if ((!isHistory &&
                                        (item.isNew || item.isChanged)) ||
                                    (isHistory && isCurrent))
                                  Positioned(
                                    right: 0,
                                    child: badge.Badge(
                                      badgeStyle: badge.BadgeStyle(
                                        shape: badge.BadgeShape.square,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      badgeContent: Text(
                                        isHistory && isCurrent
                                            ? l10n.text('dashboard.current')
                                            : item.isNew
                                                ? l10n.text('dashboard.new')
                                                : item.deleted
                                                    ? l10n.text(
                                                        'dashboard.deleted')
                                                    : l10n.text(
                                                        'dashboard.changed'),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              l10n.translateDashboardServerText(displayTitle),
                              style: TextStyle(
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: displaySubtitle.isNullOrEmpty
                                ? null
                                : LinkifiedText(
                                    l10n.translateDashboardServerText(
                                      displaySubtitle,
                                    ),
                                    style: TextStyle(
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                            leading:
                                !isHistory && !isDeletedView && item.deleteable
                                    ? IconButton(
                                        tooltip: l10n.text('button.delete'),
                                        icon: const Icon(Icons.close),
                                        onPressed: noInternet
                                            ? null
                                            : () => handleDelete(delete),
                                        padding: EdgeInsets.zero,
                                      )
                                    : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      if (canEditReminder)
                        IconButton(
                          tooltip: l10n.text('dashboard.editEntry'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: noInternet
                              ? null
                              : () async {
                                  await editReminder!();
                                },
                        ),
                      if (!isHistory &&
                          displayLabel != null &&
                          !isSelfCreatedAssessment)
                        IconButton(
                          tooltip: l10n.text('dashboard.entryHistory'),
                          icon: (isDeletedView
                                      ? item.previousVersion!.previousVersion
                                      : item.previousVersion) !=
                                  null
                              ? badge.Badge(
                                  badgeContent:
                                      const Icon(Icons.edit, size: 15),
                                  badgeStyle: badge.BadgeStyle(
                                    padding: EdgeInsets.zero,
                                    badgeColor: isDeletedView
                                        ? Theme.of(context)
                                                .dialogTheme
                                                .backgroundColor ??
                                            Theme.of(context).canvasColor
                                        : Theme.of(context)
                                            .scaffoldBackgroundColor,
                                    elevation: 0,
                                  ),
                                  badgeAnimation:
                                      const badge.BadgeAnimation.scale(
                                          toAnimate: false),
                                  child: const Icon(
                                    Icons.info_outline,
                                  ),
                                )
                              : const Icon(
                                  Icons.info_outline,
                                ),
                          onPressed: () {
                            _showHistory(context);
                          },
                        ),
                      if (item.type == HomeworkType.grade)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(
                            item.gradeFormatted!,
                            style: TextStyle(
                                color: gradeColor(
                                    parseBackendGradeHundredths(item.grade)),
                                fontSize: 30),
                          ),
                        )
                      else if (!isHistory && !isDeletedView && item.checkable)
                        Checkbox(
                          semanticLabel: l10n.text('dashboard.markDone'),
                          visualDensity: VisualDensity.standard,
                          activeColor: Theme.of(context).colorScheme.success,
                          value: item.checked,
                          onChanged: noInternet
                              ? null
                              : (done) {
                                  toggleDone!();
                                },
                        ),
                    ],
                  ),
                ],
              ),
              if (isHistory || isDeletedView) ...[
                const Divider(height: 0),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    formatChanged(context.l10n, item),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              if (item.gradeGroupSubmissions?.isNotEmpty == true) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(context.l10n.text('ui.attachment'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                for (final attachment in item.gradeGroupSubmissions!)
                  AttachmentWidget(
                    ggs: attachment,
                    noInternet: noInternet,
                    openCallback: onOpenAttachment,
                  )
              ]
            ],
          ),
        ),
      ),
    );
    if (!isHistory && !isDeletedView) {
      child = AutoScrollTag(
        index: index!,
        key: ValueKey(index),
        controller: controller!,
        highlightColor: Colors.grey.withValues(alpha: 0.5),
        child: child,
      );
    }
    return Column(
      key: ValueKey(item.id),
      children: <Widget>[
        child,
        if (isHistory && item.previousVersion != null)
          ItemWidget(
            isHistory: true,
            isCurrent: false,
            item: item.previousVersion!,
            allSubjects: allSubjects,
            onOpenAttachment: onOpenAttachment,
            colorBorder: colorBorder,
            subjectThemes: subjectThemes,
            colorTestsInRed: colorTestsInRed,
            askWhenDelete: askWhenDelete,
            noInternet: noInternet,
          ),
      ],
    );
  }
}

Future<(bool, bool)> _showConfirmDelete(BuildContext context) async {
  final l10n = context.l10n;
  var ask = true;
  final delete = await showDialog<bool>(
    context: context,
    builder: (context) {
      return InfoDialog(
        content: StatefulBuilder(
          builder: (context, setState) => SwitchListTile.adaptive(
            title: Text(l10n.text('dashboard.neverAsk')),
            onChanged: (bool value) {
              setState(() => ask = !value);
            },
            value: !ask,
          ),
        ),
        title: Text(l10n.text('dashboard.reminder.deleteQuestion')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.text('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.text('button.delete')),
          )
        ],
      );
    },
  );
  return (delete ?? false, ask);
}

/// Runs [delete], after asking first if the user wants to be asked.
Future<void> deleteReminderWithConfirmation(
  BuildContext context, {
  required bool askWhenDelete,
  required VoidCallback? setDoNotAskWhenDelete,
  required Future<void> Function() delete,
}) async {
  if (askWhenDelete) {
    final confirmationResult = await _showConfirmDelete(context);
    final shouldDelete = confirmationResult.$1;
    final ask = confirmationResult.$2;
    if (shouldDelete == true) {
      if (!ask) {
        setDoNotAskWhenDelete!();
      }
      await delete();
    }
  } else {
    await delete();
  }
}

/// Describes when [hw] was entered, changed, deleted or restored, in the
/// selected language. The entry only keeps the observation times, so the text
/// is rendered from them on every build.
String formatChanged(AppLocalizations l10n, Homework hw) {
  final localeTag = l10n.locale.toLanguageTag();
  final dateTime = DateFormat('EEEE, dd.MM, HH:mm', localeTag);
  final time = DateFormat('HH:mm', localeTag);
  final String when;
  if (hw.lastNotSeen == null) {
    when = l10n.text(
      'dashboard.history.before',
      args: {'date': dateTime.format(hw.firstSeen)},
    );
  } else if (hw.firstSeen.stripTime() == hw.lastNotSeen!.stripTime()) {
    when = l10n.text('dashboard.history.sameDay', args: {
      'date': DateFormat('EEEE, dd.MM', localeTag).format(hw.firstSeen),
      'from': time.format(hw.lastNotSeen!),
      'to': time.format(hw.firstSeen),
    });
  } else {
    when = l10n.text('dashboard.history.between', args: {
      'from': dateTime.format(hw.lastNotSeen!),
      'to': dateTime.format(hw.firstSeen),
    });
  }
  final String event;
  if (hw.deleted) {
    event = 'dashboard.history.deleted';
  } else if (hw.previousVersion == null) {
    event = 'dashboard.history.created';
  } else if (hw.previousVersion!.deleted) {
    event = 'dashboard.history.restored';
  } else {
    event = 'dashboard.history.changed';
  }
  return l10n.text(event, args: {'when': when});
}

class AttachmentWidget extends StatelessWidget {
  final GradeGroupSubmission ggs;

  /// Opens the attachment; without one the attachment is only listed.
  final AttachmentCallback? openCallback;
  final bool noInternet;

  const AttachmentWidget(
      {super.key,
      required this.ggs,
      required this.noInternet,
      required this.openCallback});
  @override
  Widget build(BuildContext context) {
    final open = context.l10n.text('ui.open');
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const Divider(
            indent: 16,
            height: 0,
          ),
          if (ggs.isLink) ...[
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(ggs.originalName),
              subtitle: linkCaption(ggs.originalName, ggs.link) == null
                  ? null
                  : Text(linkCaption(ggs.originalName, ggs.link)!),
            ),
            TextButton.icon(
              // Opening a link is up to the browser, online or not.
              onPressed:
                  openCallback == null || parseExternalLink(ggs.link) == null
                      ? null
                      : () {
                          openCallback!(ggs);
                        },
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(open),
            ),
          ] else ...[
            ListTile(title: Text(ggs.originalName)),
            AnimatedLinearProgressIndicator(show: ggs.downloading),
            TextButton(
              onPressed:
                  openCallback == null || (!ggs.fileAvailable && noInternet)
                      ? null
                      : () {
                          openCallback!(ggs);
                        },
              child: Text(open),
            ),
          ],
        ],
      ),
    );
  }
}
