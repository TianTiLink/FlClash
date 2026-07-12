// Reseller 分销插件 —— 客户端 API。
// 对接后端 plugins/Reseller 的接口(全部前缀 /api/v1/reseller):
//   GET  /summary             身份+余额+汇总(需登录)
//   GET  /downlines?level&page 某层下线(需登录)
//   GET  /records?type&page    收益明细(需登录)
//   POST /withdraw             提交提现(需登录,仅代理)   body {amount, usdt_address}
//   GET  /withdraw/history     提现记录(需登录)
//   GET  /popup                启动弹窗(游客,无需登录)
//
// 依赖 package:http(pubspec 已有)。认证头复用 XboardAuth 的 authData("Bearer xxx")。

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'xboard_api.dart'; // 复用 XboardApiException

class ResellerApi {
  final String baseUrl;
  final String? authData; // "Bearer xxx";popup 接口可为 null
  final Duration timeout;

  ResellerApi(this.baseUrl, {this.authData, this.timeout = const Duration(seconds: 20)});

  Uri _u(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (authData != null && authData!.isNotEmpty) 'Authorization': authData!,
      };

  Future<Map<String, dynamic>> summary() => _get('/api/v1/reseller/summary');

  Future<Map<String, dynamic>> downlines({int level = 1, int page = 1}) =>
      _get('/api/v1/reseller/downlines?level=$level&page=$page');

  Future<Map<String, dynamic>> records({String type = 'commission', int page = 1}) =>
      _get('/api/v1/reseller/records?type=$type&page=$page');

  Future<Map<String, dynamic>> withdrawHistory({int page = 1}) =>
      _get('/api/v1/reseller/withdraw/history?page=$page');

  Future<Map<String, dynamic>> popup() => _get('/api/v1/reseller/popup');

  /// 提交提现。amount 单位 USDT;address 为 TRC20 地址。成功返回 data,失败抛 XboardApiException(带后端提示语)。
  Future<Map<String, dynamic>> submitWithdraw({
    required double amount,
    required String address,
  }) async {
    final resp = await http
        .post(
          _u('/api/v1/reseller/withdraw'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'amount': amount, 'usdt_address': address}),
        )
        .timeout(timeout);
    return _unwrap(resp);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await http.get(_u(path), headers: _headers).timeout(timeout);
    return _unwrap(resp);
  }

  Map<String, dynamic> _unwrap(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw XboardApiException('登录已过期或无权限,请重新登录');
    }
    if (resp.statusCode >= 500) {
      throw XboardApiException('服务器错误(${resp.statusCode})');
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw XboardApiException('响应不是合法 JSON(检查面板地址)');
    }
    if (body is! Map) {
      throw XboardApiException('请求失败');
    }
    if (body['status'] == 'fail') {
      throw XboardApiException((body['message'] ?? '请求失败').toString());
    }
    final d = body['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return <String, dynamic>{};
  }
}
