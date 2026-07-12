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
import 'package:fl_clash/providers/config.dart'; // currentProfileIdProvider

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
  final qa = Map<String, String>.from(ua.queryParameters)..remove('flag');
  final qb = Map<String, String>.from(ub.queryParameters)..remove('flag');
  if (qa.length != qb.length) return false;
  for (final entry in qa.entries) {
    if (qb[entry.key] != entry.value) return false;
  }
  return true;
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
    // 已存在:切为当前并应用(FlClash 自带的定时任务会按 autoUpdate 刷新内容)。
    c.read(currentProfileIdProvider.notifier).value = existing.id;
    c.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
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
}
