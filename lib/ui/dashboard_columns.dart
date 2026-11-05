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

import 'dart:math' as math;

import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';

/// How the dashboard uses a wide window: the summary and the banner keep the
/// width they have on a phone and stay in place beside the day list.
@immutable
class DashboardColumns {
  const DashboardColumns._(this.margin);

  /// Below this width of the window the day list would get too narrow.
  static const double minWindowWidth = 1080;

  static const double sideWidth = 380;

  /// Both columns together. A wider window only gets wider margins, so that a
  /// row stays readable.
  static const double maxWidth = sideWidth + DesignTokens.contentMaxWidth;

  /// Null for a window that is too narrow for two columns.
  static DashboardColumns? forWindow(double windowWidth) {
    if (windowWidth < minWindowWidth) return null;
    final body = windowWidth - appNavigationRailExtent;
    return DashboardColumns._(math.max(0, (body - maxWidth) / 2));
  }

  /// The free space on each side of the columns.
  final double margin;

  /// Keeps the content of a list in its column. The list itself reaches the
  /// edge of the window, and with it its scrollbar.
  EdgeInsets listPadding(EdgeInsets safeArea) => EdgeInsets.only(
        top: safeArea.top,
        right: margin,
        bottom: safeArea.bottom,
      );
}

/// [side] and [main] next to each other, as [columns] says.
class DashboardColumnsView extends StatelessWidget {
  const DashboardColumnsView({
    super.key,
    required this.columns,
    required this.side,
    required this.main,
  });

  final DashboardColumns columns;
  final Widget side, main;

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: columns.margin),
          child: SizedBox(
            key: const Key('dashboard-side-column'),
            width: DashboardColumns.sideWidth,
            // It only has to scroll when a low window cannot show all of it.
            child: SingleChildScrollView(
              primary: false,
              padding: EdgeInsets.only(
                top: safeArea.top,
                bottom: safeArea.bottom,
              ),
              child: side,
            ),
          ),
        ),
        Expanded(child: main),
      ],
    );
  }
}
