import 'package:fl_clash/xboard/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith can explicitly clear a stale subscription URL', () {
    const state = XboardAuthState(
      restored: true,
      loggedIn: true,
      authData: 'Bearer test',
      subscribeUrl: 'https://subscription.example/s/old-token',
    );

    final cleared = state.copyWith(subscribeUrl: null);

    expect(cleared.subscribeUrl, isNull);
    expect(cleared.authData, 'Bearer test');
  });

  test('copyWith still preserves nullable values when omitted', () {
    const state = XboardAuthState(
      authData: 'Bearer test',
      subscribeUrl: 'https://subscription.example/s/token',
    );

    final updated = state.copyWith(email: 'user@example.com');

    expect(updated.authData, 'Bearer test');
    expect(updated.subscribeUrl, 'https://subscription.example/s/token');
  });
}
