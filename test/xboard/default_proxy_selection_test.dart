import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/xboard/default_proxy_selection.dart';
import 'package:flutter_test/flutter_test.dart';

Proxy proxy(String name, {String type = 'vless'}) =>
    Proxy(name: name, type: type);

Group selector(String name, List<Proxy> proxies) =>
    Group(name: name, type: GroupType.Selector, all: proxies);

void main() {
  test('uses the first concrete node when no node was selected', () {
    final result = withDefaultProxySelections(
      groups: [
        selector('TianTi', [proxy('DIRECT'), proxy('香港01'), proxy('日本东京')]),
      ],
      selectedMap: const {},
    );

    expect(result['TianTi'], '香港01');
  });

  test('preserves an existing valid user selection', () {
    final result = withDefaultProxySelections(
      groups: [
        selector('TianTi', [proxy('香港01'), proxy('日本东京')]),
      ],
      selectedMap: const {'TianTi': '日本东京'},
    );

    expect(result['TianTi'], '日本东京');
  });

  test('does not invent a selection for an empty or nested-only group', () {
    final groups = [
      selector('自动选择', const []),
      selector('TianTi', [proxy('自动选择', type: 'url-test'), proxy('REJECT')]),
    ];

    expect(
      withDefaultProxySelections(groups: groups, selectedMap: const {}),
      isEmpty,
    );
  });
}
