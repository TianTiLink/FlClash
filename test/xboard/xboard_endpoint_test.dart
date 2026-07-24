import 'package:fl_clash/xboard/xboard_endpoint.dart';
import 'package:fl_clash/xboard/xboard_api.dart';
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
    final result = TtEndpointResult('https://example.com', true, {
      'versions': {
        'android': '0.8.95',
        'windows': '0.8.95',
        'macos': '0.8.95',
        'pwa': '0.8.95',
      },
    }, currentVersion: '0.8.96');

    expect(result.hasUpdate, isFalse);
  });

  test('subscription URL follows the currently reachable API base', () {
    expect(
      XboardApi.rebaseSubscribeUrl(
        'https://blocked.example/s/token123?flag=meta',
        'https://186.244.223.118',
      ),
      'https://186.244.223.118/s/token123?flag=meta',
    );
  });

  group('signed IP bootstrap', () {
    const publicKey = 'hTHCS3kmmUvYgfaJK9KHsDdar3XVKCTSwaM1BeH0wMA=';
    const signature =
        'j79BMB3uULSbRlR3XfL/xVo3ylEtlKWAGN4FDbmBo5wKoW0QEkdAxm/RePUq1IUMQyNHadKJnlRA6SKeAL9SAw==';
    final now = DateTime.fromMillisecondsSinceEpoch(
      1700000100 * 1000,
      isUtc: true,
    );

    test('accepts an authentic, unexpired HTTPS address list', () async {
      final domains = await verifyBootstrapDocument(
        {
          'data': {
            'version': 1,
            'brand': 'test',
            'issued_at': 1700000000,
            'expires_at': 1700003600,
            'api_domains': ['https://api.example.com'],
            'signature': signature,
          },
        },
        expectedBrand: 'test',
        publicKeyBase64: publicKey,
        now: now,
      );

      expect(domains, ['https://api.example.com']);
    });

    test('rejects a modified address list', () async {
      final domains = await verifyBootstrapDocument(
        {
          'version': 1,
          'brand': 'test',
          'issued_at': 1700000000,
          'expires_at': 1700003600,
          'api_domains': ['https://evil.example.com'],
          'signature': signature,
        },
        expectedBrand: 'test',
        publicKeyBase64: publicKey,
        now: now,
      );

      expect(domains, isEmpty);
    });
  });
}
