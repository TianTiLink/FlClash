// 通知弹窗 —— 拉 Reseller 通知(发给我的 + 全体广播),有比"上次弹过的 id"更新的就弹最新那条。
// 由 XboardGate 触发:登录后首帧 + 每 ~4 分钟 + 从后台切回前台各查一次。
// 已弹过的记在 secure storage,不重复弹;游客(未登录)不查。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'xboard_auth.dart';

const _storage = FlutterSecureStorage();
const _kSeenKey = 'xboard_notice_popup_id';
bool _showing = false; // 防重入:多个触发点同时进来只弹一个

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

Future<void> maybeShowNewNotices(BuildContext context, WidgetRef ref) async {
  if (_showing) return;
  final auth = ref.read(xboardAuthProvider);
  final token = auth.authData;
  if (auth.panelUrl.isEmpty || token == null || token.isEmpty) return;
  final base = auth.panelUrl.replaceAll(RegExp(r'/+$'), '');

  List data;
  try {
    final resp = await http
        .get(Uri.parse('$base/api/v1/reseller/notices'),
            headers: {'Accept': 'application/json', 'Authorization': token})
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final d = body is Map ? body['data'] : null;
    if (d is! List || d.isEmpty) return;
    data = d;
  } catch (_) {
    return; // 拉取失败静默,不打扰
  }

  // 取 id 最大(最新)的一条
  Map<String, dynamic>? newest;
  int maxId = 0;
  for (final e in data) {
    if (e is! Map) continue;
    final id = _toInt(e['id']);
    if (id > maxId) {
      maxId = id;
      newest = Map<String, dynamic>.from(e);
    }
  }
  if (newest == null) return;

  final seen = _toInt(await _storage.read(key: _kSeenKey));
  if (maxId <= seen) return; // 没有新通知
  if (!context.mounted) return;

  final title = (newest['title']?.toString() ?? '').trim();
  final content = (newest['content']?.toString() ?? '').trim();

  _showing = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title.isEmpty ? '通知' : title),
        content: SingleChildScrollView(
          child: Text(content.isEmpty ? '(无内容)' : content),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了')),
        ],
      ),
    );
    await _storage.write(key: _kSeenKey, value: maxId.toString()); // 弹过即记已读
  } finally {
    _showing = false;
  }
}
