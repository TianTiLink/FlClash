import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int kDelayTestBatchSize = 4;
const int kDelaySkipThresholdMs = 300;

class DelayTestSummary {
  final int total;
  final int tested;
  final int skipped;

  const DelayTestSummary({
    required this.total,
    required this.tested,
    required this.skipped,
  });
}

bool shouldSkipProxyDelayTest(int? existingDelay) {
  return existingDelay != null &&
      existingDelay > 0 &&
      existingDelay < kDelaySkipThresholdMs;
}

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight + 2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight + measure.labelSmallHeight + 6,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

List<Group> getCurrentGroups() {
  return globalState.container.read(currentGroupsStateProvider).value;
}

List<Group> getGroups() {
  return globalState.container.read(groupsProvider);
}

String? getCurrentGroupName() {
  return globalState.container.read(
    currentProfileProvider.select((state) => state?.currentGroupName),
  );
}

void updateCurrentGroupName(String groupName) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentGroupName(groupName);
}

void updateCurrentUnfoldSet(Set<String> value) {
  globalState.container
      .read(proxiesActionProvider.notifier)
      .updateCurrentUnfoldSet(value);
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
  final ref = globalState.container;
  final groups = getGroups();
  final selectedMap = ref.read(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  final state = computeRealSelectedProxyState(
    proxy.name,
    groups: groups,
    selectedMap: selectedMap,
  );
  final currentTestUrl = state.testUrl.takeFirstValid([
    ref.read(realTestUrlProvider(testUrl)),
  ]);
  if (state.proxyName.isEmpty) {
    return;
  }
  ref
      .read(proxiesActionProvider.notifier)
      .setDelay(Delay(url: currentTestUrl, name: state.proxyName, value: 0));
  try {
    final delay = await coreController
        .getDelay(currentTestUrl, state.proxyName)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              Delay(url: currentTestUrl, name: state.proxyName, value: -1),
        );
    ref.read(proxiesActionProvider.notifier).setDelay(delay);
  } catch (_) {
    ref
        .read(proxiesActionProvider.notifier)
        .setDelay(Delay(url: currentTestUrl, name: state.proxyName, value: -1));
  }
}

Future<DelayTestSummary> delayTestWithSummary(
  List<Proxy> proxies, [
  String? testUrl,
]) async {
  final ref = globalState.container;
  final groups = getGroups();
  final selectedMap = ref.read(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  final defaultResolvedTestUrl = ref.read(realTestUrlProvider(testUrl));
  final delayMap = ref.read(delayDataSourceProvider);

  final proxiesToTest = <Proxy>[];
  var skipped = 0;

  for (final proxy in proxies) {
    final state = computeRealSelectedProxyState(
      proxy.name,
      groups: groups,
      selectedMap: selectedMap,
    );
    if (state.proxyName.isEmpty) {
      continue;
    }
    final currentTestUrl = state.testUrl.takeFirstValid([
      defaultResolvedTestUrl,
    ]);
    final existingDelay = delayMap[currentTestUrl]?[state.proxyName];
    if (shouldSkipProxyDelayTest(existingDelay)) {
      skipped++;
      continue;
    }
    proxiesToTest.add(proxy);
  }

  for (
    var start = 0;
    start < proxiesToTest.length;
    start += kDelayTestBatchSize
  ) {
    final end = start + kDelayTestBatchSize < proxiesToTest.length
        ? start + kDelayTestBatchSize
        : proxiesToTest.length;
    final batch = proxiesToTest.sublist(start, end);
    await Future.wait(batch.map((proxy) => proxyDelayTest(proxy, testUrl)));
  }

  ref.read(sortNumProvider.notifier).add();
  return DelayTestSummary(
    total: proxies.length,
    tested: proxiesToTest.length,
    skipped: skipped,
  );
}

Future<int> delayTest(List<Proxy> proxies, [String? testUrl]) async {
  final summary = await delayTestWithSummary(proxies, testUrl);
  return summary.total;
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final ref = globalState.container;
  final columns = ref.read(proxiesColumnsProvider);
  final proxyCardType = ref.read(
    proxiesStyleSettingProvider.select((state) => state.cardType),
  );
  final selectedProxyName = ref.read(selectedProxyNameProvider(groupName));
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}
