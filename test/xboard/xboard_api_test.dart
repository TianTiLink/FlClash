import 'package:fl_clash/xboard/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Telegram group configuration', () {
    test('returns the configured Telegram HTTPS URL', () {
      final url = XboardApi.parseTelegramGroupUrl({
        'data': {
          'telegram': {
            'configured': true,
            'group_url': 'https://t.me/vpnYQ1688',
          },
        },
      });

      expect(url, 'https://t.me/vpnYQ1688');
    });

    test('hides the entry when the group is disabled or missing', () {
      expect(
        XboardApi.parseTelegramGroupUrl({
          'data': {
            'telegram': {
              'configured': false,
              'group_url': 'https://t.me/vpnYQ1688',
            },
          },
        }),
        isNull,
      );
      expect(
        XboardApi.parseTelegramGroupUrl({'data': {}}),
        isNull,
      );
    });

    test('rejects non-Telegram and non-HTTPS URLs', () {
      expect(
        XboardApi.parseTelegramGroupUrl({
          'data': {
            'telegram': {
              'configured': true,
              'group_url': 'https://example.com/group',
            },
          },
        }),
        isNull,
      );
      expect(
        XboardApi.parseTelegramGroupUrl({
          'data': {
            'telegram': {
              'configured': true,
              'group_url': 'http://t.me/group',
            },
          },
        }),
        isNull,
      );
    });
  });
}
