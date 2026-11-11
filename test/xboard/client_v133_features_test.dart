import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dedicated independent package name', () {
    test('uses com.tiantilink.app to eliminate clashes with upstream/generic FlClash', () {
      expect(packageName, 'com.tiantilink.app');
    });
  });

  group('version detection and comparison for v0.8.133', () {
    test('correctly identifies remote v0.8.133 is newer than v0.8.131 and v0.8.132', () {
      expect(isRemoteVersionNewer('0.8.133', '0.8.131'), isTrue);
      expect(isRemoteVersionNewer('v0.8.133', '0.8.132'), isTrue);
      expect(isRemoteVersionNewer('0.8.133', 'v0.8.132'), isTrue);
      expect(isRemoteVersionNewer('0.8.133', '0.8.133'), isFalse);
      expect(isRemoteVersionNewer('0.8.132', '0.8.133'), isFalse);
    });

    test('TtEndpointResult evaluates hasUpdate and updateForce properly for 0.8.133', () {
      final optionalUpdateResult = TtEndpointResult(
        'https://tianti.xyz',
        true,
        {
          'client_version': '0.8.133',
          'update_force': false,
          'update_note': 'Windows 安装防占用与 TUN 模式权限全面修复',
          'downloads': {'windows': 'https://tianti.xyz/TianTiLink-windows.exe'},
        },
        currentVersion: '0.8.131',
      );
      expect(optionalUpdateResult.hasUpdate, isTrue);
      expect(optionalUpdateResult.updateForce, isFalse);
      expect(optionalUpdateResult.latestVersion, '0.8.133');
    });
  });
}
