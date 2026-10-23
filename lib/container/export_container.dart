// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/ui/export_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class ExportContainer extends StatelessWidget {
  const ExportContainer({super.key, this.initialCategory});
  final ExportCategory? initialCategory;

  @override
  Widget build(BuildContext context) => StoreConnection<AppState, AppActions,
          AppState>(
      connect: (state) => state,
      builder: (context, state, actions) => ExportPage(
          key: ValueKey(
              '${state.url}|${state.loginState.username}|${state.loginState.loggedIn}'),
          state: state,
          initialCategory: initialCategory));
}

Future<void> openExportPage(BuildContext context, {ExportCategory? category}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/export'),
        builder: (_) => ExportContainer(initialCategory: category)));
