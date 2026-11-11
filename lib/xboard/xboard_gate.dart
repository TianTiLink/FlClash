// 登录门控 —— 未登录显示 LoginPage,已登录显示 FlClash 主界面。
// 公告/通知只在「登录后冷启动首帧」弹一次:最小化后再切回前台不重弹,
// 只有关闭软件重新启动才会再弹(用户要求)。因此这里不监听 App 生命周期、
// 也不做定时轮询,避免切前台/后台反复弹窗。
// 代理中心已收进底部「我的」tab 里的按钮,这里不再放悬浮拉手。
//
// 接入(改 lib/application.dart 一处,若已接过则无需再改):
//   把 MaterialApp 的  home: child!   改成   home: XboardGate(child: child!),

import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_popup.dart';
import 'login_page.dart';
import 'notice_announcement.dart';
import 'xboard_auth.dart';
import 'xboard_endpoint.dart';
import 'xboard_sync.dart';

class XboardGate extends ConsumerStatefulWidget {
  final Widget child;
  const XboardGate({super.key, required this.child});

  @override
  ConsumerState<XboardGate> createState() => _XboardGateState();
}

class _XboardGateState extends ConsumerState<XboardGate> {
  bool _endpointTried = false;
  bool _startupReady = false;
  bool _dialogsDispatched = false;
  TtEndpointResult? _endpointResult;

  @override
  void initState() {
    super.initState();
    // 启动时恢复会话(只跑一次)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreAndResolve();
    });
  }

  Future<void> _restoreAndResolve() async {
    try {
      final st = ref.read(xboardAuthProvider);
      if (!st.restored) {
        await ref.read(xboardAuthProvider.notifier).restore();
      }
      // 必须先恢复旧状态、再探测并覆盖通信地址。并发执行会让旧缓存反向覆盖刚
      // 探通的新地址，随后账户/推广请求就可能直接命中失效域名并报 TLS 握手失败。
      await _resolveEndpointOnce();
    } finally {
      if (mounted) setState(() => _startupReady = true);
      markTianTiGateReady();
    }
  }

  // 启动只跑一次:逐个探测通信地址,探通后让会话切到该地址(防封 failover),
  // 并比对后台最新版本号信息。
  Future<void> _resolveEndpointOnce() async {
    if (_endpointTried) return;
    _endpointTried = true;
    try {
      _endpointResult = await resolveEndpoint(
        currentVersion: globalState.packageInfo.version,
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final r = _endpointResult;
    if (r != null && r.online) {
      await ref.read(xboardAuthProvider.notifier).adoptBase(r.activeBase);
    }
  }

  // 弹窗严格按顺序排队：先展示版本升级（必须更新或建议更新），用户关闭或无更新后再弹后台通知公告，杜绝弹窗重叠冲突。
  void _dispatchStartupDialogs() {
    if (_dialogsDispatched) return;
    _dialogsDispatched = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 1. 第一步：先检查并展示版本更新（必须更新或建议更新均第一时间弹出）
      final r = _endpointResult;
      if (r != null && r.hasUpdate) {
        await maybeShowVersionUpdate(context, ref, r);
      }

      if (!mounted) return;

      // 2. 第二步：版本更新弹窗处理完成后（用户点击「稍后再说」或无需更新），再按顺序展示后台公告与通知
      final auth = ref.read(xboardAuthProvider);
      if (auth.loggedIn) {
        await maybeShowLatestAnnouncement(context, ref);
        if (mounted) {
          await maybeShowResellerPopup(context, ref);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(xboardAuthProvider);

    if (!auth.restored || !_startupReady) {
      // 会话恢复中:极简 splash,避免闪现登录页。
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.loggedIn) {
      // 登录页时，如果是强制更新，也第一时间弹出阻断提示
      final r = _endpointResult;
      if (r != null && r.hasUpdate && r.updateForce) {
        _dispatchStartupDialogs();
      }
      return const LoginPage();
    }

    // 已登录:按顺序检查并弹窗（版本更新优先，通知排后，杜绝冲突）
    _dispatchStartupDialogs();
    return widget.child;
  }
}
