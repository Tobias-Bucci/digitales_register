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

// The dialog or sheet that adds or edits a reminder, with the suggested
// kinds of assessment.

Future<String?> showEnterReminderDialog(
  BuildContext context, {
  String initialMessage = "",
}) async {
  final prefs = await SharedPreferences.getInstance();
  final showAssessmentHint =
      !(prefs.getBool(_localReminderAssessmentHintKey) ?? false);
  if (showAssessmentHint) {
    await prefs.setBool(_localReminderAssessmentHintKey, true);
  }
  if (!context.mounted) {
    return null;
  }
  // The new dashboard asks in a glass sheet; the Legacy one keeps its dialog.
  if (ResponsiveNavigationScope.isActive(context)) {
    return showGlassSheet<String>(
      context: context,
      builder: (context) => ControlledTextBuilder(
        initialText: initialMessage,
        builder: (context, controller) => _ReminderEntrySheet(
          controller: controller,
          showAssessmentHint: showAssessmentHint,
        ),
      ),
    );
  }
  return showDialog(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return ControlledTextBuilder(
        initialText: initialMessage,
        builder: (context, controller) {
          final message = controller.text;
          return InfoDialog(
            title: Text(l10n.text('dashboard.reminder')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showAssessmentHint)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.text(
                                  'dashboard.assessmentShortcutHintTitle'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.text(
                                'dashboard.assessmentShortcutHintBody',
                                args: {
                                  'test': '/test',
                                  'classwork': '/cw',
                                  'exam': '/exam',
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: l10n.text('dashboard.reminderHint'),
                      ),
                    ),
                    if (localReminderAssessmentSuggestions(message)
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.text('dashboard.assessmentShortcutSuggestions'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _AssessmentSuggestionChips(controller: controller),
                    ],
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(l10n.text('common.cancel')),
              ),
              ElevatedButton(
                onPressed: message.isNullOrEmpty
                    ? null
                    : () {
                        Navigator.pop(context, controller.text);
                      },
                child: Text(l10n.text('button.save')),
              ),
            ],
          );
        },
      );
    },
  );
}

/// The commands that fit the text of [controller], such as `/test`, as chips
/// that complete it.
class _AssessmentSuggestionChips extends StatelessWidget {
  const _AssessmentSuggestionChips({
    required this.controller,
    this.mouseCursor,
  });

  final TextEditingController controller;

  /// The hand cursor of the new design, which chips do not take from
  /// `NewDesignTheme`. Null in Legacy.
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final suggestion
            in localReminderAssessmentSuggestions(controller.text))
          ActionChip(
            mouseCursor: mouseCursor,
            label: Text(
              '/${suggestion.command} - ${_localizedAssessmentSuggestionLabel(l10n, suggestion.type)}',
            ),
            onPressed: () {
              final replaced = applyLocalReminderAssessmentSuggestion(
                controller.text,
                suggestion,
              );
              controller.value = controller.value.copyWith(
                text: replaced,
                selection: TextSelection.collapsed(
                  offset: replaced.length,
                ),
              );
            },
          ),
      ],
    );
  }
}

/// [showEnterReminderDialog] in the new design: the same form, hints and
/// commands in a glass sheet, above the keyboard on phones.
class _ReminderEntrySheet extends StatelessWidget {
  const _ReminderEntrySheet({
    required this.controller,
    required this.showAssessmentHint,
  });

  final TextEditingController controller;
  final bool showAssessmentHint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = controller.text;
    return SettingsSheetKeyboardInset(
      child: GlassPanel(
        title: l10n.text('dashboard.reminder'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showAssessmentHint) ...[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('dashboard.assessmentShortcutHintTitle'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.text(
                        'dashboard.assessmentShortcutHintBody',
                        args: {
                          'test': '/test',
                          'classwork': '/cw',
                          'exam': '/exam',
                        },
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.text('dashboard.reminderHint'),
              ),
            ),
            if (localReminderAssessmentSuggestions(message).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.text('dashboard.assessmentShortcutSuggestions'),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              _AssessmentSuggestionChips(
                controller: controller,
                mouseCursor: NewDesignTheme.clickCursor,
              ),
            ],
            const SizedBox(height: 16),
            SettingsSheetActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.text('common.cancel')),
                ),
                FilledButton(
                  onPressed: message.isNullOrEmpty
                      ? null
                      : () => Navigator.pop(context, controller.text),
                  child: Text(l10n.text('button.save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _localizedAssessmentSuggestionLabel(
  AppLocalizations l10n,
  LocalReminderAssessmentType type,
) {
  switch (type) {
    case LocalReminderAssessmentType.test:
      return l10n.text('dashboard.test');
    case LocalReminderAssessmentType.classwork:
      return l10n.text('dashboard.schoolwork');
    case LocalReminderAssessmentType.exam:
      return l10n.text('dashboard.exam');
  }
}
