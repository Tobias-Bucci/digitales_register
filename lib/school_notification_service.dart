import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/desktop.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/runtime_trace.dart';
import 'package:dr/school_api_endpoints.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:mutex/mutex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

const schoolNotificationTask = 'it.bucci.digitalesregister.schoolRefresh';
final schoolNotifications = SchoolNotificationService();

/// Optional native functionality must never break school-data navigation/login.
Future<void> schoolNotificationOperation(
    Future<void> Function() operation) async {
  try {
    await operation();
  } catch (error) {
    runtimeTrace('SchoolNotifications', 'operation-failed',
        detail: 'type=${error.runtimeType}');
    schoolNotifications.backgroundAvailable = false;
  }
}

@pragma('vm:entry-point')
void schoolNotificationDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final service = SchoolNotificationService();
    try {
      await service.initialize(background: true);
      await service.backgroundSync();
      return true;
    } catch (_) {
      // Android retries with backoff. iOS decides when to grant another run.
      // Never log credentials, payloads, server URLs or school data.
      return false;
    } finally {
      try {
        await service.close();
      } catch (_) {/* Next run can retry. */}
      service.dispose();
    }
  });
}

class SchoolNotificationService extends ChangeNotifier
    with WidgetsBindingObserver {
  SchoolNotificationService(
      {FlutterLocalNotificationsPlugin? native,
      FlutterSecureStorage? storage,
      Future<Database> Function()? database,
      Future<bool> Function()? permission,
      Future<void> Function()? permissionRequest,
      Future<bool> Function()? canRequestPermission,
      Dio Function(BaseOptions)? httpClient,
      Future<Directory> Function()? historyDirectory,
      this.backgroundBudget = const Duration(seconds: 20)})
      : _native = native ?? FlutterLocalNotificationsPlugin(),
        _providedStorage = storage,
        _permission = permission,
        _permissionRequest = permissionRequest,
        _canRequestPermission = canRequestPermission,
        _httpClient = httpClient ?? ((options) => Dio(options)),
        _databaseFactory = database,
        _historyDirectory = historyDirectory ?? getApplicationSupportDirectory;
  static final _processMutex = Mutex();
  static final _scheduleMutex = Mutex();
  static final _permissionMutex = Mutex();
  final FlutterLocalNotificationsPlugin _native;
  final FlutterSecureStorage? _providedStorage;
  final Future<bool> Function()? _permission;
  final Future<void> Function()? _permissionRequest;
  final Future<bool> Function()? _canRequestPermission;
  final Dio Function(BaseOptions) _httpClient;
  final Future<Database> Function()? _databaseFactory;
  final Future<Directory> Function() _historyDirectory;
  final Duration backgroundBudget;
  late final _storage = _providedStorage ??
      (mobileBackgroundSupported
          ? const FlutterSecureStorage(
              iOptions: IOSOptions(
                  accessibility:
                      KeychainAccessibility.first_unlock_this_device))
          : getFlutterSecureStorage());
  Future<Database>? _database;
  LazyBox<String>? _history;
  bool _initialized = false;
  bool _foreground = false;
  Future<void>? _initializing;
  Future<void>? _activation;
  Future<void>? _consentMigration;
  Future<void>? _backgroundWork;
  int _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;
  Timer? _timer;
  bool granted = false;
  bool permissionRequested = false;
  String? activeAccount;
  bool backgroundAvailable = true;
  SchoolNotificationPreferences preferences = SchoolNotificationPreferences();
  Map<String, dynamic> diagnostics = {};
  Map<String, dynamic> platformStatus = {};
  String? activeAccountLabel;
  List<String> enrolledAccountLabels = [];
  Map<String, bool> enrolledAccountStates = {};
  String? backgroundReason;
  SchoolNotificationDestination? pendingDestination;
  bool _preserveDestinationOnce = false;
  void preserveDestinationForNextAccountSwitch() =>
      _preserveDestinationOnce = true;
  Future<void> Function()? onTap;
  Future<void> Function()? refresh;

  bool get supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;
  bool get mobileBackgroundSupported => Platform.isAndroid || Platform.isIOS;
  String accountKey(String server, String user) {
    final uri = Uri.parse(server.replaceAll(RegExp(r'/+$'), ''));
    return notificationDigest([
      uri
          .replace(
              scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
          .toString(),
      user,
    ]);
  }

  SchoolNotificationEngine get _engine => SchoolNotificationEngine(
        read: (key) => _history!.get(key),
        write: (key, value) async {
          await _history!.put(key, value);
          await _history!.flush();
        },
      );

  /// SQLite is used only as an OS-managed transaction mutex. It contains no
  /// school data. Unlike Dart mutexes/file locks it serializes separate Flutter
  /// engines too, and a killed worker automatically releases its transaction.
  Future<T> _locked<T>(Future<T> Function() operation,
      {String label = 'storage', bool history = true}) {
    final waiting = Stopwatch()..start();
    return _processMutex.protect(() async {
      Future<T> run() async {
        final held = Stopwatch()..start();
        runtimeTrace('SchoolNotifications', 'lock-acquired',
            durationMs: waiting.elapsedMilliseconds,
            detail: 'operation=$label');
        try {
          return await (history ? _withHistory(operation) : operation());
        } finally {
          runtimeTrace('SchoolNotifications', 'lock-released',
              durationMs: held.elapsedMilliseconds, detail: 'operation=$label');
        }
      }

      if (!mobileBackgroundSupported) return run();
      while (true) {
        var entered = false;
        try {
          Database db;
          try {
            db = await (_database ??= (_databaseFactory ?? _openDatabase)());
          } catch (_) {
            _database = null;
            rethrow;
          }
          return await db.transaction((txn) async {
            await txn.rawUpdate('UPDATE mutex SET value = value + 1');
            entered = true;
            return run();
          }, exclusive: true);
        } on DatabaseException catch (error) {
          final code = error.getResultCode();
          final busy = code != null && ((code & 255) == 5 || (code & 255) == 6);
          if (entered ||
              !busy ||
              waiting.elapsed > const Duration(seconds: 20)) {
            rethrow;
          }
          // Yield in Dart, not SQLite's shared native worker thread, so the
          // other engine can commit and release its lock.
          runtimeTrace('SchoolNotifications', 'lock-busy',
              durationMs: waiting.elapsedMilliseconds,
              detail: 'operation=$label');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  }

  Future<T> _withHistory<T>(Future<T> Function() operation) async {
    final directory = await _historyDirectory();
    const keyName = 'school-notification-history-key-v1';
    final storedKey = await _storage.read(key: keyName);
    final key =
        storedKey == null ? Hive.generateSecureKey() : base64Decode(storedKey);
    if (storedKey == null) {
      await _storage.write(key: keyName, value: base64Encode(key));
    }
    // Reopen under the transaction so another engine's writes are visible.
    _history = await Hive.openLazyBox<String>('school_notification_history_v1',
        path: directory.path, encryptionCipher: HiveAesCipher(key));
    try {
      return await operation();
    } finally {
      await _history!.close();
      _history = null;
    }
  }

  Future<Database> _openDatabase() async => openDatabase(
        '${await getDatabasesPath()}/school_notification_mutex.db',
        singleInstance: false,
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA busy_timeout = 0'),
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE mutex (value INTEGER NOT NULL)');
          await db.insert('mutex', {'value': 0});
        },
      );

  Future<void> initialize({bool background = false}) {
    if (!supported) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;
    if (_initialized) return Future.value();
    final future = _initialize(background: background).whenComplete(() {
      _initializing = null;
    });
    _initializing = future;
    return future;
  }

  Future<void> _initialize({required bool background}) async {
    _foreground = !background;
    // Publish the foreground barrier before native/plugin initialization.
    if (!background) await _markForeground(true);
    final timer = Stopwatch()..start();
    runtimeTrace('SchoolNotifications', 'initialize-start',
        detail: 'background=$background');
    try {
      await _native.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_school_notification'),
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false),
          macOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false),
          linux:
              LinuxInitializationSettings(defaultActionName: 'Open Register'),
          windows: WindowsInitializationSettings(
              appName: 'Register',
              appUserModelId: 'it.bucci.digitalesregister',
              guid: '47d730b5-c496-4a56-a1cd-80f08902cdd4'),
        ),
        onDidReceiveNotificationResponse: (response) {
          pendingDestination =
              SchoolNotificationDestination.decode(response.payload);
          unawaited(schoolNotificationOperation(() async {
            await onTap?.call();
          }));
        },
      );
      _initialized = true;
      if (!background) {
        await _clearSchoolAlerts();
        WidgetsBinding.instance.addObserver(this);
        _startForegroundChecks();
        final launch = Platform.isLinux
            ? null
            : await _native.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          pendingDestination = SchoolNotificationDestination.decode(
              launch?.notificationResponse?.payload);
        }
        try {
          if (mobileBackgroundSupported) {
            await Workmanager().initialize(schoolNotificationDispatcher);
          }
        } catch (_) {
          backgroundAvailable = false;
        }
      }
      await reload();
      runtimeTrace('SchoolNotifications', 'initialize-end',
          durationMs: timer.elapsedMilliseconds);
    } catch (_) {
      _initialized = false;
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
      rethrow;
    }
  }

  void _startForegroundChecks() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) {
      unawaited(schoolNotificationOperation(() async {
        await _markForeground(true);
        if (preferences.enabled &&
            (preferences.grades || preferences.messages)) {
          await refresh?.call();
        }
      }));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(schoolNotificationOperation(enterForeground));
      _startForegroundChecks();
    } else {
      _timer?.cancel();
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        _foreground = false;
        unawaited(schoolNotificationOperation(() => _markForeground(false)));
      }
    }
  }

  Future<void> enterForeground() async {
    _foreground = true;
    await _markForeground(true);
    await _locked(_clearSchoolAlerts, history: false, label: 'clear-on-resume');
  }

  Future<void> _markForeground(bool active) => _locked(() async {
        if (active) {
          await _storage.write(
              key: 'school-notification-foreground-until',
              value: DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 6))
                  .toIso8601String());
        } else {
          await _storage.delete(key: 'school-notification-foreground-until');
        }
      }, label: 'foreground-heartbeat', history: false);

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _hasPermission() async {
    if (_permission != null) return _permission();
    if (Platform.isMacOS) {
      return (await _native
                  .resolvePlatformSpecificImplementation<
                      MacOSFlutterLocalNotificationsPlugin>()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    if (Platform.isLinux || Platform.isWindows) {
      // These desktop daemons enforce system policy and expose no permission
      // request API. Require explicit in-app consent before submitting alerts.
      return await _storage.read(key: 'school-notification-desktop-consent') ==
          'true';
    }
    if (Platform.isAndroid) {
      return await _native
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled() ??
          false;
    }
    return (await _native
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.checkPermissions())
            ?.isEnabled ??
        false;
  }

  /// Workers must release native connections before their Flutter engine exits.
  Future<void> close() => _processMutex.protect(() async {
        final database = _database;
        _database = null;
        if (database != null) await (await database).close();
      });

  Future<SchoolNotificationPreferences> _readPreferences(
      {String? account, bool legacyEligible = false}) async {
    account ??= await _storage.read(key: 'school-notification-active');
    var raw = account == null
        ? null
        : await _storage.read(
            key: 'school-notification-preferences-v1-$account');
    if (raw == null && account != null) {
      final legacy =
          await _storage.read(key: 'school-notification-preferences-v1');
      if (legacy != null) {
        final data = jsonDecode(legacy) as Map;
        final disabled = data['enabled'] == false ||
            (data['grades'] == false && data['messages'] == false);
        if (disabled ||
            legacyEligible ||
            (await _enrolledAccounts()).containsKey(account)) {
          raw = legacy;
        }
      }
    }
    final data = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map;
    final SchoolNotificationConsent consent;
    if (data.containsKey('decision')) {
      consent = switch (data['decision']) {
        'accepted' => SchoolNotificationConsent.accepted,
        'declined' => SchoolNotificationConsent.declined,
        _ => SchoolNotificationConsent.unknown,
      };
    } else if (raw != null &&
        (data.containsKey('enabled') ||
            data.containsKey('grades') ||
            data.containsKey('messages'))) {
      consent = data['enabled'] == false ||
              (data['grades'] == false && data['messages'] == false)
          ? SchoolNotificationConsent.declined
          : SchoolNotificationConsent.accepted;
    } else {
      consent = SchoolNotificationConsent.unknown;
    }
    return SchoolNotificationPreferences(
        consent: consent,
        enabled: consent == SchoolNotificationConsent.accepted &&
            data['enabled'] != false,
        showEventCount: data['showEventCount'] == true,
        grades: data['grades'] != false,
        messages: data['messages'] != false);
  }

  Future<void> _loadPreferences({String? account}) async {
    preferences = await _readPreferences(account: account);
  }

  /// Snapshot only accounts already saved before startup sign-in can add a new
  /// one. This preserves old global choices even after an earlier logout,
  /// without treating OS permission or a later new account as app consent.
  Future<void> migrateLegacyDecisions(Iterable<(String, String)> accounts) {
    final ids = accounts.map((a) => accountKey(a.$1, a.$2)).toSet();
    final future = _locked(() async {
      const marker = 'school-notification-consent-migrated-v1';
      if (await _storage.read(key: marker) == 'true') return;
      for (final account in ids) {
        final settings =
            await _readPreferences(account: account, legacyEligible: true);
        if (settings.consent != SchoolNotificationConsent.unknown) {
          await _storage.write(
              key: 'school-notification-preferences-v1-$account',
              value: jsonEncode(settings.toJson()));
        }
      }
      await _storage.write(key: marker, value: 'true');
    }, history: false, label: 'opt-in-migration');
    _consentMigration = future;
    return future;
  }

  Future<void> _clearSchoolAlerts() async {
    // Desktop APIs may not enumerate payloads. Remember only our submitted IDs
    // so cleanup remains scoped even there; never cancel the whole app inbox.
    final rawIds = await _storage.read(key: 'school-notification-alert-ids-v1');
    if (rawIds != null) {
      for (final id in (jsonDecode(rawIds) as List).cast<int>()) {
        await _native.cancel(id: id);
      }
      await _storage.delete(key: 'school-notification-alert-ids-v1');
    }
    // Filter by our own channels/payloads. General app announcements are retained.
    if (Platform.isLinux) return; // The plugin cannot enumerate Linux alerts.
    for (final alert in await _native.getActiveNotifications()) {
      if (alert.id != null &&
          (alert.channelId == 'school_grade' ||
              alert.channelId == 'school_message' ||
              SchoolNotificationDestination.decode(alert.payload) != null)) {
        await _native.cancel(id: alert.id!, tag: alert.tag);
      }
    }
  }

  Future<bool> _presentationAllowed() async {
    if (_foreground) return false;
    final until = DateTime.tryParse(
        await _storage.read(key: 'school-notification-foreground-until') ?? '');
    if (until != null && until.isAfter(DateTime.now().toUtc())) return false;
    if (Platform.isAndroid || Platform.isIOS) {
      // Registered in both UI and headless engines. Missing native integration
      // fails closed instead of producing a late popup during startup.
      if (await const MethodChannel('dr/school_notifications')
              .invokeMethod<bool>('isForeground') !=
          false) {
        return false;
      }
    }
    return await _hasPermission();
  }

  Future<void> _diagnose(String account, Map<String, dynamic> updates) async {
    final key = 'school-notification-diagnostics-$account';
    final raw = await _history!.get(key);
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    data.addAll(updates);
    await _history!.put(key, jsonEncode(data));
    await _history!.flush();
    diagnostics = data;
  }

  Future<void> openSystemSettings() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await const MethodChannel('dr/school_notifications')
          .invokeMethod<void>('openSettings');
    }
  }

  Future<void> reload() async {
    if (!supported || !_initialized) return;
    await _locked(() async {
      await _loadPreferences();
      granted = await _hasPermission();
      permissionRequested = await _storage.read(
              key: 'school-notification-permission-requested-v1') ==
          'true';
      final previous =
          await _storage.read(key: 'school-notification-permission');
      if (granted && previous != 'true') {
        final account = await _storage.read(key: 'school-notification-active');
        for (final account in {
          ...(await _enrolledAccounts()).keys,
          if (account != null) account
        }) {
          for (final category in SchoolNotificationCategory.values) {
            await _engine.baselineNext(account, category.name);
          }
        }
      }
      await _storage.write(
          key: 'school-notification-permission', value: '$granted');
      if (granted && previous != 'true') await _prepareBackgroundCredentials();
      final account = await _storage.read(key: 'school-notification-active');
      activeAccount = account;
      final raw = account == null
          ? null
          : await _history!.get('school-notification-diagnostics-$account');
      diagnostics = raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
      final loginRaw = await _storage.read(key: 'login');
      final login =
          loginRaw == null ? <String, dynamic>{} : jsonDecode(loginRaw) as Map;
      final saved = [
        login,
        ...(login['otherAccounts'] as List? ?? []).whereType<Map>()
      ];
      final enrolled = await _enrolledAccounts();
      enrolledAccountLabels = [];
      enrolledAccountStates = {};
      for (final credentials in saved) {
        if (credentials['user'] is! String || credentials['url'] is! String) {
          continue;
        }
        final id = accountKey(
            credentials['url'] as String, credentials['user'] as String);
        final label =
            '${credentials['user']} · ${Uri.parse(credentials['url'] as String).authority}';
        if (id == account) activeAccountLabel = label;
        if (enrolled.containsKey(id)) {
          enrolledAccountLabels.add(label);
          final settings = await _readPreferences(account: id);
          enrolledAccountStates[label] =
              settings.enabled && (settings.grades || settings.messages);
        }
      }
      backgroundReason = !preferences.enabled
          ? 'disabled'
          : !granted
              ? 'permission'
              : account == null
                  ? 'noAccount'
                  : await _storage.read(
                              key: 'school-notification-background') !=
                          'true'
                      ? 'credentials'
                      : null;
    });
    if (Platform.isAndroid || Platform.isIOS) {
      platformStatus = await const MethodChannel('dr/school_notifications')
              .invokeMapMethod<String, dynamic>('diagnostics') ??
          {};
    }
    notifyListeners();
  }

  Future<void> requestPermission() =>
      _permissionMutex.protect(_requestPermission);

  Future<void> _requestPermission() async {
    if (!supported) return;
    await initialize();
    final account = await _storage.read(key: 'school-notification-active');
    if (account == null ||
        !(await _readPreferences(account: account)).enabled) {
      return;
    }
    final generation = _sessionGeneration;
    final alreadyAsked = await _storage.read(
            key: 'school-notification-permission-requested-v1') ==
        'true';
    var canAsk = !alreadyAsked && !await _hasPermission();
    if (canAsk && _canRequestPermission != null) {
      canAsk = await _canRequestPermission();
    } else if (canAsk && (Platform.isAndroid || Platform.isIOS)) {
      canAsk = await const MethodChannel('dr/school_notifications')
              .invokeMethod<bool>('canRequestNotificationPermission') ==
          true;
    }
    if (generation != _sessionGeneration ||
        await _storage.read(key: 'school-notification-active') != account) {
      return;
    }
    if (canAsk) {
      // Persist before entering native UI: a crash/denial cannot repeat the prompt.
      await _storage.write(
          key: 'school-notification-permission-requested-v1', value: 'true');
      permissionRequested = true;
      if (_permissionRequest != null) {
        await _permissionRequest();
      } else if (Platform.isAndroid) {
        await _native
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _native
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (Platform.isMacOS) {
        await _native
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else {
        await _storage.write(
            key: 'school-notification-desktop-consent', value: 'true');
      }
    } else if (!await _hasPermission()) {
      // A known OS denial is handled only through the voluntary settings link.
      await _storage.write(
          key: 'school-notification-permission-requested-v1', value: 'true');
    }
    await reload();
    if (generation != _sessionGeneration) return;
    if (_foreground) await _markForeground(true);
    await _locked(_prepareBackgroundCredentials,
        history: false, label: 'opt-in-keychain');
    await schedule();
    await refresh?.call();
  }

  Future<void> setCategory(
      SchoolNotificationCategory category, bool value) async {
    if (!supported) return;
    await _locked(() async {
      await _loadPreferences();
      if (category == SchoolNotificationCategory.grade) {
        preferences.grades = value;
      } else {
        preferences.messages = value;
      }
      final account = await _storage.read(key: 'school-notification-active');
      if (account != null) await _engine.baselineNext(account, category.name);
      await _storage.write(
          key: account == null
              ? 'school-notification-preferences-v1'
              : 'school-notification-preferences-v1-$account',
          value: jsonEncode(preferences.toJson()));
      await _clearSchoolAlerts();
    });
    await reload();
    await schedule();
    await refresh?.call();
  }

  Future<void> setEnabled(bool value) async {
    await _locked(() async {
      await _loadPreferences();
      preferences.enabled = value;
      preferences.consent = value
          ? SchoolNotificationConsent.accepted
          : SchoolNotificationConsent.declined;
      final account = await _storage.read(key: 'school-notification-active');
      if (account != null) {
        for (final category in SchoolNotificationCategory.values) {
          await _engine.baselineNext(account, category.name);
        }
      }
      await _storage.write(
          key: account == null
              ? 'school-notification-preferences-v1'
              : 'school-notification-preferences-v1-$account',
          value: jsonEncode(preferences.toJson()));
      await _clearSchoolAlerts();
    });
    await reload();
    if (value) {
      await requestPermission();
    } else {
      await schedule();
      await refresh?.call();
    }
  }

  Future<SchoolNotificationOptInOffer?> pendingOptIn() async {
    await _activation;
    await _initializing;
    if (!supported || !_initialized) return null;
    return _locked(() async {
      final account = await _storage.read(key: 'school-notification-active');
      if (account == null ||
          (await _readPreferences(account: account)).consent !=
              SchoolNotificationConsent.unknown) {
        return null;
      }
      return SchoolNotificationOptInOffer(
          account, _sessionGeneration, activeAccountLabel ?? '');
    }, history: false, label: 'opt-in-read');
  }

  Future<bool> decideOptIn(SchoolNotificationOptInOffer offer,
      {required bool accept, bool grades = true, bool messages = true}) async {
    final saved = await _locked(() async {
      if (offer.generation != _sessionGeneration ||
          await _storage.read(key: 'school-notification-active') !=
              offer.account) {
        return false;
      }
      final current = await _readPreferences(account: offer.account);
      if (current.consent != SchoolNotificationConsent.unknown) return false;
      current
        ..enabled = accept && (grades || messages)
        ..consent = accept
            ? SchoolNotificationConsent.accepted
            : SchoolNotificationConsent.declined
        ..grades = grades
        ..messages = messages;
      for (final category in SchoolNotificationCategory.values) {
        await _engine.baselineNext(offer.account, category.name);
      }
      await _storage.write(
          key: 'school-notification-preferences-v1-${offer.account}',
          value: jsonEncode(current.toJson()));
      return true;
    }, label: 'opt-in-save');
    if (!saved) return false;
    await reload();
    if (offer.generation != _sessionGeneration) return true;
    if (accept && (grades || messages)) {
      try {
        await requestPermission();
      } catch (_) {
        // The explicit app decision is durable even if optional native UI fails.
        backgroundAvailable = false;
        notifyListeners();
      }
    } else {
      await schedule();
      await refresh?.call();
    }
    return true;
  }

  Future<void> setShowEventCount(bool value) async {
    await _locked(() async {
      await _loadPreferences();
      preferences.showEventCount = value;
      final account = await _storage.read(key: 'school-notification-active');
      await _storage.write(
          key: account == null
              ? 'school-notification-preferences-v1'
              : 'school-notification-preferences-v1-$account',
          value: jsonEncode(preferences.toJson()));
      await _clearSchoolAlerts();
    });
    await reload();
  }

  Future<void> activate(String server, String user,
      {required bool backgroundAllowed}) {
    final generation = ++_sessionGeneration;
    final future = _activate(server, user,
        backgroundAllowed: backgroundAllowed, generation: generation);
    _activation = future;
    return future;
  }

  Future<void> _activate(String server, String user,
      {required bool backgroundAllowed, required int generation}) async {
    if (!supported) return;
    try {
      await _consentMigration;
    } catch (_) {/* Unknown consent stays disabled. */}
    await initialize();
    await _locked(() async {
      if (generation != _sessionGeneration) return;
      final account = accountKey(server, user);
      final previous = await _storage.read(key: 'school-notification-active');
      final enrolled = await _enrolledAccounts();
      // Materialize unknown/legacy decisions before enrolling a new account;
      // old positive global settings must not opt new accounts in implicitly.
      final settings = await _readPreferences(account: account);
      await _storage.write(
          key: 'school-notification-preferences-v1-$account',
          value: jsonEncode(settings.toJson()));
      if (previous != account) await _clearSchoolAlerts();
      activeAccountLabel = user;
      await _storage.write(key: 'school-notification-active', value: account);
      // A session token also rejects late responses after A -> B -> A or logout
      // followed by another login to the same account, across Flutter engines.
      await _storage.write(
          key: 'school-notification-session',
          value: notificationDigest(Hive.generateSecureKey()));
      await _storage.write(
          key: 'school-notification-background', value: '$backgroundAllowed');
      enrolled[account] = true;
      await _storage.write(
          key: 'school-notification-accounts-v1', value: jsonEncode(enrolled));
      await _prepareBackgroundCredentials();
    }, label: 'activate', history: false);
    if (generation == _sessionGeneration) {
      await reload();
      await schedule();
    }
  }

  /// Caller holds the account lock. Upgrade only after notification consent,
  /// without introducing a second credential record.
  Future<void> _prepareBackgroundCredentials() async {
    if (!Platform.isIOS ||
        !granted ||
        !(await _readPreferences()).enabled ||
        await _storage.read(key: 'school-notification-background') != 'true') {
      return;
    }
    final login = await _storage.read(key: 'login');
    if (login != null) await _storage.write(key: 'login', value: login);
  }

  Future<Map<String, dynamic>> _enrolledAccounts() async {
    final raw = await _storage.read(key: 'school-notification-accounts-v1');
    if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
    // Upgrade the previous single-account installation without resetting its
    // opt-in/history. An explicit empty registry (deletion) is never migrated.
    final active = await _storage.read(key: 'school-notification-active');
    return {if (active != null) active: true};
  }

  Future<void> forgetAccount(String server, String user) async {
    // Revocation/history deletion must not depend on an available OS notifier.
    await _locked(() async {
      final account = accountKey(server, user);
      final enrolled = (await _enrolledAccounts())..remove(account);
      await _storage.write(
          key: 'school-notification-accounts-v1', value: jsonEncode(enrolled));
      await _storage.delete(key: 'school-notification-preferences-v1-$account');
      await _storage.delete(key: 'school-notification-last-sync-$account');
      await _storage.delete(key: 'school-notification-lease-$account');
      await _history!.delete(_engine.key(account));
      await _history!.delete('school-notification-diagnostics-$account');
      await _history!.flush();
      if (await _storage.read(key: 'school-notification-active') == account) {
        ++_sessionGeneration;
        await _storage.delete(key: 'school-notification-active');
        await _storage.delete(key: 'school-notification-session');
        activeAccountLabel = null;
        activeAccount = null;
        diagnostics = {};
      }
      if (pendingDestination?.account == account) pendingDestination = null;
      await _clearSchoolAlerts();
    }, label: 'forget-account');
    await reload();
    await schedule();
  }

  Future<void> deactivate({bool switchingAccount = false}) async {
    ++_sessionGeneration;
    if (!supported) return;
    await _locked(() async {
      if (switchingAccount) {
        final enrolled = await _enrolledAccounts();
        await _storage.write(
            key: 'school-notification-accounts-v1',
            value: jsonEncode(enrolled));
      }
      await _storage.delete(key: 'school-notification-active');
      await _storage.delete(key: 'school-notification-session');
      if (!switchingAccount) {
        await _storage.delete(key: 'school-notification-accounts-v1');
      }
      await _clearSchoolAlerts();
      activeAccountLabel = null;
      activeAccount = null;
      diagnostics = {};
      if (!switchingAccount || !_preserveDestinationOnce) {
        pendingDestination = null;
      }
      _preserveDestinationOnce = false;
    }, label: 'deactivate', history: false);
    if (mobileBackgroundSupported && _initialized) {
      try {
        await _scheduleMutex.protect(
            () => Workmanager().cancelByUniqueName(schoolNotificationTask));
      } catch (error) {
        // The account is already revoked. An unavailable scheduler must not
        // undo that barrier or prevent logout; later workers recheck storage.
        backgroundAvailable = false;
        runtimeTrace('SchoolNotifications', 'cancel-schedule-failed',
            detail: 'type=${error.runtimeType}');
      }
    }
  }

  Future<void> schedule() => _scheduleMutex.protect(_schedule);

  Future<void> _schedule() async {
    if (!supported || !_initialized) return;
    if (!mobileBackgroundSupported) return;
    try {
      var anyEnabled = false;
      for (final account in (await _enrolledAccounts()).keys) {
        final preferences = await _readPreferences(account: account);
        anyEnabled |=
            preferences.enabled && (preferences.grades || preferences.messages);
      }
      if (!granted ||
          !anyEnabled ||
          await _storage.read(key: 'school-notification-active') == null ||
          await _storage.read(key: 'school-notification-background') !=
              'true') {
        await Workmanager().cancelByUniqueName(schoolNotificationTask);
      } else {
        if (Platform.isIOS &&
            await const MethodChannel('dr/school_notifications')
                    .invokeMethod<bool>('backgroundRefreshAvailable') !=
                true) {
          backgroundAvailable = false;
          notifyListeners();
          return;
        }
        await Workmanager().registerPeriodicTask(
            schoolNotificationTask, schoolNotificationTask,
            frequency: const Duration(minutes: 15),
            initialDelay: const Duration(minutes: 15),
            constraints: Constraints(networkType: NetworkType.connected),
            existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
            backoffPolicy: BackoffPolicy.exponential,
            backoffPolicyDelay: const Duration(minutes: 1));
      }
      backgroundAvailable = true;
      if (Platform.isAndroid || Platform.isIOS) {
        platformStatus = await const MethodChannel('dr/school_notifications')
                .invokeMapMethod<String, dynamic>('diagnostics') ??
            {};
      }
    } catch (_) {
      backgroundAvailable = false;
    }
    notifyListeners();
  }

  Future<void> ingest(String server, String user, List data,
      {bool background = false}) async {
    if (!supported) return;
    final generation = _sessionGeneration;
    await _activation;
    if (!_initialized || generation != _sessionGeneration) return;
    await _locked(() async {
      final account = accountKey(server, user);
      if (generation != _sessionGeneration ||
          await _storage.read(key: 'school-notification-active') != account) {
        return;
      }
      await _ingest(account, data, background: background);
    }, label: 'ingest');
  }

  Future<void> _ingest(String account, List data,
      {required bool background}) async {
    if (data.any((e) =>
        e is Map &&
        (e['type'] == 'grade' || e['type'] == 'message') &&
        SchoolNotificationEvent.parse(e) == null)) {
      throw const FormatException('Incomplete personal notification entry');
    }
    final events = data
        .map((e) => e is Map ? SchoolNotificationEvent.parse(e) : null)
        .whereType<SchoolNotificationEvent>()
        .toList();
    await _loadPreferences(account: account);
    await (await SharedPreferences.getInstance()).reload();
    await appLanguageController.load();
    final l10n =
        await AppLocalizations.load(appLanguageController.language.locale);
    await _engine.synchronize(
        account: account,
        events: events,
        preferences: preferences,
        permitted: await _hasPermission(),
        foreground: !background,
        now: DateTime.now(),
        deliverBatch: (batch) async {
          for (final category in SchoolNotificationCategory.values) {
            final group =
                batch.where((event) => event.category == category).toList();
            if (group.isEmpty) continue;
            final event = group.first;
            // Recheck after persisting the claim; never show without OS permission.
            if (!await _presentationAllowed()) return;
            final kind = event.category.name;
            final id = int.parse(
                notificationDigest([account, kind]).substring(0, 7),
                radix: 16);
            final requestedAt = DateTime.now().toUtc().toIso8601String();
            final rawIds =
                await _storage.read(key: 'school-notification-alert-ids-v1');
            final ids = rawIds == null
                ? <int>{}
                : (jsonDecode(rawIds) as List).cast<int>().toSet();
            ids.add(id);
            await _storage.write(
                key: 'school-notification-alert-ids-v1',
                value: jsonEncode(ids.toList()));
            await _diagnose(
                account, {'lastNotificationRequestedAt': requestedAt});
            await _native.show(
                id: id,
                title: l10n.text(
                    'schoolNotifications.$kind.${group.length == 1 ? 'title' : preferences.showEventCount ? 'pluralTitle' : 'multipleTitle'}',
                    args: {
                      'count': '${group.length}'
                    }),
                body: l10n.text(
                    'schoolNotifications.$kind.${group.length == 1 ? 'body' : 'pluralBody'}'),
                notificationDetails: NotificationDetails(
                    android: AndroidNotificationDetails('school_$kind',
                        l10n.text('schoolNotifications.$kind.title'),
                        visibility: NotificationVisibility.private,
                        groupKey: 'school_$account'),
                    iOS: DarwinNotificationDetails(
                        threadIdentifier: 'school_$account',
                        presentAlert: false,
                        presentBanner: false,
                        presentList: false,
                        presentSound: true),
                    macOS: const DarwinNotificationDetails(
                        presentAlert: false, presentSound: false),
                    linux: LinuxNotificationDetails(
                        defaultActionName: l10n.text('common.open'))),
                payload: SchoolNotificationDestination(account, event.category,
                        group.length == 1 ? event.objectId : null)
                    .encode());
            await _diagnose(account, {
              'lastNotificationAcceptedAt':
                  DateTime.now().toUtc().toIso8601String()
            });
            // If the local UI resumed while show was awaiting its native reply,
            // remove the alert without marking any school event as read.
            if (_foreground) await _native.cancel(id: id);
          }
        });
    final state =
        jsonDecode((await _history!.get(_engine.key(account)))!) as Map;
    await _diagnose(account, {
      if (state['lastDetectedAt'] != null)
        'lastDetectedAt': state['lastDetectedAt'],
      if (background)
        'lastBackgroundSuccessAt': DateTime.now().toUtc().toIso8601String(),
      if (background) 'backgroundResult': 'success',
    });
    await _storage.write(
        key: 'school-notification-last-sync-$account',
        value: DateTime.now().toUtc().toIso8601String());
  }

  Future<void> markViewed(
      String server, String user, List<Map<String, Object?>> items) async {
    if (!supported || !_initialized) return;
    final generation = _sessionGeneration;
    await _locked(() async {
      final account = accountKey(server, user);
      if (generation != _sessionGeneration ||
          await _storage.read(key: 'school-notification-active') != account ||
          !(await _enrolledAccounts()).containsKey(account)) {
        return;
      }
      final identities = items
          .map(SchoolNotificationEvent.parse)
          .whereType<SchoolNotificationEvent>()
          .expand((e) => e.identities)
          .toSet();
      await _engine.markViewed(account, identities);
      for (final identity in identities) {
        final id = int.parse(
            notificationDigest([account, identity]).substring(0, 7),
            radix: 16);
        await _native.cancel(id: id);
      }
      for (final category
          in items.map((e) => e['type']).whereType<String>().toSet()) {
        await _native.cancel(
            id: int.parse(
                notificationDigest([account, category]).substring(0, 7),
                radix: 16));
      }
    });
  }

  /// Resolve only an existing saved account; a payload never supplies a URL,
  /// password or new account. The UI still runs the normal sign-in/lock flow.
  Future<int?> savedAccountIndex(String account,
      {required bool loggedIn, required bool noPasswordSaving}) async {
    final raw = await _storage.read(key: 'login');
    if (raw == null) return null;
    final login = jsonDecode(raw) as Map;
    final saved = [
      if (!loggedIn &&
          noPasswordSaving &&
          login['user'] != null &&
          login['pass'] != null)
        login,
      ...(login['otherAccounts'] as List? ?? []).whereType<Map>(),
    ];
    for (var i = 0; i < saved.length; i++) {
      final candidate = saved[i];
      if (candidate['user'] is String &&
          candidate['url'] is String &&
          accountKey(candidate['url'] as String, candidate['user'] as String) ==
              account) {
        return i;
      }
    }
    return null;
  }

  /// Uses the existing encrypted saved-login record, without copying credentials
  /// into task arguments or keeping cookies on disk. This client never opens UI,
  /// refreshes sessions indefinitely, follows redirects or handles 2FA prompts.
  Future<void> backgroundSync() {
    final pending = _backgroundWork;
    if (pending != null) return pending;
    final future = _backgroundSync().whenComplete(() => _backgroundWork = null);
    _backgroundWork = future;
    return future;
  }

  Future<void> _backgroundSync() async {
    if (!mobileBackgroundSupported) return;
    final accounts = await _locked(() async {
      final enrolled = await _enrolledAccounts();
      final active = await _storage.read(key: 'school-notification-active');
      if (active == null) return <String>[];
      // Least recently attempted first prevents a slow school from starving
      // other accounts when iOS grants only a short execution window.
      final starts = <String, String>{};
      for (final account in enrolled.keys) {
        final raw =
            await _history!.get('school-notification-diagnostics-$account');
        starts[account] = raw == null
            ? ''
            : (jsonDecode(raw) as Map)['lastBackgroundStartedAt'] as String? ??
                '';
      }
      return enrolled.keys.toList()
        ..sort((a, b) => starts[a]!.compareTo(starts[b]!));
    });
    final elapsed = Stopwatch()..start();
    Object? failure;
    StackTrace? failureStack;
    for (final account in accounts) {
      final remaining = backgroundBudget - elapsed.elapsed;
      if (remaining <= Duration.zero) break;
      try {
        await _backgroundSyncAccount(account, remaining);
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<void> _backgroundSyncAccount(
      String targetAccount, Duration budget) async {
    if (!mobileBackgroundSupported) return;
    // Capture the request under a short storage lock. No network operation may
    // run inside that lock: a slow worker must never stall a foreground engine.
    final request = await _locked<_BackgroundNotificationRequest?>(() async {
      if (!await _hasPermission()) return null;
      await _loadPreferences(account: targetAccount);
      if (!preferences.enabled ||
          (!preferences.grades && !preferences.messages)) {
        return null;
      }
      final active = await _storage.read(key: 'school-notification-active');
      final account = targetAccount;
      if (active == null ||
          !(await _enrolledAccounts()).containsKey(account) ||
          await _storage.read(key: 'school-notification-background') !=
              'true') {
        return null;
      }
      final last = DateTime.tryParse(
          await _storage.read(key: 'school-notification-last-sync-$account') ??
              '');
      if (last != null &&
          DateTime.now().toUtc().difference(last) <
              const Duration(minutes: 2)) {
        return null;
      }
      final foregroundUntil = DateTime.tryParse(
          await _storage.read(key: 'school-notification-foreground-until') ??
              '');
      if (foregroundUntil != null &&
          foregroundUntil.isAfter(DateTime.now().toUtc())) {
        return null;
      }
      final raw = await _storage.read(key: 'login');
      if (raw == null) return null;
      final login = jsonDecode(raw) as Map;
      final saved = [
        login,
        ...(login['otherAccounts'] as List? ?? []).whereType<Map>()
      ];
      Map? credentials;
      for (final candidate in saved) {
        if (candidate['url'] is String &&
            candidate['user'] is String &&
            accountKey(
                    candidate['url'] as String, candidate['user'] as String) ==
                account) {
          credentials = candidate;
          break;
        }
      }
      final server = credentials?['url'] as String?;
      final user = credentials?['user'] as String?;
      final password = credentials?['pass'];
      if (server == null ||
          user == null ||
          password is! String ||
          accountKey(server, user) != account ||
          user == 'demo' ||
          user == 'debug') {
        return null;
      }
      final uri = Uri.tryParse(server);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        return null;
      }
      final lease = DateTime.tryParse(
          await _storage.read(key: 'school-notification-lease-$account') ?? '');
      if (lease != null && lease.isAfter(DateTime.now().toUtc())) return null;
      final session = await _storage.read(key: 'school-notification-session');
      final rawDiagnostics =
          await _history!.get('school-notification-diagnostics-$account');
      final previous = rawDiagnostics == null
          ? <String, dynamic>{}
          : jsonDecode(rawDiagnostics) as Map;
      if (previous['backgroundResult'] == 'authenticationRequired' &&
          previous['authenticationSession'] == session) {
        return null;
      }
      final leaseValue = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 45))
          .toIso8601String();
      await _storage.write(
          key: 'school-notification-lease-$account', value: leaseValue);
      await _diagnose(account, {
        'lastBackgroundStartedAt': DateTime.now().toUtc().toIso8601String(),
        'backgroundResult': 'running',
      });
      return _BackgroundNotificationRequest(
          lease: leaseValue,
          active: active,
          account: account,
          session: session,
          rawLogin: raw,
          server: server,
          user: user,
          password: password);
    }, label: 'background-prepare');
    if (request == null) {
      runtimeTrace('SchoolNotifications', 'background-skipped');
      return;
    }
    final networkTimer = Stopwatch()..start();
    runtimeTrace('SchoolNotifications', 'background-network-start');
    final dio = _httpClient(BaseOptions(
        baseUrl: schoolApiBase(request.server),
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        followRedirects: false));
    dio.interceptors.add(CookieManager(CookieJar()));
    final cancellation = CancelToken();
    final deadline =
        Timer(budget, () => cancellation.cancel('Background refresh deadline'));
    try {
      final result = (await dio.post<dynamic>(schoolLoginEndpoint,
              data: {
                'username': request.user,
                'password': request.password,
              },
              cancelToken: cancellation))
          .data;
      final auth = result is String ? jsonDecode(result) : result;
      if (auth is! Map) {
        throw const FormatException('Invalid school authentication response');
      }
      if (auth['loggedIn'] != true && auth['loggedIn'] != 1) {
        await _locked(() async {
          if ((await _enrolledAccounts()).containsKey(request.account)) {
            await _diagnose(request.account, {
              'backgroundResult': 'authenticationRequired',
              'authenticationSession': request.session
            });
          }
        });
        return;
      }
      final response = (await dio.post<dynamic>(
              schoolUnreadNotificationsEndpoint,
              data: <String, Object?>{},
              cancelToken: cancellation))
          .data;
      final data = response is String ? jsonDecode(response) : response;
      if (data is! List) {
        throw const FormatException('Invalid school notification feed');
      }
      runtimeTrace('SchoolNotifications', 'background-response-received',
          durationMs: networkTimer.elapsedMilliseconds);
      // Everything mutable is checked again while holding the commit lock.
      // Another account, foreground refresh, permission change or logout may
      // have superseded this request while it was waiting for the network.
      await _locked(() async {
        final last = DateTime.tryParse(await _storage.read(
                key: 'school-notification-last-sync-${request.account}') ??
            '');
        final foreground = DateTime.tryParse(
            await _storage.read(key: 'school-notification-foreground-until') ??
                '');
        if (await _storage.read(key: 'school-notification-active') !=
                request.active ||
            !(await _enrolledAccounts()).containsKey(request.account) ||
            await _storage.read(key: 'school-notification-session') !=
                request.session ||
            await _storage.read(key: 'school-notification-background') !=
                'true' ||
            await _storage.read(key: 'login') != request.rawLogin ||
            !await _hasPermission() ||
            (foreground != null &&
                foreground.isAfter(DateTime.now().toUtc())) ||
            (last != null &&
                DateTime.now().toUtc().difference(last) <
                    const Duration(minutes: 2))) {
          runtimeTrace('SchoolNotifications', 'background-response-discarded');
          if ((await _enrolledAccounts()).containsKey(request.account)) {
            await _diagnose(
                request.account, {'backgroundResult': 'superseded'});
          }
          return;
        }
        await _ingest(request.account, data, background: true);
      }, label: 'background-commit');
    } catch (error) {
      await _locked(() async {
        if (!(await _enrolledAccounts()).containsKey(request.account)) return;
        await _diagnose(request.account, {
          'backgroundResult': error is DioException &&
                  (error.response?.statusCode == 401 ||
                      error.response?.statusCode == 403)
              ? 'authenticationRequired'
              : error is DioException
                  ? (error.type == DioExceptionType.cancel ||
                          error.type == DioExceptionType.receiveTimeout ||
                          error.type == DioExceptionType.connectionTimeout ||
                          error.type == DioExceptionType.sendTimeout
                      ? 'timeout'
                      : 'networkError')
                  : error is FormatException
                      ? 'invalidResponse'
                      : 'storageOrNotificationError',
          if (error is DioException &&
              (error.response?.statusCode == 401 ||
                  error.response?.statusCode == 403))
            'authenticationSession': request.session,
        });
      });
      rethrow;
    } finally {
      deadline.cancel();
      dio.close(force: true);
      await _locked(() async {
        if (await _storage.read(
                key: 'school-notification-lease-${request.account}') ==
            request.lease) {
          await _storage.delete(
              key: 'school-notification-lease-${request.account}');
        }
      }, history: false, label: 'release-background-lease');
      runtimeTrace('SchoolNotifications', 'background-end',
          durationMs: networkTimer.elapsedMilliseconds);
    }
  }
}

class SchoolNotificationOptInOffer {
  const SchoolNotificationOptInOffer(this.account, this.generation, this.label);
  final String account;
  final int generation;
  final String label;
}

class _BackgroundNotificationRequest {
  const _BackgroundNotificationRequest(
      {required this.lease,
      required this.active,
      required this.account,
      required this.session,
      required this.rawLogin,
      required this.server,
      required this.user,
      required this.password});
  final String account;
  final String active;
  final String lease;
  final String? session;
  final String rawLogin;
  final String server;
  final String user;
  final String password;
}
