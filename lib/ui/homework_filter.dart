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

import 'package:built_collection/built_collection.dart';
import 'package:dr/container/homework_filter_container.dart';
import 'package:dr/data.dart';
import 'package:flutter/material.dart';

typedef HomeworkBlacklistCallback = void Function(
    ListBuilder<HomeworkType> blacklist);

class HomeworkFilter extends StatefulWidget {
  final HomeworkFilterVM vm;
  final HomeworkBlacklistCallback callback;
  final bool showEmptyDays;
  final ValueChanged<bool> onShowEmptyDaysChanged;

  const HomeworkFilter({
    super.key,
    required this.vm,
    required this.callback,
    required this.showEmptyDays,
    required this.onShowEmptyDaysChanged,
  });

  @override
  _HomeworkFilterState createState() => _HomeworkFilterState();
}

class _HomeworkFilterState extends State<HomeworkFilter>
    with AutomaticKeepAliveClientMixin {
  ListBuilder<HomeworkType> _toggleType(
    ListBuilder<HomeworkType> blacklist,
    HomeworkType type,
    bool visible,
  ) {
    if (visible) {
      blacklist.remove(type);
    } else {
      blacklist.add(type);
    }
    return blacklist;
  }

  ListBuilder<HomeworkType> _toggleGroup(
    ListBuilder<HomeworkType> blacklist,
    List<HomeworkType> types,
    bool visible,
  ) {
    for (final type in types) {
      if (visible) {
        blacklist.remove(type);
      } else {
        blacklist.add(type);
      }
    }
    return blacklist;
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final localBlacklist = widget.vm.currentBlacklist.toBuilder();
    var showEmptyDays = widget.showEmptyDays;

    void updateBlacklist(
      void Function(ListBuilder<HomeworkType> blacklist) updates,
      void Function(void Function()) setSheetState,
    ) {
      updates(localBlacklist);
      widget.callback(ListBuilder<HomeworkType>(localBlacklist.build()));
      setSheetState(() {});
    }

    void updateShowEmptyDays(
      bool value,
      void Function(void Function()) setSheetState,
    ) {
      showEmptyDays = value;
      widget.onShowEmptyDaysChanged(value);
      setSheetState(() {});
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final localBlacklistSnapshot = localBlacklist.build();
            final hasGrades =
                !localBlacklistSnapshot.contains(HomeworkType.grade);
            final hasHomework =
                !localBlacklistSnapshot.contains(HomeworkType.homework);
            final hasObservation =
                !localBlacklistSnapshot.contains(HomeworkType.observation);
            final activeFilterCount = [
              !hasGrades,
              !hasHomework,
              !hasObservation,
              !showEmptyDays,
            ].where((isDisabled) => isDisabled).length;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Dashboard-Filter",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeFilterCount == 0
                          ? "Wähle aus, welche Inhalte angezeigt werden."
                          : "$activeFilterCount Filter deaktiviert.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (v) {
                        updateBlacklist(
                          (blacklist) => _toggleGroup(
                            blacklist,
                            const [
                              HomeworkType.grade,
                              HomeworkType.gradeGroup,
                            ],
                            v!,
                          ),
                          setSheetState,
                        );
                      },
                      title: const Text("Noten & Tests"),
                      value: hasGrades,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (v) {
                        updateBlacklist(
                          (blacklist) => _toggleGroup(
                            blacklist,
                            const [
                              HomeworkType.homework,
                              HomeworkType.lessonHomework,
                            ],
                            v!,
                          ),
                          setSheetState,
                        );
                      },
                      title: const Text("Hausaufgaben & Erinnerungen"),
                      value: hasHomework,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (v) {
                        updateBlacklist(
                          (blacklist) => _toggleType(
                            blacklist,
                            HomeworkType.observation,
                            v!,
                          ),
                          setSheetState,
                        );
                      },
                      title: const Text("Beobachtungen"),
                      value: hasObservation,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (v) {
                        updateShowEmptyDays(v ?? false, setSheetState);
                      },
                      title: const Text("Leere Tage anzeigen"),
                      value: showEmptyDays,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasGrades = !widget.vm.currentBlacklist.contains(HomeworkType.grade);
    final hasHomework =
        !widget.vm.currentBlacklist.contains(HomeworkType.homework);
    final hasObservation =
        !widget.vm.currentBlacklist.contains(HomeworkType.observation);
    final activeFilterCount = [
      !hasGrades,
      !hasHomework,
      !hasObservation,
      !widget.showEmptyDays,
    ].where((isDisabled) => isDisabled).length;
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: () => _openFilterSheet(context),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        icon: const Icon(Icons.tune_rounded),
        label: Text(
            activeFilterCount > 0 ? "Filter ($activeFilterCount)" : "Filter"),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
