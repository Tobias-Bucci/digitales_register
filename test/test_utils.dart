import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/serializers.dart';

final String serializedDefaultAppState =
    json.encode(serializers.serialize(AppState()));

Map<String, String> get initialLoggedInStorage => <String, String>{
      'login': json.encode(
        <String, Object?>{
          'user': 'username23',
          'pass': 'Passwort123',
          'url': 'https://example.digitales.register.example',
        },
      ),
      json.encode(<String, Object?>{
        'username': 'username23',
        'server_url': 'https://example.digitales.register.example/v2/api/login',
      }): serializedDefaultAppState,
    };
