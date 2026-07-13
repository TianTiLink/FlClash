// 登录门控 —— 未登录显示 LoginPage,已登录显示 FlClash 主界面。
// 已登录时首帧弹一次启动公告(Reseller 插件后台可配)。
// 代理中心已收进底部「我的」tab 里的按钮,这里不再放悬浮拉手。
//
// 接入(改 lib/application.dart 一处,若已接过则无需再改):
//   把 MaterialApp 的  home: child!   改成   home: XboardGate(child: child!),

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_auth.dart';
import 'login_page.dart';
import 'app_popup.dart';

class XboardGate extends ConsumerStatefulWidget {
  final Widget child;
  const XboardGate({super.key, required this.child});

  @override
  ConsumerState<XboardGate> createState() => _XboardGateState();
}

class _XboardGateState extends ConsumerState<XboardGate> {
  bool _popupTried = false;

  @override
  void initState() {
    super.initState();
    // 启动时恢复会话(只跑一次)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final st = ref.read(xboardAuthProvider);
      if (!st.restored) {
        ref.read(xboardAuthProvider.notifier).restore();
      }
    });
  }

  void _maybePopup() {
    if (_popupTried) return;
    _popupTried = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowResellerPopup(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(xboardAuthProvider);

    if (!auth.restored) {
      // 会话恢复中:极简 splash,避免闪现登录页。
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.loggedIn) {
      return const LoginPage();
    }

    // 已登录:首帧后弹一次启动公告(app_popup 内部已去重)。
    _maybePopup();

    // 代理中心已收进底部「我的」tab,这里直接显示 FlClash 主界面即可。
    return widget.child;
  }
}
