// 登录门控 —— 未登录显示 LoginPage,已登录显示 FlClash 主界面。
// 已登录时首帧弹一次启动公告(Reseller 插件后台可配)。
// 代理中心已收进底部「我的」tab 里的按钮,这里不再放悬浮拉手。
//
// 接入(改 lib/application.dart 一处,若已接过则无需再改):
//   把 MaterialApp 的  home: child!   改成   home: XboardGate(child: child!),

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_auth.dart';
import 'login_page.dart';
import 'app_popup.dart';
import 'notice_watcher.dart';

class XboardGate extends ConsumerStatefulWidget {
  final Widget child;
  const XboardGate({super.key, required this.child});

  @override
  ConsumerState<XboardGate> createState() => _XboardGateState();
}

class _XboardGateState extends ConsumerState<XboardGate>
    with WidgetsBindingObserver {
  bool _popupTried = false;
  bool _noticeStarted = false;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动时恢复会话(只跑一次)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final st = ref.read(xboardAuthProvider);
      if (!st.restored) {
        ref.read(xboardAuthProvider.notifier).restore();
      }
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台切回前台:查一次新通知。
    if (state == AppLifecycleState.resumed && mounted) {
      maybeShowNewNotices(context, ref);
    }
  }

  // 通知弹窗:登录后首帧查一次 + 每 4 分钟查一次。
  void _startNoticeWatch() {
    if (_noticeStarted) return;
    _noticeStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowNewNotices(context, ref);
    });
    _noticeTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (mounted) maybeShowNewNotices(context, ref);
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
    _startNoticeWatch();
    // 代理中心已收进底部「我的」tab,这里直接显示 FlClash 主界面即可。
    return widget.child;
  }
}
