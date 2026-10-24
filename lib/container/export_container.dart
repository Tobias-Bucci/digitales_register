// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/middleware/middleware.dart' show loadExportCalendarYear;
import 'package:dr/ui/export_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class ExportContainer extends StatelessWidget {
  const ExportContainer({super.key, this.initialCategory});
  final ExportCategory? initialCategory;
  @override
  Widget build(BuildContext context) => StoreConnection<AppState, AppActions,
          AppState>(
      connect: (state) => state,
      builder: (context, state, actions) => _HydratedExport(
          key: ValueKey(
              '${state.url}|${state.loginState.username}|${state.loginState.loggedIn}'),
          state: state,
          actions: actions,
          initialCategory: initialCategory));
}

class _HydratedExport extends StatefulWidget {
  const _HydratedExport(
      {super.key,
      required this.state,
      required this.actions,
      this.initialCategory});
  final AppState state;
  final AppActions actions;
  final ExportCategory? initialCategory;
  @override
  State<_HydratedExport> createState() => _HydratedExportState();
}

class _HydratedExportState extends State<_HydratedExport> {
  bool loading = true;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    final actions = widget.actions;
    final today = UtcDateTime.now();
    final monday =
        today.stripTime().subtract(Duration(days: today.weekday - 1));
    final operations = <Future<void> Function()>[
      () async {
        if (widget.state.config != null) {
          await actions.gradesActions.load(Semester.all);
        }
      },
      () async {
        await actions.messagesActions.load();
      },
      () async {
        await actions.certificateActions.load();
      },
      () async {
        await actions.absencesActions.load();
      },
      () async {
        await actions.dashboardActions.load(widget.state.dashboardState.future);
      },
      () async {
        await actions.calendarActions.load(monday);
      },
      () async {
        final complete = await loadExportCalendarYear(
            state: () => widget.state,
            onLoaded: actions.calendarActions.loaded.call,
            isActive: () => mounted);
        if (!complete) failed = true;
      },
    ];
    for (final operation in operations) {
      if (!mounted || !widget.state.loginState.loggedIn) return;
      try {
        await operation();
      } catch (_) {
        failed = true;
      }
    }
    if (mounted) {
      setState(() {
        loading = false;
        failed = failed || widget.state.noInternet;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ExportPage(
      state: widget.state,
      initialCategory: widget.initialCategory,
      loading: loading,
      loadFailed: failed,
      onReload: _load);
}

Future<void> openExportPage(BuildContext context, {ExportCategory? category}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/export'),
        builder: (_) => ExportContainer(initialCategory: category)));
