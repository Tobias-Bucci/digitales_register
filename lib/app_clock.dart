// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central source for the date the user-facing app treats as "today".
///
/// The simulated date is deliberately only exposed while the local demo guest
/// is active. Runtime concerns such as cache expiry and session timeouts must
/// continue to use [DateTime.now] directly.
class AppClock extends ChangeNotifier {
  static final DateTime demoSchoolYearStart = DateTime(2025, 9, 10);
  static final DateTime demoSchoolYearEnd = DateTime(2026, 6, 6);
  static final DateTime defaultDemoDate = DateTime(2025, 10, 10);

  static const String _preferenceKey = 'demoSimulatedDate';

  bool _demoMode = false;
  DateTime? _selectedDemoDate;
  int _revision = 0;

  bool get isDemoMode => _demoMode;
  DateTime? get selectedDemoDate => _selectedDemoDate;
  DateTime get simulatedDate => _selectedDemoDate ?? defaultDemoDate;
  int get revision => _revision;

  DateTime get now {
    final realNow = DateTime.now();
    if (!_demoMode) {
      return realNow;
    }
    final date = simulatedDate;
    return DateTime(
      date.year,
      date.month,
      date.day,
      realNow.hour,
      realNow.minute,
      realNow.second,
      realNow.millisecond,
      realNow.microsecond,
    );
  }

  Future<void> initialize() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_preferenceKey);
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed != null && isWithinDemoSchoolYear(parsed)) {
      _selectedDemoDate = _dateOnly(parsed);
    }
  }

  void setDemoMode(bool enabled) {
    if (_demoMode == enabled) {
      return;
    }
    _demoMode = enabled;
    _notifyDateChanged();
  }

  Future<void> setSimulatedDate(DateTime date) async {
    if (!_demoMode) {
      throw StateError('A simulated date is only available to the demo guest.');
    }
    final normalized = _dateOnly(date);
    if (!isWithinDemoSchoolYear(normalized)) {
      throw RangeError.range(
        normalized.millisecondsSinceEpoch,
        demoSchoolYearStart.millisecondsSinceEpoch,
        demoSchoolYearEnd.millisecondsSinceEpoch,
        'date',
        'The simulated date must be inside the demo school year.',
      );
    }
    if (_selectedDemoDate == normalized) {
      return;
    }
    _selectedDemoDate = normalized;
    await (await SharedPreferences.getInstance())
        .setString(_preferenceKey, normalized.toIso8601String());
    _notifyDateChanged();
  }

  Future<void> resetSimulatedDate() async {
    if (!_demoMode) {
      throw StateError('A simulated date is only available to the demo guest.');
    }
    if (_selectedDemoDate == null) {
      return;
    }
    _selectedDemoDate = null;
    await (await SharedPreferences.getInstance()).remove(_preferenceKey);
    _notifyDateChanged();
  }

  bool isWithinDemoSchoolYear(DateTime date) {
    final normalized = _dateOnly(date);
    return !normalized.isBefore(demoSchoolYearStart) &&
        !normalized.isAfter(demoSchoolYearEnd);
  }

  void _notifyDateChanged() {
    _revision++;
    notifyListeners();
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @visibleForTesting
  void resetForTest() {
    _demoMode = false;
    _selectedDemoDate = null;
    _revision = 0;
  }
}

final AppClock appClock = AppClock();
