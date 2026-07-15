// 后台原生「公告管理」弹窗 —— 每次打开 App(登录后首帧 + 从后台切回前台)拉一次原生公告,
// 有内容就弹「最新一条」;没有就不弹。不做"看过不弹",每次打开都弹(符合"强制每次显示")。
//
// 与 notice_watcher.dart 是两套、互不影响:
//   notice_watcher   → 插件发通知(/api/v1/reseller/notices),只弹比"看过的"新的那条、每条一次。
//   本文件           → Xboard 原生公告(/api/v1/user/notice/fetch),每次打开弹最新一条。
//
// 接入(在 xboard_gate.dart 的首帧回调 + didChangeAppLifecycleState.resumed 里各调一次):
//   maybeShowLatestAnnouncement(context, ref);
//
// 说明:原生公告正文是后台富文本(HTML)。FlClash 无 HTML 渲染依赖,这里转成可读纯文本显示。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'xboard_auth.dart';

bool _announcing = false; // 防重入:多个触发点(首帧/切前台)同时进来只弹一个

/// 把公告 HTML 正文转成可读纯文本(去标签、还原常见实体、压缩多余空行)。
String _htmlToText(String s) {
  var t = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>|</div>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '· ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  t = t.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

Future<void> maybeShowLatestAnnouncement(BuildContext context, WidgetRef ref) async {
  if (_announcing) return;
  final auth = ref.read(xboardAuthProvider);
  final token = auth.authData;
  // 需登录才拉公告;游客不弹。
  if (auth.panelUrl.isEmpty || token == null || token.isEmpty) return;
  final base = auth.panelUrl.replaceAll(RegExp(r'/+$'), '');

  List data;
  try {
    final resp = await http
        .get(Uri.parse('$base/api/v1/user/notice/fetch'),
            headers: {'Accept': 'application/json', 'Authorization': token})
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final d = body is Map ? body['data'] : null;
    if (d is! List || d.isEmpty) return; // 没有公告:不弹
    data = d;
  } catch (_) {
    return; // 拉取失败静默,不打扰
  }

  // 接口已按 sort ASC、id DESC 排序,第一条即置顶/最新那条。
  final first = data.first;
  if (first is! Map) return;
  final title = (first['title']?.toString() ?? '').trim();
  final content = _htmlToText(first['content']?.toString() ?? '');
  if (!context.mounted) return;

  _announcing = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title.isEmpty ? '公告' : title),
        content: SingleChildScrollView(
          child: Text(content.isEmpty ? '(无内容)' : content),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我知道了')),
        ],
      ),
    );
  } finally {
    _announcing = false;
  }
}
