// TianTi Core 客户端 API —— 登录、套餐、订单、工单与订阅。
// 文件名和部分类型名暂时保留旧迁移命名，以避免一次性改动 Flutter 页面导入路径；
// 所有运行时请求均直接访问独立 TianTi Core，不再依赖 Xboard。
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

/// 账号当前没有有效套餐，因此服务端不会签发订阅地址。
///
/// 单独区分这个业务状态，调用方才可以安全清除旧节点；普通网络错误、TLS 错误
/// 或服务端临时故障绝不能误删用户当前还能使用的本地配置。
class XboardNoSubscriptionException extends XboardApiException {
  XboardNoSubscriptionException() : super('当前账号没有有效套餐，请先购买套餐后再刷新节点');
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

  bool isExpiredAt(DateTime now) {
    final expiry = expiredAt;
    return expiry != null && expiry <= now.millisecondsSinceEpoch ~/ 1000;
  }
}

class XboardRegistrationTrial {
  final bool enabled;
  final bool claimed;
  final double durationDays;
  final String label;

  const XboardRegistrationTrial({
    required this.enabled,
    required this.claimed,
    required this.durationDays,
    required this.label,
  });

  factory XboardRegistrationTrial.fromMap(Map<dynamic, dynamic> data) =>
      XboardRegistrationTrial(
        enabled: data['enabled'] == true || data['enabled'] == 1,
        claimed: data['claimed'] == true || data['claimed'] == 1,
        durationDays: double.tryParse(data['duration_days']?.toString() ?? '') ?? 1,
        label: data['label']?.toString() ?? '领取注册试用1天',
      );
}

class XboardCheckout {
  final int type;
  final String data;
  final String? payment;
  final String? network;
  final String? address;
  final String? amount;
  final DateTime? expiresAt;
  final String? instructions;

  const XboardCheckout({
    required this.type,
    required this.data,
    this.payment,
    this.network,
    this.address,
    this.amount,
    this.expiresAt,
    this.instructions,
  });

  factory XboardCheckout.fromMap(Map<dynamic, dynamic> data) {
    String? optional(String key) {
      final value = data[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return XboardCheckout(
      type: parseInt(data['type']),
      data: (data['data'] ?? '').toString(),
      payment: optional('payment'),
      network: optional('network'),
      address: optional('address'),
      amount: optional('amount'),
      expiresAt: DateTime.tryParse(optional('expires_at') ?? '')?.toUtc(),
      instructions: optional('instructions'),
    );
  }

  bool get isUsdt => payment == 'usdt_trc20';
  String get qrData => address ?? data;

  Duration remainingAt(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return Duration.zero;
    final remaining = expiry.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }
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
          _u('/api/v1/unified-admin/customer/auth/login'),
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

  Future<void> logout(String authData) async {
    final resp = await http
        .delete(
          _u('/api/v1/unified-admin/customer/auth/session'),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    if (resp.statusCode >= 400 && resp.statusCode != 401) {
      throw XboardApiException('退出登录失败');
    }
  }

  Future<void> sendRegistrationEmailCode(String email) async {
    final resp = await http
        .post(
          _u('/api/v1/unified-admin/customer/auth/email-code'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'email': email}),
        )
        .timeout(timeout);
    _unwrap(resp, badAuthMsg: '验证码发送失败');
  }

  /// 注册并自动登录。email_code 仅当面板开启「邮箱验证」时必填;invite_code 仅当面板要求邀请码时必填。
  /// 成功返回 auth_data+token(与登录同);失败抛 XboardApiException(带后端提示语)。
  /// 端点:POST /api/v1/unified-admin/customer/auth/register。
  Future<XboardLoginResult> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
    String? sliderToken,
    String? companyWebsite,
  }) async {
    final body = <String, dynamic>{'email': email, 'password': password};
    if (inviteCode != null && inviteCode.isNotEmpty) {
      body['invite_code'] = inviteCode;
    }
    if (emailCode != null && emailCode.isNotEmpty) {
      body['email_code'] = emailCode;
    }
    if (sliderToken != null && sliderToken.isNotEmpty) {
      body['slider_token'] = sliderToken;
    }
    body['company_website'] = companyWebsite ?? '';
    final resp = await http
        .post(
          _u('/api/v1/unified-admin/customer/auth/register'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '注册失败');
    final authData = data['auth_data'] as String?;
    final token = data['token'] as String?;
    if (authData == null || token == null) {
      throw XboardApiException('注册响应缺少 auth_data/token');
    }
    return XboardLoginResult(authData, token);
  }

  /// 读取后台实时配置的 Telegram 群地址。
  ///
  /// 未配置、关闭或返回了非 Telegram HTTPS 地址时返回 null，客户端据此隐藏入口。
  Future<String?> getTelegramGroupUrl() async {
    final resp = await http
        .get(
          _u('/api/v1/unified-admin/public/catalog'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(timeout);
    if (resp.statusCode >= 400) return null;

    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      return null;
    }
    return parseTelegramGroupUrl(body);
  }

  static String? parseTelegramGroupUrl(dynamic body) {
    final data = body is Map ? body['data'] : null;
    final telegram = data is Map ? data['telegram'] : null;
    if (telegram is! Map) return null;

    final configured = telegram['configured'];
    if (configured != true && configured != 1 && configured != '1') {
      return null;
    }
    final rawUrl = telegram['group_url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        (uri.host.toLowerCase() != 't.me' &&
            uri.host.toLowerCase() != 'telegram.me') ||
        uri.pathSegments.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  Future<XboardSubscribe> getSubscribe(String authData) async {
    final resp = await http
        .get(
          _u('/api/v1/unified-admin/customer/account'),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '登录已过期,请重新登录');
    final url = data['subscribe_url'] as String?;
    if (url == null || url.isEmpty) {
      throw XboardNoSubscriptionException();
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

  /// 取当前用户的邀请码。TianTi Core 在注册时已为每个账号生成唯一邀请码。
  Future<String> fetchInviteCode(String authData) async {
    final resp = await http
        .get(
          _u('/api/v1/unified-admin/customer/account'),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '登录已过期,请重新登录');
    final code = data['invite_code']?.toString().trim();
    if (code != null && code.isNotEmpty) return code;
    throw XboardApiException('未能获取邀请码');
  }

  Future<XboardRegistrationTrial> fetchRegistrationTrial(
    String authData,
  ) async {
    final resp = await http
        .get(
          _u('/api/v1/unified-admin/customer/registration-trial'),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    return XboardRegistrationTrial.fromMap(
      _unwrap(resp, badAuthMsg: '登录已过期,请重新登录'),
    );
  }

  Future<XboardRegistrationTrial> claimRegistrationTrial(
    String authData,
  ) async {
    final resp = await http
        .post(
          _u('/api/v1/unified-admin/customer/registration-trial/claim'),
          headers: _jsonAuth(authData),
          body: '{}',
        )
        .timeout(timeout);
    return XboardRegistrationTrial.fromMap(
      _unwrap(resp, badAuthMsg: '登录已过期,请重新登录'),
    );
  }

  // ============ 订单 / 套餐 / 工单 / 支付(全部原生,替代会崩的 webview)============

  /// 我的订单列表。金额字段单位=分。
  Future<List<Map<String, dynamic>>> fetchOrders(String authData) =>
      _getList('/api/v1/unified-admin/customer/orders', authData);

  /// 可购套餐列表。价格字段单位=分。
  Future<List<Map<String, dynamic>>> fetchPlans(String authData) =>
      _getList('/api/v1/unified-admin/customer/plans', authData);

  /// 工单列表。
  Future<List<Map<String, dynamic>>> fetchTickets(String authData) =>
      _getList('/api/v1/unified-admin/customer/support/tickets', authData);

  /// 单个工单详情（含对话）。
  Future<Map<String, dynamic>> fetchTicketDetail(
    String authData,
    String id,
  ) async {
    final resp = await http
        .get(
          _u(
            '/api/v1/unified-admin/customer/support/tickets/${Uri.encodeComponent(id)}',
          ),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '登录已过期,请重新登录');
    final messages = data['message'];
    if (messages is List) {
      for (final item in messages) {
        if (item is! Map || item['type'] != 'image') continue;
        final path = item['attachment_url']?.toString() ?? '';
        if (path.isEmpty) continue;
        final url = path.startsWith('http')
            ? path
            : '${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path';
        item['message'] = '[img]$url';
      }
    }
    return data;
  }

  /// 新建工单。
  Future<void> createTicket(
    String authData, {
    required String subject,
    required String message,
    int level = 1,
  }) async {
    final resp = await http
        .post(
          _u('/api/v1/unified-admin/customer/support/tickets'),
          headers: _jsonAuth(authData),
          body: jsonEncode({
            'subject': subject,
            'level': level,
            'message': message,
          }),
        )
        .timeout(timeout);
    _expectTrue(resp, failMsg: '工单创建失败');
  }

  /// 回复工单。已关闭时 Core 会返回业务错误。
  Future<void> replyTicket(String authData, String id, String message) async {
    final resp = await http
        .post(
          _u(
            '/api/v1/unified-admin/customer/support/tickets/${Uri.encodeComponent(id)}/reply',
          ),
          headers: _jsonAuth(authData),
          body: jsonEncode({'message': message}),
        )
        .timeout(timeout);
    _expectTrue(resp, failMsg: '回复失败');
  }

  /// 关闭工单。
  Future<void> closeTicket(String authData, String id) async {
    final resp = await http
        .post(
          _u(
            '/api/v1/unified-admin/customer/support/tickets/${Uri.encodeComponent(id)}/close',
          ),
          headers: _jsonAuth(authData),
          body: '{}',
        )
        .timeout(timeout);
    _expectTrue(resp, failMsg: '关闭工单失败');
  }

  /// 下单。period 传价格键，如 month_price。
  /// 返回 trade_no(data 为字符串)。若已有未支付订单会抛错。
  Future<String> createOrder(
    String authData, {
    required int planId,
    required String period,
  }) async {
    final resp = await http
        .post(
          _u('/api/v1/unified-admin/customer/orders'),
          headers: _jsonAuth(authData),
          body: jsonEncode({'plan_id': planId, 'period': period}),
        )
        .timeout(timeout);
    final data = _unwrap(resp, badAuthMsg: '登录已过期,请重新登录');
    final tradeNo = data['trade_no']?.toString();
    if (tradeNo == null || tradeNo.isEmpty) {
      throw XboardApiException('下单响应缺少订单号');
    }
    return tradeNo;
  }

  /// 支付方式列表。
  Future<List<Map<String, dynamic>>> getPaymentMethods(String authData) =>
      _getList('/api/v1/unified-admin/customer/payment-methods', authData);

  /// 结账。
  /// 返回裸 {type,data}(不带 envelope):type=1 外部支付URL(浏览器打开);
  /// type=0 二维码串(原生渲染);type=-1 免费订单已支付(data=true)。
  Future<XboardCheckout> checkout(
    String authData,
    String tradeNo,
    int method,
  ) async {
    final resp = await http
        .post(
          _u('/api/v1/unified-admin/customer/orders/checkout'),
          headers: _jsonAuth(authData),
          body: jsonEncode({'trade_no': tradeNo, 'method': method}),
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw XboardApiException('登录已过期,请重新登录');
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw XboardApiException('结账响应异常');
    }
    if (resp.statusCode >= 400) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '结账失败',
      );
    }
    final data = body is Map ? body['data'] : null;
    if (data is Map && data.containsKey('type')) {
      return XboardCheckout.fromMap(data);
    }
    throw XboardApiException(
      (body is Map ? body['message'] : null)?.toString() ?? '结账失败',
    );
  }

  /// 轮询订单状态（data 为整数）。
  /// 0 待支付 / 1 开通中 / 2 已取消 / 3 已完成 / 4 已折抵。
  Future<int> checkOrderStatus(String authData, String tradeNo) async {
    final resp = await http
        .get(
          _u(
            '/api/v1/unified-admin/customer/orders/check',
          ).replace(queryParameters: {'trade_no': tradeNo}),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    return _int(_unwrapScalar(resp, badAuthMsg: '登录已过期,请重新登录'));
  }

  /// 给订阅地址补上 ?flag=meta，强制 TianTi Core 输出 mihomo/Clash.Meta YAML，
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

  /// 保留兼容调用签名，但绝不把订阅专用域名改写为 API 通信域名。
  /// TianTi Core 会严格校验订阅 Host，改写后按设计会返回 404。
  static String rebaseSubscribeUrl(String subscribeUrl, String baseUrl) {
    return subscribeUrl;
  }

  Map<String, dynamic> _unwrap(
    http.Response resp, {
    required String badAuthMsg,
  }) {
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
    if (resp.statusCode >= 400) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '请求失败',
      );
    }
    if (body is! Map || body['data'] == null) {
      final msg = (body is Map ? body['message'] : null) ?? '请求失败';
      throw XboardApiException(msg.toString());
    }
    final d = body['data'];
    return d is Map<String, dynamic> ? d : Map<String, dynamic>.from(d as Map);
  }

  Map<String, String> _jsonAuth(String authData) => {
    'Authorization': authData,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<List<Map<String, dynamic>>> _getList(
    String path,
    String authData,
  ) async {
    final resp = await http
        .get(
          _u(path),
          headers: {'Authorization': authData, 'Accept': 'application/json'},
        )
        .timeout(timeout);
    return _unwrapList(resp, badAuthMsg: '登录已过期,请重新登录');
  }

  /// data 为「数组」时解包(订单/套餐/工单列表/支付方式)。现有 _unwrap 只认 Map,会崩。
  List<Map<String, dynamic>> _unwrapList(
    http.Response resp, {
    required String badAuthMsg,
  }) {
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
    if (resp.statusCode >= 400) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '请求失败',
      );
    }
    if (body is! Map || body['data'] is! List) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '请求失败',
      );
    }
    return (body['data'] as List)
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map),
        )
        .toList();
  }

  /// data 为「标量」时解包(下单返回 trade_no 字符串、查单返回状态整数)。
  dynamic _unwrapScalar(http.Response resp, {required String badAuthMsg}) {
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
    if (resp.statusCode >= 400) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '请求失败',
      );
    }
    if (body is! Map || !body.containsKey('data')) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '请求失败',
      );
    }
    return body['data'];
  }

  /// 期望 data==true 的写操作(工单 save/reply/close)。失败抛后端 message。
  void _expectTrue(http.Response resp, {required String failMsg}) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw XboardApiException('登录已过期,请重新登录');
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw XboardApiException(failMsg);
    }
    if (resp.statusCode >= 400) {
      throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? failMsg,
      );
    }
    if (body is Map && (body['data'] == true || body['data'] == 1)) return;
    throw XboardApiException(
      (body is Map ? body['message'] : null)?.toString() ?? failMsg,
    );
  }
}
