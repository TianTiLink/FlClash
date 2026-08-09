import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/xboard/reseller_api.dart';
import 'package:fl_clash/xboard/xboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('withdrawal business validation errors are never reported as success', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handling = server.first.then((request) async {
      expect(request.method, 'POST');
      request.response.statusCode = 422;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': '提现金额低于最低限额。'}));
      await request.response.close();
    });

    final api = ResellerApi(
      'http://${server.address.host}:${server.port}',
      authData: 'Bearer test',
    );

    await expectLater(
      api.submitWithdraw(
        amount: 1,
        address: 'TFc7i7Q5C5fpbhV5kqKdxxWC5T4yUX3SGU',
      ),
      throwsA(
        isA<XboardApiException>().having(
          (error) => error.message,
          'message',
          contains('最低限额'),
        ),
      ),
    );
    await handling;
    await server.close(force: true);
  });
}
