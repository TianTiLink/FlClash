import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/xboard/proxies_connect_bar.dart';
import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('delay test batching and <300ms skip policy', () {
    test('uses batch size of 4 and 300ms threshold', () {
      expect(kDelayTestBatchSize, 4);
      expect(kDelaySkipThresholdMs, 300);
    });

    test('skips only measured positive delays strictly below 300ms', () {
      expect(shouldSkipProxyDelayTest(null), isFalse);
      expect(shouldSkipProxyDelayTest(0), isFalse);
      expect(shouldSkipProxyDelayTest(-1), isFalse);
      expect(shouldSkipProxyDelayTest(1), isTrue);
      expect(shouldSkipProxyDelayTest(180), isTrue);
      expect(shouldSkipProxyDelayTest(299), isTrue);
      expect(shouldSkipProxyDelayTest(300), isFalse);
      expect(shouldSkipProxyDelayTest(650), isFalse);
    });
  });

  group('emergency IP endpoint configuration', () {
    test('uses 186.244.220.105 as primary emergency API base', () {
      expect(kPrimaryEmergencyApiBase, 'https://186.244.220.105');
      expect(kEmergencyApiBases.first, 'https://186.244.220.105');
      expect(kEmergencyApiBases, contains('https://186.244.223.118'));
    });
  });

  group('ProxiesConnectBar dual-button bar above mode selector', () {
    testWidgets('renders 刷新订阅 and 延迟检测 above 智能 and 全局 and invokes callbacks', (
      tester,
    ) async {
      var refreshCount = 0;
      var delayCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runTimeProvider.overrideWithBuild((_, _) => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ProxiesConnectBar(
                  enabled: true,
                  onRefreshSubscription: () {
                    refreshCount++;
                  },
                  onTestDelay: () {
                    delayCount++;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final refreshFinder = find.text('刷新订阅');
      final delayFinder = find.text('延迟检测');
      final smartFinder = find.text('智能');
      final globalFinder = find.text('全局');

      expect(refreshFinder, findsOneWidget);
      expect(delayFinder, findsOneWidget);
      expect(smartFinder, findsOneWidget);
      expect(globalFinder, findsOneWidget);

      // Verify the new dual-button bar sits vertically above 智能 / 全局
      final refreshDy = tester.getCenter(refreshFinder).dy;
      final delayDy = tester.getCenter(delayFinder).dy;
      final smartDy = tester.getCenter(smartFinder).dy;
      expect((refreshDy - delayDy).abs(), lessThan(1.0));
      expect(refreshDy, lessThan(smartDy));

      await tester.tap(refreshFinder);
      await tester.pump();
      expect(refreshCount, 1);

      await tester.tap(delayFinder);
      await tester.pump();
      expect(delayCount, 1);
    });

    testWidgets('keeps 刷新订阅 active while disabling 延迟检测 when no plan', (
      tester,
    ) async {
      var refreshCount = 0;
      var delayCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runTimeProvider.overrideWithBuild((_, _) => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProxiesConnectBar(
                enabled: false,
                onRefreshSubscription: () {
                  refreshCount++;
                },
                onTestDelay: () {
                  delayCount++;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('刷新订阅'));
      await tester.pump();
      expect(refreshCount, 1);

      await tester.tap(find.text('延迟检测'));
      await tester.pump();
      expect(delayCount, 0);
    });
  });
}
