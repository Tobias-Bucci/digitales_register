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

part of '../settings_page_widget.dart';

// The page of the favorite subjects.

class _FavoriteSubjectsSettingsPage extends StatefulWidget {
  const _FavoriteSubjectsSettingsPage({
    required this.favoriteSubjects,
    required this.allSubjects,
    required this.onSetFavoriteSubjects,
  });

  final List<String> favoriteSubjects;
  final List<String> allSubjects;
  final OnSettingChanged<List<String>> onSetFavoriteSubjects;

  @override
  State<_FavoriteSubjectsSettingsPage> createState() =>
      _FavoriteSubjectsSettingsPageState();
}

class _FavoriteSubjectsSettingsPageState
    extends State<_FavoriteSubjectsSettingsPage> {
  late List<String> _favoriteSubjects;

  List<String> get _notYetFavoriteSubjects => widget.allSubjects
      .where(
          (subject) => !containsSubjectIgnoreCase(_favoriteSubjects, subject))
      .toList();

  @override
  void initState() {
    super.initState();
    _favoriteSubjects = List<String>.from(widget.favoriteSubjects);
  }

  Future<void> _addFavorite() async {
    final newSubject = await _showAddSubject(
      context,
      availableSubjects: _notYetFavoriteSubjects,
      title: context.l10n.text('settings.calendar.favoriteSubjects'),
      requireSuggestionMatch: true,
    );
    if (newSubject == null ||
        !mounted ||
        containsSubjectIgnoreCase(
          _favoriteSubjects,
          newSubject,
        )) {
      return;
    }
    setState(() {
      _favoriteSubjects.add(newSubject);
    });
    widget.onSetFavoriteSubjects(_favoriteSubjects);
  }

  Widget _favorite(
    String subject,
    Widget Function(BuildContext, Future<void> Function()) builder, {
    Duration duration = const Duration(milliseconds: 250),
  }) =>
      CommittedDeleteable(
        onDeleted: () {
          _favoriteSubjects.remove(subject);
          widget.onSetFavoriteSubjects(List.of(_favoriteSubjects));
          if (mounted) setState(() {});
        },
        showExitAnimation: _favoriteSubjects.length != 1,
        showEntryAnimation: _favoriteSubjects.length != 1,
        duration: duration,
        key: ValueKey(subject),
        builder: builder,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (ResponsiveNavigationScope.isActive(context)) {
      return _SettingsDetailPage(
        key: const Key('settings-favorite-subjects-page'),
        title: l10n.text('settings.calendar.favoriteSubjects'),
        children: [
          SettingsSectionNew(
            key: const Key('settings-favorite-subjects-list'),
            title: l10n.text('grades.subjects'),
            count: _favoriteSubjects.length,
            trailing: SettingsHeadingButton(
              key: const Key('settings-favorite-subjects-add'),
              tooltip: l10n.text('settings.addSubject'),
              onPressed: _notYetFavoriteSubjects.isEmpty ? null : _addFavorite,
            ),
            children: [
              if (_favoriteSubjects.isEmpty)
                SettingsEmptyRow(
                  text: l10n.text('settings.calendar.noFavoriteSubject'),
                ),
              for (final subject in _favoriteSubjects)
                _favorite(
                  subject,
                  duration: _settingsMotion(context),
                  (context, delete) => ListTile(
                    leading: const Icon(Icons.star_outline_rounded),
                    title: Text(subject),
                    trailing: _RemoveButton(onPressed: delete),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    return _SettingsDetailPage(
      key: const Key('settings-favorite-subjects-page'),
      title: l10n.text('settings.calendar.favoriteSubjects'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(l10n.text('settings.calendar.favoriteSubjects')),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _notYetFavoriteSubjects.isEmpty ? null : _addFavorite,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: _favoriteSubjects.isEmpty
              ? ListTile(
                  title: Text(
                    l10n.text('settings.calendar.noFavoriteSubject'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    for (final subject in _favoriteSubjects)
                      _favorite(
                        subject,
                        (context, delete) => ListTile(
                          title: Text(subject),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: delete,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
