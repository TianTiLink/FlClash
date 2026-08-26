// 登录态 + 会话持久化(Riverpod v3 手写 Notifier,无需 build_runner 代码生成)。
//
// 存储分两处:
//   - 敏感的登录凭据(auth_data)→ flutter_secure_storage(系统级加密:iOS Keychain /
//     Android Keystore)。依赖:pubspec.yaml 加 `flutter_secure_storage: ^10.3.1`
//     (必须 ^10.3.1,不能 ^9——当前 FlClash 依赖 win32^6,^9 会拽进 win32^5 致 pub get 冲突;
//     v10 的 read/write/delete 用法与 v9 相同,本文件无需改动)。
//   - 非敏感的展示用字段(面板地址、邮箱、订阅地址)→ shared_preferences 明文即可。
//
// 登出会调用 TianTi Core 的当前会话吊销接口，再清理本机安全存储。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_localizations.dart';
import 'xboard_api.dart';

const _secureStorage = FlutterSecureStorage();

typedef XboardApiFactory = XboardApi Function(String baseUrl);

/// Test seam for authentication/subscription boundary behavior.
XboardApiFactory xboardApiFactory = XboardApi.new;

/// 客户端默认通信地址(硬编码兜底,也是默认参数用的常量)。登录页已隐藏地址输入框。
/// 用 API 专用域名(和官网/导航分开:官网被举报封了不连累 App 登录/订阅)。
/// 换域名时改这里、重编即可。前提:该域名有有效 HTTPS 证书且反代到面板。
const String kDefaultPanelUrl = 'https://pafslnnalksdf.xyz';

/// 当前生效的通信地址(可变):启动时 resolveEndpoint() 探测候选 API 地址后写入这里,
/// 逐个探测用第一个能通的(防封 failover)。所有运行时 API 调用读这个,不读上面的 const。
/// 探测失败/域名没解析时保持默认 = 现有行为,安全降级。
String ttActiveBase = kDefaultPanelUrl;

const _kPanelUrl = 'tianti_api_base';
const _kEmail = 'tianti_email';
const _kAuth = 'tianti_auth_token';
const _kSub = 'tianti_subscribe_url';
const _notProvided = Object();

class XboardLoginOutcome {
  final String? mihomoUrl;
  final String? syncWarning;

  const XboardLoginOutcome({this.mihomoUrl, this.syncWarning});
}

class XboardAuthState {
  final bool restored; // 是否已从磁盘读过(避免启动闪现登录页)
  final bool loggedIn;
  final String panelUrl;
  final String email;
  final String? authData;
  final String? subscribeUrl;

  const XboardAuthState({
    this.restored = false,
    this.loggedIn = false,
    this.panelUrl = kDefaultPanelUrl,
    this.email = '',
    this.authData,
    this.subscribeUrl,
  });

  XboardAuthState copyWith({
    bool? restored,
    bool? loggedIn,
    String? panelUrl,
    String? email,
    Object? authData = _notProvided,
    Object? subscribeUrl = _notProvided,
  }) {
    return XboardAuthState(
      restored: restored ?? this.restored,
      loggedIn: loggedIn ?? this.loggedIn,
      panelUrl: panelUrl ?? this.panelUrl,
      email: email ?? this.email,
      authData: identical(authData, _notProvided)
          ? this.authData
          : authData as String?,
      subscribeUrl: identical(subscribeUrl, _notProvided)
          ? this.subscribeUrl
          : subscribeUrl as String?,
    );
  }
}

final xboardAuthProvider = NotifierProvider<XboardAuth, XboardAuthState>(
  XboardAuth.new,
);

class XboardAuth extends Notifier<XboardAuthState> {
  @override
  XboardAuthState build() => const XboardAuthState();

  /// 启动时调用一次:从磁盘恢复会话。
  Future<void> restore() async {
    final sp = await SharedPreferences.getInstance();
    final auth = await _secureStorage.read(key: _kAuth);
    state = XboardAuthState(
      restored: true,
      loggedIn: auth != null,
      panelUrl: sp.getString(_kPanelUrl) ?? ttActiveBase,
      email: sp.getString(_kEmail) ?? '',
      authData: auth,
      subscribeUrl: sp.getString(_kSub),
    );
  }

  /// 登录先独立确认并持久化账号认证，再尝试同步订阅。
  /// 后续账号/订阅接口临时失败不会被重新标记为密码错误，也不会把用户挡在登录页。
  Future<XboardLoginOutcome> login({
    required String panelUrl,
    required String email,
    required String password,
  }) async {
    final api = xboardApiFactory(panelUrl);
    final res = await api.login(email, password);

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPanelUrl, panelUrl);
    await sp.setString(_kEmail, email);
    await _secureStorage.write(key: _kAuth, value: res.authData);
    await sp.remove(_kSub);

    state = state.copyWith(
      loggedIn: true,
      panelUrl: panelUrl,
      email: email,
      authData: res.authData,
      subscribeUrl: null,
    );

    String? mihomoUrl;
    String? subscribeUrl;
    try {
      final sub = await api.getSubscribe(res.authData);
      subscribeUrl = sub.subscribeUrl;
      mihomoUrl = XboardApi.toMihomoUrl(subscribeUrl);
      await sp.setString(_kSub, subscribeUrl);
    } on XboardNoSubscriptionException {
      // 账号未购买套餐 / 暂无订阅:不算登录失败,让用户先进 App 再去充值。
      await sp.remove(_kSub);
    } catch (error) {
      final detail = error is XboardApiException
          ? error.message
          : '网络暂时不可用，请稍后重试';
      return XboardLoginOutcome(
        syncWarning: currentAppLocalizations.accountLoginSyncFailed(detail),
      );
    }

    state = state.copyWith(
      loggedIn: true,
      panelUrl: panelUrl,
      email: email,
      authData: res.authData,
      subscribeUrl: subscribeUrl,
    );
    return XboardLoginOutcome(mihomoUrl: mihomoUrl);
  }

  /// 注册并自动登录。与 login 一样持久化凭据、尝试拉订阅;新号一般还没套餐→返回 null,
  /// 由调用方引导去充值。emailCode/inviteCode 见面板配置(不需要就留空)。
  Future<String?> register({
    required String panelUrl,
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
    String? sliderToken,
    String? companyWebsite,
  }) async {
    final api = XboardApi(panelUrl);
    final res = await api.register(
      email,
      password,
      inviteCode: inviteCode,
      emailCode: emailCode,
      sliderToken: sliderToken,
      companyWebsite: companyWebsite,
    );

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPanelUrl, panelUrl);
    await sp.setString(_kEmail, email);
    await _secureStorage.write(key: _kAuth, value: res.authData);

    String? mihomoUrl;
    String? subscribeUrl;
    try {
      final sub = await api.getSubscribe(res.authData);
      subscribeUrl = sub.subscribeUrl;
      mihomoUrl = XboardApi.toMihomoUrl(subscribeUrl);
      await sp.setString(_kSub, subscribeUrl);
    } on XboardNoSubscriptionException {
      await sp.remove(_kSub);
    }

    state = state.copyWith(
      loggedIn: true,
      panelUrl: panelUrl,
      email: email,
      authData: res.authData,
      subscribeUrl: subscribeUrl,
    );
    return mihomoUrl;
  }

  /// 重新拉取订阅地址(套餐变更/续费后)。返回最新 mihomo 订阅 URL,失败返回 null。
  Future<String?> refreshSubscribe() async {
    final auth = state.authData;
    if (auth == null) return null;
    XboardSubscribe sub;
    try {
      sub = await XboardApi(state.panelUrl).getSubscribe(auth);
    } on XboardNoSubscriptionException {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kSub);
      state = state.copyWith(subscribeUrl: null);
      rethrow;
    }
    final subscribeUrl = sub.subscribeUrl;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSub, subscribeUrl);
    state = state.copyWith(subscribeUrl: subscribeUrl);
    return XboardApi.toMihomoUrl(subscribeUrl);
  }

  /// 服务端已经明确确认当前账号没有有效订阅时，清除本机保存的旧地址。
  /// 普通网络错误不能调用此方法，避免误删仍可使用的节点。
  Future<void> clearSubscription() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kSub);
    state = state.copyWith(subscribeUrl: null);
  }

  /// failover 探测到可用通信地址后,让当前会话也切过去(持久化)。
  /// 这样已登录用户后续的接口(刷新订阅等,走 state.panelUrl)也用探通的地址,
  /// 而不是死守登录时那个可能已被墙的域名。地址没变就直接跳过。
  Future<void> adoptBase(String base) async {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty || b == state.panelUrl) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPanelUrl, b);
    // 通信域名和订阅域名必须隔离。切换 API 地址时不能改写订阅 URL 的 Host，
    // 否则 TianTi Core 的订阅域名白名单会按设计返回 404。
    final subscribeUrl = state.subscribeUrl;
    if (subscribeUrl != null) {
      await sp.setString(_kSub, subscribeUrl);
    }
    state = state.copyWith(panelUrl: b, subscribeUrl: subscribeUrl);
  }

  Future<void> logout() async {
    final auth = state.authData;
    if (auth != null && auth.isNotEmpty) {
      try {
        await XboardApi(state.panelUrl).logout(auth);
      } catch (_) {
        // 本地退出不能被短暂网络故障阻塞；服务端会话仍有固定有效期。
      }
    }
    final sp = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _kAuth);
    await sp.remove(_kSub);
    state = XboardAuthState(
      restored: true,
      loggedIn: false,
      panelUrl: state.panelUrl,
      email: state.email,
    );
  }
}
