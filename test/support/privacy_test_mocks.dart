import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Install on every test: the binding removes channel handlers after each test.
/// Exercise the real Dart adapters without native Firebase or network access.
void mockPrivacyPlugins() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  TestFirebaseCoreHostApi.setUp(_PrivacyFirebaseCore());
  messenger.setMockMethodCallHandler(
    const MethodChannel('dr/privacy_bootstrap'),
    (call) async {
      switch (call.method) {
        case 'ready':
          return true;
        case 'installationSource':
          return 'unknown';
        default:
          throw MissingPluginException('Unexpected bootstrap: ${call.method}');
      }
    },
  );
  // Analytics uses Pigeon BasicMessageChannels, not the legacy MethodChannel.
  // These methods exchange only standard-codec values and a void envelope.
  for (final method in <String>[
    'setAnalyticsCollectionEnabled',
    'setConsent',
    'resetAnalyticsData',
    'setUserId',
    'setUserProperty',
    'logEvent',
  ]) {
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.firebase_analytics_platform_interface.'
        'FirebaseAnalyticsHostApi.$method',
        const StandardMessageCodec(),
      ),
      (_) async => <Object?>[null],
    );
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_crashlytics'),
    (call) async {
      switch (call.method) {
        case 'Crashlytics#setCrashlyticsCollectionEnabled':
          return <String, Object?>{
            'isCrashlyticsCollectionEnabled': call.arguments['enabled'],
          };
        case 'Crashlytics#deleteUnsentReports':
        case 'Crashlytics#setCustomKey':
        case 'Crashlytics#log':
        case 'Crashlytics#recordError':
          return null;
        default:
          throw MissingPluginException(
              'Unexpected crashlytics: ${call.method}');
      }
    },
  );
}

class _PrivacyFirebaseCore extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    for (final app in apps) {
      app.pluginConstants['plugins.flutter.io/firebase_crashlytics'] =
          <String, Object>{'isCrashlyticsCollectionEnabled': false};
    }
    return apps;
  }
}
