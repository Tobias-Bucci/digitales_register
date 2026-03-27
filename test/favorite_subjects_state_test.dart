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
      BuiltList<String>(const ["Fach1", "Fach2"]),
    );

    expect(
      store.state.settingsState.favoriteSubjects,
      BuiltList<String>(const ["Fach1", "Fach2"]),
    );
  });

  test('favorite subjects survive serialization roundtrip', () {
    final state = AppState(
      (b) => b.settingsState.favoriteSubjects = ListBuilder(
        const ["Fach1", "Fach2"],
      ),
    );

    final serialized = serializers.serialize(state);
    final deserialized = serializers.deserialize(serialized!) as AppState;

    expect(
      deserialized.settingsState.favoriteSubjects,
      BuiltList<String>(const ["Fach1", "Fach2"]),
    );
  });
}
