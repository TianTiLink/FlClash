// 登录态 + 会话持久化(Riverpod v3 手写 Notifier,无需 build_runner 代码生成)。
//
// 存储分两处:
//   - 敏感的登录凭据(auth_data)→ flutter_secure_storage(系统级加密:iOS Keychain /
//     Android Keystore)。依赖:pubspec.yaml 加 `flutter_secure_storage: ^10.3.1`
//     (必须 ^10.3.1,不能 ^9——当前 FlClash 依赖 win32^6,^9 会拽进 win32^5 致 pub get 冲突;
//     v10 的 read/write/delete 用法与 v9 相同,本文件无需改动)。
//   - 非敏感的展示用字段(面板地址、邮箱、订阅地址)→ shared_preferences 明文即可。
//
// 关于「登出」:这里的 logout() 只清本地存储,不调用服务端接口把 token 吊销掉。
// 这是刻意的——核实过 Xboard 当前的会话 API(AuthService::generateAuthData()),
// 客户端拿到的 auth_data 是 Sanctum token 去掉了数据库 id 前缀的部分,而服务端
// removeSession($id) 要按 id 匹配、getSessions() 也不返回“这是不是当前设备”的标记。
// 也就是说客户端根本不知道该吊销哪一条会话——瞎猜着调用只会伤到别的在线设备,
// 比不调用更危险,所以没有做。如果需要真正的服务端登出,需要 Xboard 自身加一个
// 按当前 token 吊销的专用接口后再接入。
// 另外:Xboard 服务端把 token 有效期设成整整一年(now()->addYear()),意味着一旦
// token 泄露,在没有服务端强制失效手段的情况下会长期有效——务必配合加密存储使用。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_api.dart';

const _secureStorage = FlutterSecureStorage();

/// 你的面板地址。登录页已隐藏"面板地址"输入框,用户只填邮箱密码,登录直接用这个地址。
/// 换域名时改这里、重编即可。
const String kDefaultPanelUrl = 'https://tiantilink.com';

const _kPanelUrl = 'xb_panel_url';
const _kEmail = 'xb_email';
const _kAuth = 'xb_auth_data';
const _kSub = 'xb_subscribe_url';

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
    String? authData,
    String? subscribeUrl,
  }) {
    return XboardAuthState(
      restored: restored ?? this.restored,
      loggedIn: loggedIn ?? this.loggedIn,
      panelUrl: panelUrl ?? this.panelUrl,
      email: email ?? this.email,
      authData: authData ?? this.authData,
      subscribeUrl: subscribeUrl ?? this.subscribeUrl,
    );
  }
}

final xboardAuthProvider =
    NotifierProvider<XboardAuth, XboardAuthState>(XboardAuth.new);

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
      panelUrl: sp.getString(_kPanelUrl) ?? kDefaultPanelUrl,
      email: sp.getString(_kEmail) ?? '',
      authData: auth,
      subscribeUrl: sp.getString(_kSub),
    );
  }

  /// 登录:验证账号 -> 尝试取订阅地址 -> 持久化。
  /// 返回 mihomo 订阅 URL 供导入;若账号还没有任何套餐(getSubscribe 失败),
  /// 登录本身仍然算成功(账号密码是对的),只是没有订阅可导入——返回 null,
  /// 由调用方(账户页/门控)引导用户去充值,而不是把用户挡在登录页外面。
  Future<String?> login({
    required String panelUrl,
    required String email,
    required String password,
  }) async {
    final api = XboardApi(panelUrl);
    final res = await api.login(email, password);

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPanelUrl, panelUrl);
    await sp.setString(_kEmail, email);
    await _secureStorage.write(key: _kAuth, value: res.authData);

    String? mihomoUrl;
    String? subscribeUrl;
    try {
      final sub = await api.getSubscribe(res.authData);
      subscribeUrl = sub.subscribeUrl;
      mihomoUrl = XboardApi.toMihomoUrl(sub.subscribeUrl);
      await sp.setString(_kSub, subscribeUrl);
    } on XboardApiException {
      // 账号未购买套餐 / 暂无订阅:不算登录失败,让用户先进 App 再去充值。
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

  /// 注册并自动登录。与 login 一样持久化凭据、尝试拉订阅;新号一般还没套餐→返回 null,
  /// 由调用方引导去充值。emailCode/inviteCode 见面板配置(不需要就留空)。
  Future<String?> register({
    required String panelUrl,
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
  }) async {
    final api = XboardApi(panelUrl);
    final res = await api.register(email, password,
        inviteCode: inviteCode, emailCode: emailCode);

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPanelUrl, panelUrl);
    await sp.setString(_kEmail, email);
    await _secureStorage.write(key: _kAuth, value: res.authData);

    String? mihomoUrl;
    String? subscribeUrl;
    try {
      final sub = await api.getSubscribe(res.authData);
      subscribeUrl = sub.subscribeUrl;
      mihomoUrl = XboardApi.toMihomoUrl(sub.subscribeUrl);
      await sp.setString(_kSub, subscribeUrl);
    } on XboardApiException {
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
    final sub = await XboardApi(state.panelUrl).getSubscribe(auth);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSub, sub.subscribeUrl);
    state = state.copyWith(subscribeUrl: sub.subscribeUrl);
    return XboardApi.toMihomoUrl(sub.subscribeUrl);
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _kAuth);
    await sp.remove(_kSub);
    state = state.copyWith(loggedIn: false, authData: null, subscribeUrl: null);
  }
}
