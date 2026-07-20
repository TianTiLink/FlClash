import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isRemoteVersionNewer', () {
    test('returns true only when the backend version is newer', () {
      expect(isRemoteVersionNewer('0.8.96', '0.8.95'), isTrue);
      expect(isRemoteVersionNewer('0.8.95', '0.8.95'), isFalse);
      expect(isRemoteVersionNewer('0.8.94', '0.8.95'), isFalse);
    });

    test('accepts a leading v and compares build numbers', () {
      expect(isRemoteVersionNewer('v1.2.3', '1.2.2'), isTrue);
      expect(isRemoteVersionNewer('1.2.3+2', '1.2.3+1'), isTrue);
    });

    test('does not show an update for invalid backend values', () {
      expect(isRemoteVersionNewer('', '0.8.95'), isFalse);
      expect(isRemoteVersionNewer('latest', '0.8.95'), isFalse);
    });
  });

  test('endpoint result does not report an older backend as an update', () {
    final result = TtEndpointResult(
      'https://example.com',
      true,
      {
        'versions': {
          'android': '0.8.95',
          'windows': '0.8.95',
          'macos': '0.8.95',
          'pwa': '0.8.95',
        },
      },
      currentVersion: '0.8.96',
    );

    expect(result.hasUpdate, isFalse);
  });
}
