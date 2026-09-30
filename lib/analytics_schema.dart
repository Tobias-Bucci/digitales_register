/// Closed schemas: reject unknown names, keys and values before reaching Firebase.
// A namespace is intentional: one immutable schema shared by service/tests/docs.
// ignore: avoid_classes_with_only_static_members
class AnalyticsSchema {
  static const features = {
    'dashboard',
    'login',
    'grades',
    'timetable',
    'homework',
    'absences',
    'notifications',
    'settings',
    'calendar_sync',
    'privacy',
    'demo',
    'messages',
    'register',
    'authentication',
    'subject_overview',
    'grade_calculator',
    'exam_calendar',
    'unknown',
    'analytics_test'
  };
  static const sources = {
    'navigation',
    'dashboard',
    'notification',
    'deep_link',
    'pull_to_refresh',
    'button',
    'automatic',
    'retry',
    'unknown'
  };
  static const results = {
    'success',
    'partial',
    'failed',
    'cancelled',
    'unknown'
  };
  static const durations = {
    'under_250ms',
    '250_500ms',
    '500ms_1s',
    '1_2s',
    '2_5s',
    'over_5s',
    'unknown'
  };
  static const dataSources = {'remote', 'cache', 'local', 'mixed', 'unknown'};
  static const actions = {
    'refresh',
    'open_statistics',
    'change_view',
    'change_day',
    'open',
    'open_privacy',
    'mark_read',
    'add',
    'import',
    'toggle_done',
    'delete',
    'edit',
    'opened_cached_data',
    'refresh_failed_offline',
    'unknown'
  };
  static const events = <String, Map<String, Set<Object>>>{
    'login_attempt': {
      'login_provider': {'school_api', 'demo', 'unknown'}
    },
    'login_result': {
      'login_provider': {'school_api', 'demo', 'unknown'},
      'result': {
        'success',
        'credentials_rejected',
        'network_error',
        'server_error',
        'parsing_error',
        'cancelled',
        'unknown'
      }
    },
    'logout': {
      'reason': {'user_action', 'session_expired', 'account_switch', 'unknown'}
    },
    'account_switch': {},
    'feature_opened': {'feature': features, 'source': sources},
    'feature_action': {'feature': features, 'action': actions},
    'refresh_requested': {'feature': features, 'source': sources},
    'refresh_result': {
      'feature': features,
      'result': results,
      'data_source': dataSources,
      'duration_bucket': durations
    },
    'sync_started': {
      'sync_type': {'calendar', 'register', 'background', 'unknown'}
    },
    'sync_completed': {
      'sync_type': {'calendar', 'register', 'background', 'unknown'},
      'result': results,
      'duration_bucket': durations
    },
    'semester_changed': {
      'semester': {'1', '2', 'year', 'unknown'}
    },
    'tab_changed': {
      'feature': features,
      'tab_id': {
        'overview',
        'statistics',
        'history',
        'forecast',
        'chart',
        'all',
        'unknown'
      }
    },
    'filter_changed': {
      'feature': features,
      'filter_id': {
        'all',
        'current',
        'open',
        'completed',
        'type_sorted',
        'date_sorted',
        'future',
        'past',
        'unknown'
      }
    },
    'sort_changed': {
      'feature': features,
      'sort_id': {'type_sorted', 'date_sorted', 'unknown'}
    },
    'notification_opened': {
      'notification_type': {
        'general',
        'grade',
        'timetable',
        'absence',
        'homework',
        'sync',
        'unknown'
      }
    },
    'notification_settings_changed': {
      'enabled': {0, 1}
    },
    'theme_changed': {
      'theme': {'light', 'dark', 'system'}
    },
    'language_changed': {
      'language': {'de', 'it', 'en', 'ld', 'other'}
    },
    'demo_mode_changed': {
      'enabled': {0, 1}
    },
    'cache_result': {
      'feature': features,
      'result': {'hit', 'miss', 'disabled', 'unknown'}
    },
    'data_source_used': {'feature': features, 'data_source': dataSources},
    'calendar_sync_changed': {
      'enabled': {0, 1}
    },
    'calendar_sync_result': {'result': results, 'duration_bucket': durations},
    'privacy_settings_changed': {
      'action': {'saved'}
    },
    'onboarding_step': {
      'step_id': {'welcome', 'navigation', 'grades', 'calendar', 'complete'},
      'action': {'shown', 'completed', 'skipped'}
    },
    'error_presented': {
      'feature': features,
      'error_category': {
        'network',
        'server',
        'authentication',
        'parsing',
        'offline',
        'permission',
        'storage',
        'unknown'
      }
    },
    'permission_result': {
      'permission_type': {'calendar', 'notifications'},
      'result': {
        'granted',
        'denied',
        'permanently_denied',
        'restricted',
        'unknown'
      }
    },
    'external_action': {
      'action_type': {
        'open_privacy_policy',
        'open_support',
        'share',
        'export',
        'unknown'
      }
    },
    'offline_usage': {'feature': features, 'action': actions},
  };
  static const properties = <String, Set<String>>{
    'notifications_enabled': {'true', 'false'},
    'school_api_type': {'digital_register_api', 'demo', 'unknown'},
    'demo_mode': {'true', 'false'},
    'app_language': {'de', 'it', 'en', 'ld', 'other'},
    'theme': {'light', 'dark', 'system'},
    'build_flavor': {'production', 'staging', 'development', 'unknown'},
    'release_channel': {
      'production',
      'closed_beta',
      'internal',
      'debug',
      'testflight',
      'unknown'
    },
  };
  static const propertyNames = {
    'notifications_enabled',
    'school_id',
    'academic_year',
    'school_api_type',
    'demo_mode',
    'app_language',
    'theme',
    'build_flavor',
    'release_channel'
  };
  static bool year(Object? value) =>
      value is String &&
      RegExp(r'^(?:20|21)[0-9]{2}_(?:20|21)[0-9]{2}$').hasMatch(value) &&
      int.parse(value.substring(5)) == int.parse(value.substring(0, 4)) + 1;
  static bool validProperty(String key, String? value) =>
      propertyNames.contains(key) &&
      (value == null ||
          (key == 'school_id'
              ? RegExp(r'^school_[0-9]{4}$').hasMatch(value)
              : key == 'academic_year'
                  ? year(value)
                  : properties[key]?.contains(value) == true));
  static bool valid(String name, Map<String, Object> parameters) {
    if (name == 'app_update_observed') {
      return parameters.length == 2 &&
          parameters.keys.every(
              (k) => {'previous_version', 'current_version'}.contains(k)) &&
          parameters.values.every((v) =>
              v is String && RegExp(r'^\d+\.\d+\.\d+(?:\+\d+)?$').hasMatch(v));
    }
    final schema = events[name];
    return schema != null &&
        parameters.length == schema.length &&
        parameters.entries
            .every((entry) => schema[entry.key]?.contains(entry.value) == true);
  }

  static String duration(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms < 250) return 'under_250ms';
    if (ms < 500) return '250_500ms';
    if (ms < 1000) return '500ms_1s';
    if (ms < 2000) return '1_2s';
    if (ms < 5000) return '2_5s';
    return 'over_5s';
  }

  static String gradeCount(int n) => n == 0
      ? '0'
      : n <= 5
          ? '1_5'
          : n <= 10
              ? '6_10'
              : n <= 20
                  ? '11_20'
                  : n <= 40
                      ? '21_40'
                      : '41_plus';
  static String subjectCount(int n) => n == 0
      ? '0'
      : n <= 5
          ? '1_5'
          : n <= 10
              ? '6_10'
              : '11_plus';
}
