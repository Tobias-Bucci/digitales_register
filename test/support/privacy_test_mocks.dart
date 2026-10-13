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
  // Crashlytics 5.4 also uses Pigeon. Enabling collection returns a bool;
  // the other methods below return a void envelope.
  const crashlyticsPrefix =
      'dev.flutter.pigeon.firebase_crashlytics_platform_interface.'
      'FirebaseCrashlyticsHostApi.';
  messenger.setMockDecodedMessageHandler<Object?>(
    const BasicMessageChannel<Object?>(
      '${crashlyticsPrefix}setCrashlyticsCollectionEnabled',
      StandardMessageCodec(),
    ),
    (message) async => <Object?>[(message! as List<Object?>).single],
  );
  for (final method in <String>[
    'deleteUnsentReports',
    'setCustomKey',
    'log',
    'recordError',
  ]) {
    // recordError carries generated Pigeon objects. The mock only acknowledges
    // delivery, so leave its payload encoded instead of decoding custom tags.
    messenger.setMockMessageHandler(
      '$crashlyticsPrefix$method',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  }
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
