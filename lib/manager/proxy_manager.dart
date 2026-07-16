import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxyManager extends ConsumerStatefulWidget {
  final Widget child;

  const ProxyManager({super.key, required this.child});

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pendingUpdate = Future.value();

  Future<void> _updateProxy(ProxyState proxyState) async {
    final isStart = proxyState.isStart;
    final systemProxy = proxyState.systemProxy;
    final port = proxyState.port;
    bool? result;
    if (isStart && systemProxy) {
      result = await proxy?.startProxy(port, proxyState.bassDomain);
    } else {
      result = await proxy?.stopProxy();
    }
    if (result == false) {
      commonPrint.log('update system proxy failed', logLevel: LogLevel.warning);
    }
  }

  void _scheduleUpdateProxy(ProxyState proxyState) {
    _pendingUpdate = _pendingUpdate
        .then((_) => _updateProxy(proxyState))
        .catchError((Object error) {
          commonPrint.log(
            'update system proxy failed: $error',
            logLevel: LogLevel.warning,
          );
        });
  }

  @override
  void initState() {
    super.initState();
    // 崩溃/异常退出自愈:每次启动先无条件清一次系统代理,清掉上次可能残留的
    // 127.0.0.1:端口(否则进程被强杀后没走到 stopProxy,整机会一直走已失效的
    // 代理导致上不了网),再交给下面的监听按当前实际状态重新设置。串进
    // _pendingUpdate 保证排在监听首次应用之前。TUN 侧无需在此处理:helper 启动
    // 时会 stop→start 复位残留内核,wintun 网卡随旧进程结束由系统回收。
    _pendingUpdate = _pendingUpdate
        .then((_) async {
          await proxy?.stopProxy();
          commonPrint.log('boot: reset stale system proxy');
        })
        .catchError((Object error) {
          commonPrint.log(
            'boot proxy reset failed: $error',
            logLevel: LogLevel.warning,
          );
        });
    ref.listenManual(proxyStateProvider, (prev, next) {
      if (prev != next) {
        _scheduleUpdateProxy(next);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
