// 登录门控 —— 未登录显示 LoginPage,已登录显示 FlClash 主界面。
// 已登录时还会:①首帧弹一次启动公告(Reseller 插件后台可配);②在屏幕右侧加一个
// 「代理中心」拉手按钮(打开下线/收益/提现页)。这样无需改 FlClash 核心 UI。
//
// 接入(改 lib/application.dart 一处,若已接过则无需再改):
//   把 MaterialApp 的  home: child!   改成   home: XboardGate(child: child!),

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_auth.dart';
import 'login_page.dart';
import 'agent_center_page.dart';
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

    // FlClash 主界面 + 右侧「代理中心」拉手(不改 FlClash 核心,保证可达)。
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          right: 0,
          top: MediaQuery.of(context).size.height * 0.42,
          child: SafeArea(
            child: Material(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AgentCenterPage()),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  child: Icon(
                    Icons.groups_outlined,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
