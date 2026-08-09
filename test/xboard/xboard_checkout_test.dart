import 'package:flutter_test/flutter_test.dart';
import 'package:fl_clash/xboard/xboard_api.dart';

void main() {
  group('XboardCheckout', () {
    test('保留 USDT 结构化支付信息并计算剩余时间', () {
      final checkout = XboardCheckout.fromMap({
        'type': 0,
        'data': '请使用 TRC20 网络支付',
        'payment': 'usdt_trc20',
        'network': 'TRC20',
        'address': 'TTestAddressForCheckout123456789',
        'amount': '1.234567',
        'expires_at': '2026-08-09T02:30:00Z',
        'instructions': '金额必须完全一致',
      });

      expect(checkout.type, 0);
      expect(checkout.isUsdt, isTrue);
      expect(checkout.network, 'TRC20');
      expect(checkout.address, 'TTestAddressForCheckout123456789');
      expect(checkout.qrData, 'TTestAddressForCheckout123456789');
      expect(checkout.amount, '1.234567');
      expect(checkout.instructions, '金额必须完全一致');
      expect(
        checkout.remainingAt(DateTime.parse('2026-08-09T02:29:00Z')),
        const Duration(minutes: 1),
      );
      expect(
        checkout.remainingAt(DateTime.parse('2026-08-09T02:31:00Z')),
        Duration.zero,
      );
    });

    test('兼容旧式二维码支付返回', () {
      final checkout = XboardCheckout.fromMap({
        'type': 0,
        'data': 'legacy-qr-payload',
        'expires_at': 'invalid-date',
      });

      expect(checkout.isUsdt, isFalse);
      expect(checkout.qrData, 'legacy-qr-payload');
      expect(checkout.expiresAt, isNull);
      expect(checkout.remainingAt(DateTime.now()), Duration.zero);
    });
  });
}
