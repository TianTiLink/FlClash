import 'package:fl_clash/xboard/xboard_api.dart';
import 'package:fl_clash/xboard/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends XboardApi {
  final Object? loginError;
  final Object? subscribeError;

  _FakeApi({this.loginError, this.subscribeError})
    : super('https://api.example.invalid');

  @override
  Future<XboardLoginResult> login(String email, String password) async {
    if (loginError != null) throw loginError!;
    return XboardLoginResult('auth-token', 'auth-token');
  }

  @override
  Future<XboardSubscribe> getSubscribe(String authData) async {
    if (subscribeError != null) throw subscribeError!;
    return XboardSubscribe(
      subscribeUrl: 'https://sub.example.invalid/s/token',
      upload: 0,
      download: 0,
      transferEnable: 1024,
      expiredAt: null,
      planName: 'Test',
    );
  }
}

void main() {
  setUpAll(() async {
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    xboardApiFactory = XboardApi.new;
  });

  test(
    'confirmed authentication survives a subscription sync failure',
    () async {
      xboardApiFactory = (_) => _FakeApi(
        subscribeError: XboardApiException('temporary account failure'),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container
          .read(xboardAuthProvider.notifier)
          .login(
            panelUrl: 'https://api.example.invalid',
            email: 'web@example.invalid',
            password: 'Contract!2026',
          );

      final state = container.read(xboardAuthProvider);
      expect(state.loggedIn, isTrue);
      expect(state.email, 'web@example.invalid');
      expect(state.authData, 'auth-token');
      expect(state.subscribeUrl, isNull);
      expect(outcome.mihomoUrl, isNull);
      expect(outcome.syncWarning, contains('temporary account failure'));
    },
  );

  test('credential rejection remains a real login failure', () async {
    xboardApiFactory = (_) =>
        _FakeApi(loginError: XboardApiException('账号或密码错误'));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(xboardAuthProvider.notifier)
          .login(
            panelUrl: 'https://api.example.invalid',
            email: 'missing@example.invalid',
            password: 'wrong-password',
          ),
      throwsA(isA<XboardApiException>()),
    );
    expect(container.read(xboardAuthProvider).loggedIn, isFalse);
  });

  test(
    'successful authentication and subscription sync returns import URL',
    () async {
      xboardApiFactory = (_) => _FakeApi();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await container
          .read(xboardAuthProvider.notifier)
          .login(
            panelUrl: 'https://api.example.invalid',
            email: 'web@example.invalid',
            password: 'Contract!2026',
          );

      expect(container.read(xboardAuthProvider).loggedIn, isTrue);
      expect(container.read(xboardAuthProvider).subscribeUrl, isNotNull);
      expect(outcome.mihomoUrl, contains('flag=meta'));
      expect(outcome.syncWarning, isNull);
    },
  );
}
