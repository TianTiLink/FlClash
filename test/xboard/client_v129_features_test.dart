import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/xboard/proxies_connect_bar.dart';
import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('delay test batching and full-node policy', () {
    test('uses batch size of 6 and tests all nodes', () {
      expect(kDelayTestBatchSize, 6);
      expect(kDelaySkipThresholdMs, 300);
    });

    test('never skips any node during delay test', () {
      expect(shouldSkipProxyDelayTest(null), isFalse);
      expect(shouldSkipProxyDelayTest(0), isFalse);
      expect(shouldSkipProxyDelayTest(-1), isFalse);
      expect(shouldSkipProxyDelayTest(1), isFalse);
      expect(shouldSkipProxyDelayTest(180), isFalse);
      expect(shouldSkipProxyDelayTest(299), isFalse);
      expect(shouldSkipProxyDelayTest(300), isFalse);
      expect(shouldSkipProxyDelayTest(650), isFalse);
    });
  });

  group('emergency IP endpoint configuration', () {
    test('uses 107.148.152.214 as primary emergency API base', () {
      expect(kPrimaryEmergencyApiBase, 'https://107.148.152.214');
      expect(kEmergencyApiBases.first, 'https://107.148.152.214');
      expect(kEmergencyApiBases, contains('https://104.233.158.99'));
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
