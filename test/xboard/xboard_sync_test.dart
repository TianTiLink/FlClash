import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/xboard/xboard_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Profile profile({required String label, required String url}) =>
    Profile.normal(label: label, url: url);

void main() {
  test('subscription candidates preserve server order and remove duplicates', () {
    expect(
      orderedSubscriptionCandidates('https://first.example/s/token', const [
        'https://first.example/s/token',
        'https://second.example/s/token',
        'https://186.244.223.118:45618/s/token',
      ]),
      const [
        'https://first.example/s/token',
        'https://second.example/s/token',
        'https://186.244.223.118:45618/s/token',
      ],
    );
  });

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

  test('recognizes a branded TianTi profile saved with the old Core path', () {
    final item = profile(
      label: 'TianTi',
      url: 'https://api.example/api/v1/client/subscribe?token=legacy',
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

  test('shouldTianTiAutoRefresh triggers on first run (null lastRefreshTime)', () {
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: null,
        force: false,
      ),
      isTrue,
    );
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: null,
        force: true,
      ),
      isTrue,
    );
  });

  test('shouldTianTiAutoRefresh enforces 6-hour routine interval', () {
    final now = DateTime(2026, 10, 22, 12, 0);

    // 5 hours ago -> false
    final fiveHoursAgo = now.subtract(const Duration(hours: 5));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: fiveHoursAgo,
        force: false,
        now: now,
      ),
      isFalse,
    );

    // 6 hours ago -> true
    final sixHoursAgo = now.subtract(const Duration(hours: 6));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: sixHoursAgo,
        force: false,
        now: now,
      ),
      isTrue,
    );

    // 12 hours ago -> true
    final twelveHoursAgo = now.subtract(const Duration(hours: 12));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: twelveHoursAgo,
        force: false,
        now: now,
      ),
      isTrue,
    );
  });

  test('shouldTianTiAutoRefresh enforces 5-minute healing cooldown', () {
    final now = DateTime(2026, 10, 22, 12, 0);

    // 2 minutes ago -> false (cooldown)
    final twoMinutesAgo = now.subtract(const Duration(minutes: 2));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: twoMinutesAgo,
        force: true,
        now: now,
      ),
      isFalse,
    );

    // 5 minutes ago -> true
    final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: fiveMinutesAgo,
        force: true,
        now: now,
      ),
      isTrue,
    );
  });

  test('hasSubscriptionContentChanged detects identical and modified payloads', () {
    final original = [1, 2, 3, 4, 5];
    final same = [1, 2, 3, 4, 5];
    final differentLength = [1, 2, 3, 4];
    final differentValue = [1, 2, 9, 4, 5];

    expect(hasSubscriptionContentChanged(original, same), isFalse);
    expect(hasSubscriptionContentChanged(original, differentLength), isTrue);
    expect(hasSubscriptionContentChanged(original, differentValue), isTrue);
  });
}
