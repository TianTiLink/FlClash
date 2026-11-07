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
        'https://186.244.220.105:45618/s/token',
      ]),
      const [
        'https://first.example/s/token',
        'https://second.example/s/token',
        'https://186.244.220.105:45618/s/token',
      ],
    );
  });

  test('expands 43-char managed token URLs with IP-SSL fallbacks', () {
    const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
    expect(token.length, 43);
    expect(
      expandTianTiSubscriptionFallbacks(const [
        'https://vm634xcklj68vas12d4.xyz/s/$token',
      ]),
      const [
        'https://vm634xcklj68vas12d4.xyz/s/$token',
        'https://186.244.220.105:45618/s/$token',
        'https://186.244.223.118:45618/s/$token',
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

  test('shouldTianTiAutoRefresh always triggers on cold startup', () {
    final now = DateTime(2026, 11, 8, 12, 0);
    final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: oneMinuteAgo,
        force: false,
        reason: 'startup',
        now: now,
      ),
      isTrue,
    );
  });

  test('shouldTianTiAutoRefresh enforces 1-hour routine interval while open', () {
    final now = DateTime(2026, 11, 8, 12, 0);
    expect(kTianTiRoutineRefreshInterval, const Duration(hours: 1));

    // 59 minutes ago -> false
    final fiftyNineMinutesAgo = now.subtract(const Duration(minutes: 59));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: fiftyNineMinutesAgo,
        force: false,
        reason: 'periodic',
        now: now,
      ),
      isFalse,
    );

    // 1 hour ago -> true
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: oneHourAgo,
        force: false,
        reason: 'periodic',
        now: now,
      ),
      isTrue,
    );

    // 2 hours ago -> true
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    expect(
      shouldTianTiAutoRefresh(
        lastRefreshTime: twoHoursAgo,
        force: false,
        reason: 'resume',
        now: now,
      ),
      isTrue,
    );
  });

  test('shouldTianTiAutoRefresh enforces 5-minute healing cooldown', () {
    final now = DateTime(2026, 11, 8, 12, 0);

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
