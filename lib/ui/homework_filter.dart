// Copyright (C) 2021 Michael Debertol
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

  const HomeworkFilter({super.key, required this.vm, required this.callback});

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

    void updateBlacklist(
      void Function(ListBuilder<HomeworkType> blacklist) updates,
      void Function(void Function()) setSheetState,
    ) {
      updates(localBlacklist);
      widget.callback(ListBuilder<HomeworkType>(localBlacklist.build()));
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
                      "Wähle aus, welche Inhalte angezeigt werden.",
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
    final activeFilterCount = widget.vm.currentBlacklist.length;
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
