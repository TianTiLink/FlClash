import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dedicated independent package name', () {
    test('uses com.tiantilink.app to eliminate clashes with upstream/generic FlClash', () {
      expect(packageName, 'com.tiantilink.app');
    });
  });

  group('version detection and comparison', () {
    test('correctly identifies remote v0.8.130 is newer than v0.8.129', () {
      expect(isRemoteVersionNewer('0.8.130', '0.8.129'), isTrue);
      expect(isRemoteVersionNewer('v0.8.130', '0.8.129'), isTrue);
      expect(isRemoteVersionNewer('0.8.130', 'v0.8.129'), isTrue);
      expect(isRemoteVersionNewer('0.8.130', '0.8.130'), isFalse);
      expect(isRemoteVersionNewer('0.8.129', '0.8.130'), isFalse);
    });

    test('TtEndpointResult evaluates hasUpdate and updateForce properly', () {
      final optionalUpdateResult = TtEndpointResult(
        'https://tianti.xyz',
        true,
        {
          'client_version': '0.8.130',
          'update_force': false,
          'update_note': '常规稳定性更新与包名独立',
          'downloads': {'windows': 'https://tianti.xyz/TianTiLink-windows.exe'},
        },
        currentVersion: '0.8.129',
      );
      expect(optionalUpdateResult.hasUpdate, isTrue);
      expect(optionalUpdateResult.updateForce, isFalse);
      expect(optionalUpdateResult.latestVersion, '0.8.130');

      final forcedUpdateResult = TtEndpointResult(
        'https://tianti.xyz',
        true,
        {
          'client_version': '0.8.130',
          'update_force': true,
          'update_note': '必须更新此版本以恢复连接',
          'downloads': {'windows': 'https://tianti.xyz/TianTiLink-windows.exe'},
        },
        currentVersion: '0.8.129',
      );
      expect(forcedUpdateResult.hasUpdate, isTrue);
      expect(forcedUpdateResult.updateForce, isTrue);

      final noUpdateResult = TtEndpointResult(
        'https://tianti.xyz',
        true,
        {
          'client_version': '0.8.130',
          'update_force': false,
        },
        currentVersion: '0.8.130',
      );
      expect(noUpdateResult.hasUpdate, isFalse);
    });
  });
}
