import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/xboard/xboard_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Profile profile({required String label, required String url}) =>
    Profile.normal(label: label, url: url);

void main() {
  test('matches the exact saved TianTi subscription ignoring client flags', () {
    final item = profile(
      label: '任意名称',
      url: 'https://sub.example/s/token?flag=meta&_=123',
    );

    expect(
      isTianTiManagedSubscription(
        item,
        subscribeUrl: 'https://sub.example/s/token',
      ),
      isTrue,
    );
  });

  test('recognizes a branded legacy TianTi profile', () {
    final item = profile(
      label: '天梯Link',
      url: 'https://sub.example/s/legacy-token?flag=meta',
    );

    expect(isTianTiManagedSubscription(item), isTrue);
  });

  test('does not classify an unrelated subscription as TianTi managed', () {
    final item = profile(
      label: '我的其他订阅',
      url: 'https://other.example/s/token?flag=meta',
    );

    expect(isTianTiManagedSubscription(item), isFalse);
  });
}
