// 客户端通信地址 failover + 版本检查(防封核心)。
//
// 启动时 resolveEndpoint() 逐个探测候选 API 地址,用第一个能通的写入全局 ttActiveBase;
// 顺带把后台配置的 api_domains 缓存到本地(下次优先探),并返回版本/下载信息给版本检查用。
//
// 单一数据源:后台 admin_setting('tt_appconfig') -> GET /api/v1/reseller/appconfig。
// 候选顺序 = [上次探通的地址(最快) → 本地缓存的 api_domains → 硬编码兜底],逐个探。
// 这样正常时走"上次可用地址"秒开,只有它被墙才 failover 到备用,避免没解析的域名拖慢启动。
// 域名全没解析/全被墙时探测都失败 -> 保持默认地址,行为等同现状,安全降级。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_auth.dart' show ttActiveBase;

/// 本次编译的客户端版本号。发新版时:改这里、重编,再把后台对应平台版本号改成新的。
const String kClientVersion = '0.8.94';

const String _kApiDomainsCache = 'tt_api_domains';
const String _kActiveBaseCache = 'tt_active_base';

/// 兜底候选(硬编码,防止本地缓存也没有时无处可探)。
const List<String> _kSeedApiHosts = <String>[
  'https://14fas434ojf54a.xyz',  // API 主(客户端通信)
  'https://jais2d5n6as1ddf.xyz', // API 备
  'https://tiantilink.com',      // 最后兜底:两个 .xyz 都不通时,新装用户仍能引导上线
];

class TtEndpointResult {
  final String activeBase; // 探通的地址(已写入 ttActiveBase)
  final bool online; // 是否有任一地址探通
  final Map<String, dynamic> config; // 完整 appconfig(拿不到为空 map)
  TtEndpointResult(this.activeBase, this.online, this.config);

  String get _platformKey => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
              ? 'macos'
              : 'pwa';

  /// 当前平台对应的最新版本号(拿不到返回 null)。
  String? get latestVersion {
    final v = config['versions'];
    if (v is! Map) return null;
    final val = v[_platformKey];
    return val == null ? null : val.toString();
  }

  /// 当前平台对应的下载地址(相对路径补成绝对地址)。
  String? get downloadUrl {
    final d = config['downloads'];
    if (d is! Map) return null;
    // 下载 key:桌面端同版本键,iOS/其它落到 ios 导入页
    final key = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
            ? 'windows'
            : Platform.isMacOS
                ? 'macos'
                : 'ios';
    final val = d[key];
    if (val == null) return null;
    var s = val.toString();
    if (s.isEmpty) return null;
    if (s.startsWith('http')) return s;
    return activeBase.replaceAll(RegExp(r'/+$'), '') + s;
  }

  bool get updateForce => config['update_force'] == true;
  String get updateNote => (config['update_note'] ?? '').toString();

  /// 版本不一致 = 有更新(后台版本号非空且与编译版本不同)。
  bool get hasUpdate {
    final lv = latestVersion;
    return lv != null && lv.isNotEmpty && lv != kClientVersion;
  }
}

/// 规范化并追加一个候选地址(去重、补 https、去尾斜杠)。
void _addHost(List<String> list, String? h) {
  if (h == null) return;
  var s = h.trim();
  if (s.isEmpty) return;
  if (!s.startsWith('http')) s = 'https://$s';
  s = s.replaceAll(RegExp(r'/+$'), '');
  if (!list.contains(s)) list.add(s);
}

/// 组装候选:上次探通地址 → 当前默认 → 缓存的 api_domains → 硬编码兜底。
Future<List<String>> _candidates() async {
  final list = <String>[];
  try {
    final sp = await SharedPreferences.getInstance();
    _addHost(list, sp.getString(_kActiveBaseCache));
    final cached = sp.getStringList(_kApiDomainsCache);
    if (cached != null) {
      for (final h in cached) {
        _addHost(list, h);
      }
    }
  } catch (_) {}
  _addHost(list, ttActiveBase);
  for (final h in _kSeedApiHosts) {
    _addHost(list, h);
  }
  return list;
}

/// 探测一个地址的 appconfig。通 -> 返回 config map;不通 -> 抛异常。
Future<Map<String, dynamic>> _probe(String base, Duration timeout) async {
  final uri = Uri.parse('$base/api/v1/reseller/appconfig');
  final resp = await http
      .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  final j = jsonDecode(resp.body);
  if (j is Map && j['data'] is Map) {
    return Map<String, dynamic>.from(j['data'] as Map);
  }
  throw Exception('bad body');
}

/// 启动时调用一次:逐个探测,用第一个能通的地址。
/// 探通后:写 ttActiveBase、持久化"上次可用地址"、缓存后台最新 api_domains、返回结果(含版本)。
/// 全失败:保持 ttActiveBase 不变,online=false,config={}(登录/订阅照常用默认地址,等同现状)。
Future<TtEndpointResult> resolveEndpoint({
  Duration perTry = const Duration(seconds: 6),
}) async {
  final cands = await _candidates();
  for (final base in cands) {
    try {
      final cfg = await _probe(base, perTry);
      ttActiveBase = base;
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_kActiveBaseCache, base);
        final apis = cfg['api_domains'];
        if (apis is List && apis.isNotEmpty) {
          await sp.setStringList(
            _kApiDomainsCache,
            apis.map((e) => e.toString()).toList(),
          );
        }
      } catch (_) {}
      return TtEndpointResult(base, true, cfg);
    } catch (_) {
      // 换下一个候选
    }
  }
  return TtEndpointResult(ttActiveBase, false, <String, dynamic>{});
}
