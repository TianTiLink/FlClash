// 把 Xboard 订阅导入 FlClash 的 profile 系统并激活。
//
// 对照 FlClash 源码(lib/providers/action.dart / config.dart / database.dart):
//   加订阅:  profilesActionProvider.notifier.addProfileFormURL(url)   // 注意是 Form 不是 From
//   查列表:  profilesProvider                                        // List<Profile>
//   设当前:  currentProfileIdProvider.notifier.value = id
//   应用:    setupActionProvider.notifier.applyProfileDebounce(force: true)  // 命名参数
//
// ⚠ 导入路径按你的品牌名改:FlClash 的包名是 fl_clash;若你把 pubspec 的 name 改成
//   例如 my_vpn,则下面 `package:fl_clash/...` 要同步改成 `package:my_vpn/...`。
//   下列具体路径请对照你 clone 的 FlClash 版本核对(不同版本可能微调)。

import 'package:fl_clash/state.dart'; // globalState
import 'package:fl_clash/models/profile.dart'; // Profile
import 'package:fl_clash/providers/action.dart'; // profilesActionProvider, setupActionProvider
import 'package:fl_clash/providers/database.dart'; // profilesProvider
import 'package:fl_clash/providers/config.dart'; // currentProfileIdProvider, patchClashConfigProvider
import 'package:fl_clash/enum/enum.dart'; // Mode

import 'xboard_api.dart';

/// 两个订阅 URL 是否指向"同一份订阅"——忽略我们自己加的 flag 参数、以及查询参数的
/// 先后顺序。只按裸字符串 `==` 比较太脆弱:面板如果哪天订阅链接的参数顺序变了、或
/// 者多带了个无关参数,裸比较就会把同一份订阅误判成"新的",导致每次登录/刷新都
/// 在 FlClash 里堆一份新 profile。真正决定"是不是同一份订阅"的应该是host+路径+
/// 除 flag 外的其余参数,而不是整个 URL 字符串长得像不像。
bool _sameSubscription(String a, String b) {
  Uri? ua, ub;
  try {
    ua = Uri.parse(a);
    ub = Uri.parse(b);
  } catch (_) {
    return a == b; // 解析失败就退化为原始比较,不崩
  }
  if (ua.scheme != ub.scheme || ua.host != ub.host || ua.path != ub.path) {
    return false;
  }
  final qa = Map<String, String>.from(ua.queryParameters)
    ..remove('flag')
    ..remove('_');
  final qb = Map<String, String>.from(ub.queryParameters)
    ..remove('flag')
    ..remove('_');
  if (qa.length != qb.length) return false;
  for (final entry in qa.entries) {
    if (qb[entry.key] != entry.value) return false;
  }
  return true;
}

/// 给下载 URL 加一个每次都不同的 cache-buster(`_=时间戳`),绕开任何 CDN/反代对订阅
/// 响应的缓存,确保「刷新订阅」强制重下拿到面板最新内容,而不是中间层的旧副本。
/// _sameSubscription 连同 flag 一起忽略 `_`,所以每次换 buster 不会破坏去重、也不会堆重复 profile。
String _withNoCache(String url) {
  try {
    final uri = Uri.parse(url);
    final qp = Map<String, String>.from(uri.queryParameters)
      ..['_'] = DateTime.now().millisecondsSinceEpoch.toString();
    return uri.replace(queryParameters: qp).toString();
  } catch (_) {
    return url;
  }
}

/// 刷新/导入订阅成功后:若当前处于「直连」模式,自动切回「智能」模式。
/// 根因:currentGroupsState 在直连模式下恒返回空列表,所以哪怕新节点已加载进内核,
/// 用户仍会看到「刷新成功但左侧没有节点」——续费重新购买后最典型(过期期间手动切了
/// 直连,续费刷新后节点仍不显示)。这里等价于自动按下空态里的「切回智能模式」按钮,
/// 切回后刚加载好的节点立即显示。用户已选择此行为(刷新即自动切智能)。
void _ensureVisibleMode() {
  final c = globalState.container;
  if (c.read(patchClashConfigProvider).mode == Mode.direct) {
    c.read(setupActionProvider.notifier).changeMode(Mode.rule);
  }
}

/// 导入(或复用)Xboard 订阅并切到它。
/// [subscribeUrl] 传 XboardAuth.login/refreshSubscribe 返回的 mihomo URL(已含 ?flag=meta),
/// 或原始 subscribe_url(本函数会自动补 flag=meta)。
Future<void> importXboardSubscription(String subscribeUrl) async {
  final url = subscribeUrl.contains('flag=')
      ? subscribeUrl
      : XboardApi.toMihomoUrl(subscribeUrl);

  final c = globalState.container;

  // 去重:FlClash 的 Profile.normal 每次用 snowflake 生成新 id,直接反复 addProfileFormURL
  // 会累积重复订阅。所以先按"同一份订阅"的宽松定义找已存在的,而不是裸字符串相等。
  Profile? existing;
  for (final p in c.read(profilesProvider)) {
    if (_sameSubscription(p.url, url)) {
      existing = p;
      break;
    }
  }

  if (existing != null) {
    // 已存在:强制从「最新订阅 URL(+ 每次不同的 no-cache 参数)」重下、校验通过后覆盖
    // <id>.yaml,再切当前 + 立即应用。三个关键点(都踩过坑):
    //   1) 用刚 refreshSubscribe() 拿到的最新 url 覆盖 existing.url(面板轮换 token 时旧 url 会失效),
    //      再加 `_=时间戳` 绕开 CDN/反代对订阅的缓存,确保拿到面板最新节点。
    //   2) 【不再 try/catch 吞异常】。updateProfile→Profile.update() 真正走网络重下,saveFile 里先
    //      validateConfig 再覆盖 <id>.yaml,失败会 throw 且旧 yaml 还没被覆盖。以前 catch(_){} 把异常
    //      吞掉、继续用旧 yaml 应用还提示"已刷新" = 用户看到的"刷新了还是旧节点/旧缓存"。现在让它抛给
    //      上层,account_page 的 catch 会如实提示"刷新失败",不再假装成功。
    //   3) 用 await applyProfile(force:true) 立即重解析进 mihomo 并刷新节点分组;不走
    //      applyProfileDebounce(拖 600ms 且可能被同 tag 取消),节点列表当场更新。
    final fresh = existing.copyWith(url: _withNoCache(url));
    await c.read(profilesActionProvider.notifier).updateProfile(fresh);
    c.read(currentProfileIdProvider.notifier).value = fresh.id;
    await c.read(setupActionProvider.notifier).applyProfile(force: true);
    _ensureVisibleMode();
    return;
  }

  // 不存在:走 FlClash 官方入口(内部会下载订阅、写配置、落库;若当前无激活项则自动激活)。
  await c.read(profilesActionProvider.notifier).addProfileFormURL(url);

  // 若之前已有别的激活订阅,addProfileFormURL 不会自动切过来,这里强制切到新导入的。
  for (final p in c.read(profilesProvider)) {
    if (_sameSubscription(p.url, url)) {
      c.read(currentProfileIdProvider.notifier).value = p.id;
      c.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
      break;
    }
  }
  _ensureVisibleMode();
}
