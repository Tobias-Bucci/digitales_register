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

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';

class LastFetchedOverlay extends StatelessWidget {
  final bool noInternet;
  final Widget child;
  final UtcDateTime? lastFetched;
  const LastFetchedOverlay({
    super.key,
    required this.child,
    required this.noInternet,
    required this.lastFetched,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (lastFetched == null || !noInternet) {
      return child;
    }
    return RawLastFetchedOverlay(
      message: l10n.text(
        'grades.offlineMode',
        args: {'time': l10n.formatTimeAgo(lastFetched!)},
      ),
      child: child,
    );
  }
}

class RawLastFetchedOverlay extends StatelessWidget {
  final String? message;
  final Widget child;
  const RawLastFetchedOverlay({
    super.key,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return child;
    }
    return Stack(
      children: [
        child,
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 3,
              horizontal: 8,
            ).copyWith(right: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              message!,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

String formatTimeAgo(UtcDateTime dateTime) {
  return dateTime.toIso8601String();
}
