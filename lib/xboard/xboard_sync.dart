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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/state.dart'; // globalState
import 'package:fl_clash/models/profile.dart'; // Profile
import 'package:fl_clash/providers/action.dart'; // profilesActionProvider, setupActionProvider
import 'package:fl_clash/providers/database.dart'; // profilesProvider
import 'package:fl_clash/providers/config.dart'; // currentProfileIdProvider, patchClashConfigProvider
import 'package:fl_clash/providers/app.dart'; // groupsProvider, delayDataSourceProvider
import 'package:fl_clash/enum/enum.dart'; // Mode
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';

const Duration kTianTiRoutineRefreshInterval = Duration(hours: 6);
const Duration kTianTiHealingCooldown = Duration(minutes: 5);
const String _kLastAutoRefreshTime = 'tianti_last_auto_refresh_ms';
const String _kLastHealingRefreshTime = 'tianti_last_healing_refresh_ms';

Future<bool>? _autoRefreshInFlight;

class SubscriptionImportResult {
  final bool changed;
  final Profile profile;

  const SubscriptionImportResult({
    required this.changed,
    required this.profile,
  });
}

bool shouldTianTiAutoRefresh({
  required DateTime? lastRefreshTime,
  required bool force,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (lastRefreshTime == null) return true;
  final elapsed = current.difference(lastRefreshTime);
  if (force) {
    return elapsed >= kTianTiHealingCooldown;
  }
  return elapsed >= kTianTiRoutineRefreshInterval;
}

bool hasSubscriptionContentChanged(List<int> oldBytes, List<int> newBytes) {
  return !listEquals(oldBytes, newBytes);
}

List<String> orderedSubscriptionCandidates(String primary, Iterable<String> configured) =>
    <String>{primary, ...configured}.where((value) => value.trim().isNotEmpty).toList();

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
  final sameManagedToken = ua.scheme == 'https' &&
      ub.scheme == 'https' &&
      ua.path == ub.path &&
      RegExp(r'^/s/[A-Za-z0-9_-]{43}$').hasMatch(ua.path);
  if (ua.scheme != ub.scheme || ua.path != ub.path || (ua.host != ub.host && !sameManagedToken)) {
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

/// 判断旧版客户端留下的 Profile 是否属于天梯托管订阅。
///
/// 优先按服务端最后保存的完整订阅地址精确匹配；只在迁移旧版本、没有地址可比时，
/// 才接受“天梯品牌名 + /s/ 令牌路径”的组合，避免误删用户自己导入的其他配置。
bool isTianTiManagedSubscription(Profile profile, {String? subscribeUrl}) {
  final expected = subscribeUrl?.trim();
  if (expected != null &&
      expected.isNotEmpty &&
      _sameSubscription(profile.url, XboardApi.toMihomoUrl(expected))) {
    return true;
  }

  final label = profile.label.trim().toLowerCase().replaceAll(' ', '');
  const labels = <String>{'tianti', 'tiantilink', '天梯', '天梯link'};
  // 只有在服务端已经明确返回“无有效套餐”后才会进入清理，因此品牌名本身就是
  // 最可靠的迁移标识。旧客户端曾保存 /api/v1/client/subscribe、/s/ 等多种路径；
  // 再限定新路径会漏掉旧版 TianTi profile，界面便继续显示已经失效的历史节点。
  return labels.contains(label);
}

/// 清除已经失效的天梯订阅和内核里残留的旧节点。
///
/// 只应在服务端明确返回“没有有效套餐”时调用；网络/TLS 临时失败必须保留旧节点。
Future<int> clearTianTiSubscriptionProfiles({String? subscribeUrl}) async {
  final c = globalState.container;
  final profiles = List<Profile>.from(c.read(profilesProvider));
  final removed = profiles
      .where(
        (profile) =>
            isTianTiManagedSubscription(profile, subscribeUrl: subscribeUrl),
      )
      .toList();
  if (removed.isEmpty) {
    c.read(groupsProvider.notifier).value = [];
    c.read(delayDataSourceProvider.notifier).value = {};
    await c.read(setupActionProvider.notifier).updateStatus(false);
    return 0;
  }

  final activeId = c.read(currentProfileIdProvider);
  final removedActive = removed.any((profile) => profile.id == activeId);
  for (final profile in removed) {
    await c.read(profilesActionProvider.notifier).deleteProfile(profile.id);
  }

  final remaining = c.read(profilesProvider);
  if (remaining.isEmpty) {
    c.read(currentProfileIdProvider.notifier).value = null;
  } else if (removedActive) {
    c.read(currentProfileIdProvider.notifier).value = null;
  }
  c.read(groupsProvider.notifier).value = [];
  c.read(delayDataSourceProvider.notifier).value = {};
  await c.read(setupActionProvider.notifier).updateStatus(false);
  return removed.length;
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

/// 智能静默/故障自愈自动刷新天梯订阅。
///
/// [force]: 为 true 时用于故障自愈（如全部节点超时、核心异常退出），
///          仍受 5 分钟冷却保护，避免瞬时循环风暴。
///          为 false 时用于冷启动与周期检查，仅在距上次刷新满 6 小时后触发。
/// [reason]: 记录触发来源（startup / resume / periodic / healing_*）。
/// 返回: true 表示节点内容有变动且已生效，false 表示无变动、跳过或静默失败。
Future<bool> autoRefreshTianTiSubscription({
  bool force = false,
  String reason = 'routine',
}) async {
  final active = _autoRefreshInFlight;
  if (active != null) return active;
  final task = _performAutoRefresh(force: force, reason: reason);
  _autoRefreshInFlight = task;
  try {
    return await task;
  } finally {
    if (identical(_autoRefreshInFlight, task)) {
      _autoRefreshInFlight = null;
    }
  }
}

Future<bool> _performAutoRefresh({
  required bool force,
  required String reason,
}) async {
  final c = globalState.container;
  final auth = c.read(xboardAuthProvider);
  if (!auth.loggedIn || auth.authData == null) {
    return false;
  }

  final sp = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final lastRoutineMs = sp.getInt(_kLastAutoRefreshTime);
  final lastHealingMs = sp.getInt(_kLastHealingRefreshTime);
  final lastCheckTime = force
      ? (lastHealingMs != null ? DateTime.fromMillisecondsSinceEpoch(lastHealingMs) : null)
      : (lastRoutineMs != null ? DateTime.fromMillisecondsSinceEpoch(lastRoutineMs) : null);

  if (!shouldTianTiAutoRefresh(
    lastRefreshTime: lastCheckTime,
    force: force,
    now: now,
  )) {
    return false;
  }

  String? freshMihomoUrl;
  try {
    freshMihomoUrl = await c.read(xboardAuthProvider.notifier).refreshSubscribe();
  } on XboardNoSubscriptionException {
    await clearTianTiSubscriptionProfiles(subscribeUrl: auth.subscribeUrl);
    return false;
  } catch (error) {
    commonPrint.log(
      '[TianTi] Auto-refresh ($reason) failed to retrieve subscription url: $error',
      logLevel: LogLevel.warning,
    );
    return false;
  }

  if (freshMihomoUrl == null || freshMihomoUrl.isEmpty) {
    return false;
  }

  try {
    final result = await importXboardSubscription(
      freshMihomoUrl,
      forceApply: force,
    );
    final nowMs = now.millisecondsSinceEpoch;
    await sp.setInt(_kLastAutoRefreshTime, nowMs);
    if (force) {
      await sp.setInt(_kLastHealingRefreshTime, nowMs);
    }
    commonPrint.log(
      '[TianTi] Auto-refresh ($reason) completed successfully (changed: ${result.changed})',
      logLevel: LogLevel.info,
    );
    return result.changed;
  } catch (error) {
    commonPrint.log(
      '[TianTi] Auto-refresh ($reason) sync error: $error',
      logLevel: LogLevel.warning,
    );
    return false;
  }
}

/// 导入(或复用)Xboard 订阅并切到它。
/// [subscribeUrl] 传 XboardAuth.login/refreshSubscribe 返回的 mihomo URL(已含 ?flag=meta),
/// 或原始 subscribe_url(本函数会自动补 flag=meta)。
/// [forceApply]: 为 true 时即便订阅内容一致也强制重载内核（用于用户手动点击“刷新节点”）；
/// 为 false 时比对新旧 YAML，无变动则仅更新元数据与过期时间，不重载内核，保障活跃长连接不中断。
Future<SubscriptionImportResult> importXboardSubscription(
  String subscribeUrl, {
  bool forceApply = false,
}) async {
  final c = globalState.container;
  final configured = c.read(xboardAuthProvider).subscribeUrls;
  final candidates = orderedSubscriptionCandidates(subscribeUrl, configured)
      .map((value) => value.contains('flag=') ? value : XboardApi.toMihomoUrl(value))
      .toList();
  Object? lastError;
  for (final candidate in candidates) {
    try {
      final result = await _importXboardSubscriptionUrl(candidate, forceApply: forceApply);
      await c.read(xboardAuthProvider.notifier).markSubscriptionAvailable(candidate);
      return result;
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError != null) throw lastError;
  throw XboardApiException('没有可用的订阅地址');
}

Future<SubscriptionImportResult> _importXboardSubscriptionUrl(
  String url, {
  bool forceApply = false,
}) async {
  final c = globalState.container;

  // 1. 去重: 找到属于同一份订阅的已有 profile
  Profile? existing;
  for (final p in c.read(profilesProvider)) {
    if (_sameSubscription(p.url, url)) {
      existing = p;
      break;
    }
  }

  final fetchUrl = _withNoCache(url);
  final response = await request.getFileResponseForUrl(fetchUrl);
  final bytes = response.data ?? Uint8List.fromList([]);
  if (bytes.isEmpty) {
    throw XboardApiException('订阅内容为空');
  }

  // 2. 写入临时文件并通过 Mihomo 内核校验合法性（防止拉到报错 HTML 破坏配置）
  final tempPath = await appPath.tempFilePath;
  final tempFile = File(tempPath);
  await tempFile.safeWriteAsBytes(bytes);
  final validationError = await coreController.validateConfig(tempPath);
  if (validationError.isNotEmpty) {
    await tempFile.safeDelete();
    throw validationError;
  }

  final disposition = response.headers.value('content-disposition');
  final userinfo = response.headers.value('subscription-userinfo');
  final subInfo = SubscriptionInfo.formHString(userinfo);

  if (existing != null) {
    final mFile = await existing.file;
    bool contentChanged = true;
    if (await mFile.exists()) {
      final oldBytes = await mFile.readAsBytes();
      contentChanged = hasSubscriptionContentChanged(oldBytes, bytes);
    }

    if (contentChanged || forceApply) {
      await tempFile.copy(mFile.path);
      await tempFile.safeDelete();

      final updated = existing.copyWith(
        url: fetchUrl,
        label: existing.label.takeFirstValid([
          utils.getFileNameForDisposition(disposition),
          existing.id.toString(),
        ]),
        subscriptionInfo: subInfo,
        lastUpdateDate: DateTime.now(),
      );
      c.read(profilesProvider.notifier).put(updated);
      c.read(currentProfileIdProvider.notifier).value = updated.id;
      await c.read(setupActionProvider.notifier).applyProfile(force: true);
      _ensureVisibleMode();
      commonPrint.log('[TianTi] Subscription applied (changed: $contentChanged, force: $forceApply)');
      return SubscriptionImportResult(changed: true, profile: updated);
    } else {
      await tempFile.safeDelete();
      final updated = existing.copyWith(
        url: fetchUrl,
        subscriptionInfo: subInfo,
        lastUpdateDate: DateTime.now(),
      );
      c.read(profilesProvider.notifier).put(updated);
      commonPrint.log('[TianTi] Subscription content unchanged; active connection preserved.');
      return SubscriptionImportResult(changed: false, profile: updated);
    }
  }

  // 3. 不存在已有 Profile：首次导入
  final newProfile = Profile.normal(
    url: fetchUrl,
    label: utils.getFileNameForDisposition(disposition),
  ).copyWith(
    subscriptionInfo: subInfo,
    lastUpdateDate: DateTime.now(),
  );
  final mFile = await newProfile.file;
  await tempFile.copy(mFile.path);
  await tempFile.safeDelete();

  c.read(profilesActionProvider.notifier).putProfile(newProfile);
  c.read(currentProfileIdProvider.notifier).value = newProfile.id;
  await c.read(setupActionProvider.notifier).applyProfile(force: true);
  _ensureVisibleMode();
  return SubscriptionImportResult(changed: true, profile: newProfile);
}
