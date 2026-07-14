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

  /// 注册并自动登录。email_code 仅当面板开启「邮箱验证」时必填;invite_code 仅当面板要求邀请码时必填。
  /// 成功返回 auth_data+token(与登录同);失败抛 XboardApiException(带后端提示语)。
  /// 端点:POST /api/v1/passport/auth/register  body {email,password,invite_code?,email_code?}
  Future<XboardLoginResult> register(
    String email,
    String password, {
    String? inviteCode,
    String? emailCode,
  }) async {
    final body = <String, dynamic>{'email': email, 'password': password};
    if (inviteCode != null && inviteCode.isNotEmpty) body['invite_code'] = inviteCode;
    if (emailCode != null && emailCode.isNotEmpty) body['email_code'] = emailCode;
    final resp = await http
        .post(
          _u('/api/v1/passport/auth/register'),
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

  /// 发送邮箱验证码(面板开启「邮箱验证」时用)。端点:POST /api/v1/passport/comm/sendEmailVerify {email}。
  Future<void> sendEmailVerify(String email) async {
    final resp = await http
        .post(
          _u('/api/v1/passport/comm/sendEmailVerify'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'email': email}),
        )
        .timeout(timeout);
    if (resp.statusCode == 429) {
      throw XboardApiException('发送过于频繁,请稍后再试');
    }
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw XboardApiException('发送验证码失败(检查面板地址)');
    }
    // 成功 data:true;失败给 message。
    if (body is Map && (body['data'] == true || body['data'] == 1)) return;
    final msg = (body is Map ? body['message'] : null) ?? '发送验证码失败';
    throw XboardApiException(msg.toString());
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

  // ============ 订单 / 套餐 / 工单 / 支付(全部原生,替代会崩的 webview)============

  /// 我的订单列表。GET /api/v1/user/order/fetch(data 为数组)。金额字段单位=分。
  Future<List<Map<String, dynamic>>> fetchOrders(String authData) =>
      _getList('/api/v1/user/order/fetch', authData);

  /// 可购套餐列表。GET /api/v1/user/plan/fetch(data 为数组)。价格字段单位=分。
  Future<List<Map<String, dynamic>>> fetchPlans(String authData) =>
      _getList('/api/v1/user/plan/fetch', authData);

  /// 工单列表。GET /api/v1/user/ticket/fetch(不带参数,data 为数组)。
  Future<List<Map<String, dynamic>>> fetchTickets(String authData) =>
      _getList('/api/v1/user/ticket/fetch', authData);

  /// 单个工单详情(含对话)。GET /api/v1/user/ticket/fetch?id=<id>(data 为对象,含 message 数组)。
  Future<Map<String, dynamic>> fetchTicketDetail(
      String authData, int id) async {
    final resp = await http.get(
      _u('/api/v1/user/ticket/fetch').replace(queryParameters: {'id': '$id'}),
      headers: {'Authorization': authData, 'Accept': 'application/json'},
    ).timeout(timeout);
    return _unwrap(resp, badAuthMsg: '登录已过期,请重新登录');
  }

  /// 新建工单。POST /api/v1/user/ticket/save {subject,level(0|1|2),message}。
  Future<void> createTicket(String authData,
      {required String subject, required String message, int level = 1}) async {
    final resp = await http
        .post(_u('/api/v1/user/ticket/save'),
            headers: _jsonAuth(authData),
            body: jsonEncode(
                {'subject': subject, 'level': level, 'message': message}))
        .timeout(timeout);
    _expectTrue(resp, failMsg: '工单创建失败');
  }

  /// 回复工单。POST /api/v1/user/ticket/reply {id,message}。已关闭/需等待客服回复会报错。
  Future<void> replyTicket(String authData, int id, String message) async {
    final resp = await http
        .post(_u('/api/v1/user/ticket/reply'),
            headers: _jsonAuth(authData),
            body: jsonEncode({'id': id, 'message': message}))
        .timeout(timeout);
    _expectTrue(resp, failMsg: '回复失败');
  }

  /// 关闭工单。POST /api/v1/user/ticket/close {id}。
  Future<void> closeTicket(String authData, int id) async {
    final resp = await http
        .post(_u('/api/v1/user/ticket/close'),
            headers: _jsonAuth(authData), body: jsonEncode({'id': id}))
        .timeout(timeout);
    _expectTrue(resp, failMsg: '关闭工单失败');
  }

  /// 下单。POST /api/v1/user/order/save {plan_id,period}。period 传价格键,如 'month_price'。
  /// 返回 trade_no(data 为字符串)。若已有未支付订单会抛错。
  Future<String> createOrder(String authData,
      {required int planId, required String period}) async {
    final resp = await http
        .post(_u('/api/v1/user/order/save'),
            headers: _jsonAuth(authData),
            body: jsonEncode({'plan_id': planId, 'period': period}))
        .timeout(timeout);
    return _unwrapScalar(resp, badAuthMsg: '登录已过期,请重新登录').toString();
  }

  /// 支付方式列表。GET /api/v1/user/order/getPaymentMethod(data 为数组:{id,name,payment,...})。
  Future<List<Map<String, dynamic>>> getPaymentMethods(String authData) =>
      _getList('/api/v1/user/order/getPaymentMethod', authData);

  /// 结账。POST /api/v1/user/order/checkout {trade_no,method}。
  /// 返回裸 {type,data}(不带 envelope):type=1 外部支付URL(浏览器打开);
  /// type=0 二维码串(原生渲染);type=-1 免费订单已支付(data=true)。
  Future<({int type, String data})> checkout(
      String authData, String tradeNo, int method) async {
    final resp = await http
        .post(_u('/api/v1/user/order/checkout'),
            headers: _jsonAuth(authData),
            body: jsonEncode({'trade_no': tradeNo, 'method': method}))
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
    if (body is Map && body.containsKey('type')) {
      return (type: _int(body['type']), data: (body['data'] ?? '').toString());
    }
    throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? '结账失败');
  }

  /// 轮询订单状态。GET /api/v1/user/order/check?trade_no=(data 为整数)。
  /// 0 待支付 / 1 开通中 / 2 已取消 / 3 已完成 / 4 已折抵。
  Future<int> checkOrderStatus(String authData, String tradeNo) async {
    final resp = await http.get(
      _u('/api/v1/user/order/check')
          .replace(queryParameters: {'trade_no': tradeNo}),
      headers: {'Authorization': authData, 'Accept': 'application/json'},
    ).timeout(timeout);
    return _int(_unwrapScalar(resp, badAuthMsg: '登录已过期,请重新登录'));
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

  Map<String, String> _jsonAuth(String authData) => {
        'Authorization': authData,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<List<Map<String, dynamic>>> _getList(
      String path, String authData) async {
    final resp = await http.get(
      _u(path),
      headers: {'Authorization': authData, 'Accept': 'application/json'},
    ).timeout(timeout);
    return _unwrapList(resp, badAuthMsg: '登录已过期,请重新登录');
  }

  /// data 为「数组」时解包(订单/套餐/工单列表/支付方式)。现有 _unwrap 只认 Map,会崩。
  List<Map<String, dynamic>> _unwrapList(http.Response resp,
      {required String badAuthMsg}) {
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
    if (body is! Map || body['data'] is! List) {
      throw XboardApiException(
          (body is Map ? body['message'] : null)?.toString() ?? '请求失败');
    }
    return (body['data'] as List)
        .map((e) =>
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))
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
    if (body is! Map || !body.containsKey('data')) {
      throw XboardApiException(
          (body is Map ? body['message'] : null)?.toString() ?? '请求失败');
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
    if (body is Map && (body['data'] == true || body['data'] == 1)) return;
    throw XboardApiException(
        (body is Map ? body['message'] : null)?.toString() ?? failMsg);
  }
}
