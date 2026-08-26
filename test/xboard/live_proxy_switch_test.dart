import 'package:fl_clash/xboard/live_proxy_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'connected node switch changes proxy then closes active connections',
    () async {
      final calls = <String>[];

      await applyLiveProxySwitch(
        changeProxy: () async => calls.add('change'),
        closeExistingConnections: true,
        closeConnections: () async => calls.add('close-connections'),
        resetConnections: () async => calls.add('reset-connections'),
      );

      expect(calls, ['change', 'close-connections']);
    },
  );

  test(
    'node switch resets connections when automatic close is disabled',
    () async {
      final calls = <String>[];

      await applyLiveProxySwitch(
        changeProxy: () async => calls.add('change'),
        closeExistingConnections: false,
        closeConnections: () async => calls.add('close-connections'),
        resetConnections: () async => calls.add('reset-connections'),
      );

      expect(calls, ['change', 'reset-connections']);
    },
  );

  test('failed node change does not touch existing connections', () async {
    final calls = <String>[];

    await expectLater(
      applyLiveProxySwitch(
        changeProxy: () async {
          calls.add('change');
          throw StateError('switch failed');
        },
        closeExistingConnections: true,
        closeConnections: () async => calls.add('close-connections'),
        resetConnections: () async => calls.add('reset-connections'),
      ),
      throwsStateError,
    );

    expect(calls, ['change']);
  });
}
