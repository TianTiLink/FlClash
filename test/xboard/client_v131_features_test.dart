import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dedicated independent package name', () {
    test('uses com.tiantilink.app to eliminate clashes with upstream/generic FlClash', () {
      expect(packageName, 'com.tiantilink.app');
    });
  });

  group('version detection and comparison for v0.8.131', () {
    test('correctly identifies remote v0.8.131 is newer than v0.8.130', () {
      expect(isRemoteVersionNewer('0.8.131', '0.8.130'), isTrue);
      expect(isRemoteVersionNewer('v0.8.131', '0.8.130'), isTrue);
      expect(isRemoteVersionNewer('0.8.131', 'v0.8.130'), isTrue);
      expect(isRemoteVersionNewer('0.8.131', '0.8.131'), isFalse);
      expect(isRemoteVersionNewer('0.8.130', '0.8.131'), isFalse);
    });

    test('TtEndpointResult evaluates hasUpdate and updateForce properly for 0.8.131', () {
      final optionalUpdateResult = TtEndpointResult(
        'https://tianti.xyz',
        true,
        {
          'client_version': '0.8.131',
          'update_force': false,
          'update_note': 'Windows 安装防占用与 TUN 模式权限修复',
          'downloads': {'windows': 'https://tianti.xyz/TianTiLink-windows.exe'},
        },
        currentVersion: '0.8.130',
      );
      expect(optionalUpdateResult.hasUpdate, isTrue);
      expect(optionalUpdateResult.updateForce, isFalse);
      expect(optionalUpdateResult.latestVersion, '0.8.131');
    });
  });
}
