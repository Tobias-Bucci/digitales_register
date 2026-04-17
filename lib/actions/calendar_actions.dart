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
import 'package:built_redux/built_redux.dart';
import 'package:built_value/built_value.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';

import 'package:dr/utc_date_time.dart';

part 'calendar_actions.g.dart';

abstract class CalendarActions extends ReduxActions {
  factory CalendarActions() => _$CalendarActions();
  CalendarActions._();

  abstract final ActionDispatcher<UtcDateTime> load;
  abstract final ActionDispatcher<CalendarLoadedPayload> loaded;
  abstract final ActionDispatcher<UtcDateTime> setCurrentMonday;
  abstract final ActionDispatcher<CalendarSelection?> select;
  abstract final ActionDispatcher<SubstituteDetectionConfig>
      recalculateSubstitutes;
  abstract final ActionDispatcher<LessonContentSubmission> onDownloadFile;
  abstract final ActionDispatcher<LessonContentSubmission> onOpenFile;
  abstract final ActionDispatcher<LessonContentSubmission> fileAvailable;
}

class CalendarLoadedPayload {
  final Map<String, dynamic> data;
  final SubstituteDetectionConfig config;

  const CalendarLoadedPayload({
    required this.data,
    required this.config,
  });
}

abstract class SubstituteDetectionConfig
    implements
        Built<SubstituteDetectionConfig, SubstituteDetectionConfigBuilder> {
  bool get enabled;
  BuiltMap<String, BuiltList<String>> get primaryTeachers;

  factory SubstituteDetectionConfig(
          [void Function(SubstituteDetectionConfigBuilder)? updates]) =
      _$SubstituteDetectionConfig;
  SubstituteDetectionConfig._();
}
