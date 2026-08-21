import 'dart:ffi';

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

  test('endpoint result reads the Core force-update switch', () {
    final enabled = TtEndpointResult(
      'https://example.com',
      true,
      {'client_version': '0.8.110', 'update_force': true},
      currentVersion: '0.8.109',
    );
    final disabled = TtEndpointResult(
      'https://example.com',
      true,
      {'client_version': '0.8.110', 'update_force': false},
      currentVersion: '0.8.109',
    );

    expect(enabled.hasUpdate, isTrue);
    expect(enabled.updateForce, isTrue);
    expect(disabled.updateForce, isFalse);
  });

  group('platform update artifact selection', () {
    final config = <String, dynamic>{
      'downloads': {
        'android': '/dl/TianTiLink-android.apk?v=0.8.115',
        'android_v7a': '/dl/TianTiLink-android-armeabi-v7a.apk?v=0.8.115',
        'android_x86': '/dl/TianTiLink-android-x86_64.apk?v=0.8.115',
        'windows': '/dl/TianTiLink-windows.exe?v=0.8.115',
        'windows_portable': '/dl/TianTiLink-windows-portable.zip?v=0.8.115',
        'macos': '/dl/TianTiLink-macos.zip?v=0.8.115',
        'macos_intel': '/dl/TianTiLink-macos-intel.zip?v=0.8.115',
      },
      // Deliberately use the former alphabetical order. Exact keyed downloads
      // must win over the first same-platform item in this list.
      'client_downloads': [
        {
          'name': 'TianTiLink-android-armeabi-v7a.apk',
          'platform': 'Android',
          'download_url': '/wrong-v7a.apk',
        },
        {
          'name': 'TianTiLink-windows-portable.zip',
          'platform': 'Windows',
          'download_url': '/wrong-portable.zip',
        },
        {
          'name': 'TianTiLink-macos-intel.zip',
          'platform': 'macOS',
          'download_url': '/wrong-intel.zip',
        },
      ],
    };

    String select(String platform, Abi abi) => selectClientDownloadUrl(
      config: config,
      activeBase: 'https://api.example.com',
      platform: platform,
      abi: abi,
    )!;

    test('Windows always selects the Inno installer', () {
      expect(
        select('windows', Abi.windowsX64),
        'https://api.example.com/dl/TianTiLink-windows.exe?v=0.8.115',
      );
    });

    test('Android selects the package matching its CPU ABI', () {
      expect(
        select('android', Abi.androidArm64),
        endsWith('/dl/TianTiLink-android.apk?v=0.8.115'),
      );
      expect(
        select('android', Abi.androidArm),
        endsWith('/dl/TianTiLink-android-armeabi-v7a.apk?v=0.8.115'),
      );
      expect(
        select('android', Abi.androidX64),
        endsWith('/dl/TianTiLink-android-x86_64.apk?v=0.8.115'),
      );
    });

    test('macOS separates Apple Silicon and Intel packages', () {
      expect(
        select('macos', Abi.macosArm64),
        endsWith('/dl/TianTiLink-macos.zip?v=0.8.115'),
      );
      expect(
        select('macos', Abi.macosX64),
        endsWith('/dl/TianTiLink-macos-intel.zip?v=0.8.115'),
      );
    });

    test('canonical filename fallback ignores wrong first platform item', () {
      final fallback = Map<String, dynamic>.from(config)..remove('downloads');
      fallback['client_downloads'] = [
        {
          'name': 'TianTiLink-windows-portable.zip',
          'platform': 'Windows',
          'download_url': '/wrong-portable.zip',
        },
        {
          'name': 'TianTiLink-windows.exe',
          'platform': 'Windows',
          'download_url': '/dl/TianTiLink-windows.exe',
        },
      ];
      expect(
        selectClientDownloadUrl(
          config: fallback,
          activeBase: 'https://api.example.com',
          platform: 'windows',
          abi: Abi.windowsX64,
        ),
        'https://api.example.com/dl/TianTiLink-windows.exe',
      );
    });
  });

  test('subscription URL keeps the dedicated subscription host', () {
    expect(
      XboardApi.rebaseSubscribeUrl(
        'https://blocked.example/s/token123?flag=meta',
        'https://186.244.223.118',
      ),
      'https://blocked.example/s/token123?flag=meta',
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
