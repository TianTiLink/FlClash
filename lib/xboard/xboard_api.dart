// Xboard 客户端 API —— 登录 + 取订阅。
// 端点全部对照 cedar2025/Xboard 源码核实:
//   登录   POST /api/v1/passport/auth/login   body {email,password} -> data.{auth_data,token}
//   取订阅 GET  /api/v1/user/getSubscribe      header Authorization: <auth_data> -> data.subscribe_url
//   下配置 GET  {subscribe_url}?flag=meta       -> mihomo/Clash.Meta YAML
//
// 依赖:package:http(在 pubspec.yaml 的 dependencies 里加 `http: ^1.2.0`)。
// 若想复用 FlClash 自带的 dio 请求器,可把下面 http 调用替换为它的 request。

import 'dart:convert';
import 'package:http/http.dart' as http;

class XboardApiException implements Exception {
  final String message;
  XboardApiException(this.message);
  @override
  String toString() => message;
}

class XboardLoginResult {
  /// 形如 "Bearer xxxxx",直接作为 Authorization 头。
  final String authData;

  /// 用户持久订阅 token(备用)。
  final String token;

  XboardLoginResult(this.authData, this.token);
}

class XboardSubscribe {
  final String subscribeUrl;
  final int upload; // 已用上行(字节)
  final int download; // 已用下行(字节)
  final int transferEnable; // 套餐总流量(字节)
  final int? expiredAt; // 到期 unix 秒,null=永不过期
  final String? planName;

  XboardSubscribe({
    required this.subscribeUrl,
    this.upload = 0,
    this.download = 0,
    this.transferEnable = 0,
    this.expiredAt,
    this.planName,
  });
}

class XboardApi {
  /// 面板地址,如 https://panel.example.com
  final String baseUrl;
  final Duration timeout;

  XboardApi(this.baseUrl, {this.timeout = const Duration(seconds: 20)});

  Uri _u(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<XboardLoginResult> login(String email, String password) async {
    final resp = await http
        .post(
          _u('/api/v1/passport/auth/login'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '账号或密码错误');
    final authData = data['auth_data'] as String?;
    final token = data['token'] as String?;
    if (authData == null || token == null) {
      throw XboardApiException('登录响应缺少 auth_data/token');
    }
    return XboardLoginResult(authData, token);
  }

  Future<XboardSubscribe> getSubscribe(String authData) async {
    final resp = await http.get(
      _u('/api/v1/user/getSubscribe'),
      headers: {'Authorization': authData, 'Accept': 'application/json'},
    ).timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '登录已过期,请重新登录');
    final url = data['subscribe_url'] as String?;
    if (url == null || url.isEmpty) {
      throw XboardApiException('未取得订阅地址(账号可能未购买套餐)');
    }
    final plan = data['plan'];
    return XboardSubscribe(
      subscribeUrl: url,
      upload: _int(data['u']),
      download: _int(data['d']),
      transferEnable: _int(data['transfer_enable']),
      expiredAt: data['expired_at'] == null ? null : _int(data['expired_at']),
      planName: plan is Map ? plan['name']?.toString() : null,
    );
  }

  /// 取当前用户的邀请码(推广码)。没有则自动生成一个再取。返回邀请码字符串。
  /// 邀请链接由调用方拼:"<面板>/#/register?code=<邀请码>"。
  /// 端点对照 Xboard 原生:GET /api/v1/user/invite/fetch(data.codes[].code)、
  ///           POST /api/v1/user/invite/save(生成一个,返回体不解析)。
  Future<String> fetchInviteCode(String authData) async {
    final headers = {'Authorization': authData, 'Accept': 'application/json'};
    String? pick(Map<String, dynamic> data) {
      final codes = data['codes'];
      if (codes is List && codes.isNotEmpty) {
        final first = codes.first;
        final c = first is Map ? first['code']?.toString() : null;
        if (c != null && c.isNotEmpty) return c;
      }
      return null;
    }

    var resp = await http
        .get(_u('/api/v1/user/invite/fetch'), headers: headers)
        .timeout(timeout);
    var code = pick(_unwrap(resp, badAuthMsg: '登录已过期,请重新登录'));
    if (code != null) return code;

    // 还没有邀请码 → 先生成一个(返回可能是 true,不走 _unwrap),再取一次。
    await http
        .post(_u('/api/v1/user/invite/save'), headers: headers)
        .timeout(timeout);
    resp = await http
        .get(_u('/api/v1/user/invite/fetch'), headers: headers)
        .timeout(timeout);
    code = pick(_unwrap(resp, badAuthMsg: '登录已过期,请重新登录'));
    if (code != null) return code;
    throw XboardApiException('未能获取邀请码');
  }

  /// 给订阅地址补上 ?flag=meta,强制 Xboard 输出 mihomo/Clash.Meta 格式,
  /// 不受客户端 User-Agent 影响。
  static String toMihomoUrl(String subscribeUrl) {
    final uri = Uri.parse(subscribeUrl);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['flag'] = 'meta';
    return uri.replace(queryParameters: qp).toString();
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Map<String, dynamic> _unwrap(http.Response resp, {required String badAuthMsg}) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw XboardApiException(badAuthMsg);
    }
    if (resp.statusCode >= 500) {
      throw XboardApiException('服务器错误(${resp.statusCode})');
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw XboardApiException('响应不是合法 JSON(检查面板地址是否正确)');
    }
    if (body is! Map || body['data'] == null) {
      final msg = (body is Map ? body['message'] : null) ?? '请求失败';
      throw XboardApiException(msg.toString());
    }
    final d = body['data'];
    return d is Map<String, dynamic> ? d : Map<String, dynamic>.from(d as Map);
  }
}
