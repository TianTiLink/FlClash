// 登录门控 —— 未登录显示 LoginPage,已登录显示 FlClash 主界面。
// 公告/通知只在「登录后冷启动首帧」弹一次:最小化后再切回前台不重弹,
// 只有关闭软件重新启动才会再弹(用户要求)。因此这里不监听 App 生命周期、
// 也不做定时轮询,避免切前台/后台反复弹窗。
// 代理中心已收进底部「我的」tab 里的按钮,这里不再放悬浮拉手。
//
// 接入(改 lib/application.dart 一处,若已接过则无需再改):
//   把 MaterialApp 的  home: child!   改成   home: XboardGate(child: child!),

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_auth.dart';
import 'xboard_endpoint.dart';
import 'login_page.dart';
import 'app_popup.dart';
import 'notice_watcher.dart';
import 'notice_announcement.dart';

class XboardGate extends ConsumerStatefulWidget {
  final Widget child;
  const XboardGate({super.key, required this.child});

  @override
  ConsumerState<XboardGate> createState() => _XboardGateState();
}

class _XboardGateState extends ConsumerState<XboardGate> {
  bool _popupTried = false;
  bool _noticeStarted = false;
  bool _endpointTried = false;

  @override
  void initState() {
    super.initState();
    // 启动时恢复会话(只跑一次)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final st = ref.read(xboardAuthProvider);
      if (!st.restored) {
        ref.read(xboardAuthProvider.notifier).restore();
      }
      // 后台 failover 探测通信地址 + 版本检查(异步,不阻塞会话恢复/UI)。
      _resolveEndpointOnce();
    });
  }

  // 启动只跑一次:逐个探测通信地址,探通后让会话切到该地址(防封 failover),
  // 再比对后台版本号,不一致就弹「建议更新」(非强制)。全程失败静默,等同现状。
  Future<void> _resolveEndpointOnce() async {
    if (_endpointTried) return;
    _endpointTried = true;
    TtEndpointResult r;
    try {
      r = await resolveEndpoint();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (r.online) {
      await ref.read(xboardAuthProvider.notifier).adoptBase(r.activeBase);
    }
    if (mounted && r.hasUpdate) {
      await maybeShowVersionUpdate(context, ref, r);
    }
  }

  // 通知 + 公告:只在登录后冷启动首帧各查一次(两者内部都有「本次进程只弹一次」去重)。
  // 不接 didChangeAppLifecycleState、不做定时轮询 —— 最小化切回前台不重弹,关闭重启才会再弹。
  void _startNoticeWatch() {
    if (_noticeStarted) return;
    _noticeStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        maybeShowNewNotices(context, ref); // 插件新通知:有比"看过的"更新的才弹,每进程一次
        maybeShowLatestAnnouncement(context, ref); // 原生公告:有内容就弹最新一条,每进程一次
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
    _startNoticeWatch();
    // 代理中心已收进底部「我的」tab,这里直接显示 FlClash 主界面即可。
    return widget.child;
  }
}
