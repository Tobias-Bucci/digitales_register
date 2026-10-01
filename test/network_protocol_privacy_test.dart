import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protocol rejects payloads and personal URL context at the reducer',
      () async {
    final store = Store<AppState, AppStateBuilder, AppActions>(
        appReducerBuilder.build(), AppState(), AppActions());
    await store.actions.addNetworkProtocolItem(NetworkProtocolItem((b) => b
      ..address = 'https://school.example/grades/student123?token=secret'
      ..parameters = 'password=secret'
      ..response = 'health reason and personal content'));
    final item = store.state.networkProtocolState.items.single;
    expect(item.address, '/grades');
    expect(item.parameters, '[redacted]');
    expect(item.response, '[redacted]');
    for (var i = 0; i < 105; i++) {
      await store.actions.addNetworkProtocolItem(NetworkProtocolItem((b) => b
        ..address = '/grades'
        ..parameters = 'secret'
        ..response = 'completed'));
    }
    expect(store.state.networkProtocolState.items.length, 100);
    expect(store.state.networkProtocolState.items.last.response, 'completed');
  });
}
