// 客户端启动弹窗 —— 读 Reseller 插件的 /popup(游客接口),按后台配置弹出
// 更新提示 / 公告说明,可带「下载更新」按钮;开启强制更新且配了下载地址时会挡住不给关。
//
// 接入(在主界面首帧后调用一次,例如 XboardGate 的 child 外层或主页):
//   WidgetsBinding.instance.addPostFrameCallback((_) => maybeShowResellerPopup(context, ref));
//
// 依赖 url_launcher(FlClash 已有)。import 路径按你的品牌包名改。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reseller_api.dart';
import 'xboard_auth.dart';

bool _shownOnce = false;

/// 拉取并(按需)展示启动弹窗。[once]=true 时每次 App 运行只弹一次。
Future<void> maybeShowResellerPopup(BuildContext context, WidgetRef ref, {bool once = true}) async {
  if (once && _shownOnce) return;

  final auth = ref.read(xboardAuthProvider);
  if (auth.panelUrl.isEmpty) return;

  Map<String, dynamic> p;
  try {
    p = await ResellerApi(auth.panelUrl).popup();
  } catch (_) {
    return; // 拉取失败静默,不打扰用户
  }
  if (p['enable'] != true) return;
  _shownOnce = true;
  if (!context.mounted) return;

  final title = ((p['title'] as String?) ?? '').trim();
  final content = ((p['content'] as String?) ?? '').trim();
  final url = ((p['download_url'] as String?) ?? '').trim();
  final version = ((p['latest_version'] as String?) ?? '').trim();
  // 只有「开了强制更新」且「确实配了下载地址」才真正阻断,避免配置疏漏把用户永久卡死。
  final bool effectiveForce = (p['force'] == true) && url.isNotEmpty;

  await showDialog<void>(
    context: context,
    barrierDismissible: !effectiveForce,
    builder: (ctx) => PopScope(
      canPop: !effectiveForce,
      child: AlertDialog(
        title: Text(title.isEmpty ? '公告' : title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (version.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('最新版本:$version',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              if (content.isNotEmpty) Text(content),
              if (effectiveForce)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('请更新到最新版本后再继续使用。',
                      style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
        actions: [
          if (!effectiveForce)
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('稍后')),
          if (url.isNotEmpty)
            FilledButton(
              onPressed: () async {
                final uri = Uri.tryParse(url);
                // 只允许 http/https,拦截 javascript: 等可疑协议。
                if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (!effectiveForce && ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('下载更新'),
            ),
        ],
      ),
    ),
  );
}
