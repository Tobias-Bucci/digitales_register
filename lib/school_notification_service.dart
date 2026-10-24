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
      Dio Function(BaseOptions)? httpClient,
      Future<Directory> Function()? historyDirectory})
      : _native = native ?? FlutterLocalNotificationsPlugin(),
        _providedStorage = storage,
        _permission = permission,
        _httpClient = httpClient ?? ((options) => Dio(options)),
        _databaseFactory = database,
        _historyDirectory = historyDirectory ?? getApplicationSupportDirectory;
  static final _processMutex = Mutex();
  final FlutterLocalNotificationsPlugin _native;
  final FlutterSecureStorage? _providedStorage;
  final Future<bool> Function()? _permission;
  final Dio Function(BaseOptions) _httpClient;
  final Future<Database> Function()? _databaseFactory;
  final Future<Directory> Function() _historyDirectory;
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
  Future<void>? _initializing;
  Future<void>? _activation;
  Future<void>? _backgroundWork;
  int _sessionGeneration = 0;
  Timer? _timer;
  bool granted = false;
  bool backgroundAvailable = true;
  SchoolNotificationPreferences preferences = SchoolNotificationPreferences();
  SchoolNotificationDestination? pendingDestination;
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
        await _markForeground(true);
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
      if (granted && (preferences.grades || preferences.messages)) {
        unawaited(schoolNotificationOperation(() async {
          await _markForeground(true);
          await refresh?.call();
        }));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(schoolNotificationOperation(() => _markForeground(true)));
      _startForegroundChecks();
    } else {
      _timer?.cancel();
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        unawaited(schoolNotificationOperation(() => _markForeground(false)));
      }
    }
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

  Future<void> _loadPreferences() async {
    final raw = await _storage.read(key: 'school-notification-preferences-v1');
    final data = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map;
    preferences = SchoolNotificationPreferences(
        grades: data['grades'] != false, messages: data['messages'] != false);
  }

  Future<void> reload() async {
    if (!supported || !_initialized) return;
    await _locked(() async {
      await _loadPreferences();
      granted = await _hasPermission();
      final previous =
          await _storage.read(key: 'school-notification-permission');
      if (granted && previous != 'true') {
        final account = await _storage.read(key: 'school-notification-active');
        if (account != null) {
          for (final category in SchoolNotificationCategory.values) {
            await _engine.baselineNext(account, category.name);
          }
        }
      }
      await _storage.write(
          key: 'school-notification-permission', value: '$granted');
      if (granted && previous != 'true') await _prepareBackgroundCredentials();
    });
    notifyListeners();
  }

  Future<void> requestPermission() async {
    if (!supported) return;
    await initialize();
    // Only called from the explanatory settings button, never on startup.
    if (Platform.isAndroid) {
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
    await reload();
    await _markForeground(true);
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
          key: 'school-notification-preferences-v1',
          value: jsonEncode(preferences.toJson()));
      await _native.cancelAll();
    });
    notifyListeners();
    await schedule();
    await refresh?.call();
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
    await initialize();
    await _locked(() async {
      if (generation != _sessionGeneration) return;
      final account = accountKey(server, user);
      final previous = await _storage.read(key: 'school-notification-active');
      if (previous != account) await _native.cancelAll();
      await _storage.write(key: 'school-notification-active', value: account);
      // A session token also rejects late responses after A -> B -> A or logout
      // followed by another login to the same account, across Flutter engines.
      await _storage.write(
          key: 'school-notification-session',
          value: notificationDigest(Hive.generateSecureKey()));
      await _storage.write(
          key: 'school-notification-background', value: '$backgroundAllowed');
      await _prepareBackgroundCredentials();
    }, label: 'activate', history: false);
    if (generation == _sessionGeneration) await schedule();
  }

  /// Caller holds the account lock. Upgrade only after notification consent,
  /// without introducing a second credential record.
  Future<void> _prepareBackgroundCredentials() async {
    if (!Platform.isIOS ||
        !granted ||
        await _storage.read(key: 'school-notification-background') != 'true') {
      return;
    }
    final login = await _storage.read(key: 'login');
    if (login != null) await _storage.write(key: 'login', value: login);
  }

  Future<void> deactivate() async {
    ++_sessionGeneration;
    if (!supported) return;
    await _locked(() async {
      await _storage.delete(key: 'school-notification-active');
      await _storage.delete(key: 'school-notification-session');
      await _native.cancelAll();
      pendingDestination = null;
    }, label: 'deactivate', history: false);
    if (mobileBackgroundSupported && _initialized) {
      try {
        await Workmanager().cancelByUniqueName(schoolNotificationTask);
      } catch (error) {
        // The account is already revoked. An unavailable scheduler must not
        // undo that barrier or prevent logout; later workers recheck storage.
        backgroundAvailable = false;
        runtimeTrace('SchoolNotifications', 'cancel-schedule-failed',
            detail: 'type=${error.runtimeType}');
      }
    }
  }

  Future<void> schedule() async {
    if (!supported || !_initialized) return;
    if (!mobileBackgroundSupported) return;
    try {
      if (Platform.isIOS &&
          await const MethodChannel('dr/school_notifications')
                  .invokeMethod<bool>('backgroundRefreshAvailable') !=
              true) {
        backgroundAvailable = false;
        notifyListeners();
        return;
      }
      if (!granted ||
          (!preferences.grades && !preferences.messages) ||
          await _storage.read(key: 'school-notification-active') == null ||
          await _storage.read(key: 'school-notification-background') !=
              'true') {
        await Workmanager().cancelByUniqueName(schoolNotificationTask);
      } else {
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
    } catch (_) {
      backgroundAvailable = false;
    }
    notifyListeners();
  }

  Future<void> ingest(String server, String user, List data) async {
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
      await _ingest(account, data);
    }, label: 'ingest');
  }

  Future<void> _ingest(String account, List data) async {
    final events = data
        .map((e) => e is Map ? SchoolNotificationEvent.parse(e) : null)
        .whereType<SchoolNotificationEvent>()
        .toList();
    await _loadPreferences();
    await (await SharedPreferences.getInstance()).reload();
    await appLanguageController.load();
    final l10n =
        await AppLocalizations.load(appLanguageController.language.locale);
    await _engine.synchronize(
        account: account,
        events: events,
        preferences: preferences,
        permitted: await _hasPermission(),
        now: DateTime.now(),
        deliver: (event) async {
          // Recheck after persisting the claim; never show without OS permission.
          if (!await _hasPermission()) return;
          final kind = event.category.name;
          final id = int.parse(
              notificationDigest([account, event.identity]).substring(0, 7),
              radix: 16);
          await _native.show(
              id: id,
              title: l10n.text('schoolNotifications.$kind.title'),
              body: l10n.text('schoolNotifications.$kind.body'),
              notificationDetails: NotificationDetails(
                  android: AndroidNotificationDetails('school_$kind',
                      l10n.text('schoolNotifications.$kind.title'),
                      visibility: NotificationVisibility.private,
                      onlyAlertOnce: true),
                  iOS: const DarwinNotificationDetails(),
                  macOS: const DarwinNotificationDetails(),
                  linux: const LinuxNotificationDetails()),
              payload: SchoolNotificationDestination(
                      account, event.category, event.objectId)
                  .encode());
        });
    await _storage.write(
        key: 'school-notification-last-sync-$account',
        value: DateTime.now().toUtc().toIso8601String());
  }

  Future<void> markViewed(
      String server, String user, List<Map<String, Object?>> items) async {
    if (!supported || !_initialized) return;
    await _locked(() async {
      final account = accountKey(server, user);
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
    });
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
    // Capture the request under a short storage lock. No network operation may
    // run inside that lock: a slow worker must never stall a foreground engine.
    final request = await _locked<_BackgroundNotificationRequest?>(() async {
      if (!await _hasPermission()) return null;
      await _loadPreferences();
      if (!preferences.grades && !preferences.messages) return null;
      final account = await _storage.read(key: 'school-notification-active');
      if (account == null ||
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
      final server = login['url'] as String?;
      final user = login['user'] as String?;
      final password = login['pass'];
      if (server == null ||
          user == null ||
          password is! String ||
          accountKey(server, user) != account ||
          user == 'demo' ||
          user == 'debug') {
        return null;
      }
      final uri = Uri.tryParse(server);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
      return _BackgroundNotificationRequest(
          account: account,
          session: await _storage.read(key: 'school-notification-session'),
          rawLogin: raw,
          server: server,
          user: user,
          password: password);
    }, label: 'background-prepare', history: false);
    if (request == null) {
      runtimeTrace('SchoolNotifications', 'background-skipped');
      return;
    }
    final networkTimer = Stopwatch()..start();
    runtimeTrace('SchoolNotifications', 'background-network-start');
    final dio = _httpClient(BaseOptions(
        baseUrl: '${request.server.replaceAll(RegExp(r'/+$'), '')}/v2/',
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        followRedirects: false));
    dio.interceptors.add(CookieManager(CookieJar()));
    final cancellation = CancelToken();
    final deadline = Timer(const Duration(seconds: 20),
        () => cancellation.cancel('Background refresh deadline'));
    try {
      final result = (await dio.post<dynamic>('api/auth/login',
              data: {
                'username': request.user,
                'password': request.password,
              },
              cancelToken: cancellation))
          .data;
      final auth = result is String ? jsonDecode(result) : result;
      if (auth is! Map || (auth['loggedIn'] != true && auth['loggedIn'] != 1)) {
        return;
      }
      final response = (await dio.post<dynamic>('api/notification/unread',
              data: <String, Object?>{}, cancelToken: cancellation))
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
                request.account ||
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
          return;
        }
        await _ingest(request.account, data);
      }, label: 'background-commit');
    } finally {
      deadline.cancel();
      dio.close(force: true);
      runtimeTrace('SchoolNotifications', 'background-end',
          durationMs: networkTimer.elapsedMilliseconds);
    }
  }
}

class _BackgroundNotificationRequest {
  const _BackgroundNotificationRequest(
      {required this.account,
      required this.session,
      required this.rawLogin,
      required this.server,
      required this.user,
      required this.password});
  final String account;
  final String? session;
  final String rawLogin;
  final String server;
  final String user;
  final String password;
}
