// Copyright (C) 2026 Tobias Bucci

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/serializers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('favorite subjects reducer updates settings state', () async {
    final store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(),
      AppActions(),
    );

    await store.actions.settingsActions.favoriteSubjects(
      BuiltList<String>(const <String>['Fach1', 'Fach2']),
    );

    expect(
      store.state.settingsState.favoriteSubjects,
      BuiltList<String>(const <String>['Fach1', 'Fach2']),
    );
  });

  test('favorite subjects survive a serialization roundtrip', () {
    final state = AppState(
      (b) => b.settingsState.favoriteSubjects = ListBuilder<String>(
        const <String>['Fach1', 'Fach2'],
      ),
    );

    final serialized = serializers.serialize(state);
    final deserialized = serializers.deserialize(serialized);

    expect(deserialized, isA<AppState>());
    expect(
      (deserialized! as AppState).settingsState.favoriteSubjects,
      BuiltList<String>(const <String>['Fach1', 'Fach2']),
    );
  });
}
