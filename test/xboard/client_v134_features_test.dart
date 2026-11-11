import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('version detection and comparison for v0.8.134', () {
    test('correctly identifies remote v0.8.134 is newer than v0.8.133', () {
      expect(isRemoteVersionNewer('0.8.134', '0.8.133'), isTrue);
      expect(isRemoteVersionNewer('v0.8.134', '0.8.133'), isTrue);
      expect(isRemoteVersionNewer('0.8.134', 'v0.8.133'), isTrue);
      expect(isRemoteVersionNewer('0.8.134', '0.8.134'), isFalse);
      expect(isRemoteVersionNewer('0.8.133', '0.8.134'), isFalse);
    });

    test('TtEndpointResult evaluates hasUpdate and updateForce properly for 0.8.134', () {
      final optionalUpdateResult = TtEndpointResult(
        'https://tianti.xyz',
        true,
        {
          'client_version': '0.8.134',
          'update_force': false,
          'update_note': 'macOS 钥匙串权限异常与登录受阻彻底根治',
          'downloads': {'macos': 'https://tianti.xyz/TianTiLink-macos.zip'},
        },
        currentVersion: '0.8.133',
      );
      expect(optionalUpdateResult.hasUpdate, isTrue);
      expect(optionalUpdateResult.updateForce, isFalse);
      expect(optionalUpdateResult.latestVersion, '0.8.134');
    });
  });
}
