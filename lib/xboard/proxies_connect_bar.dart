// 节点页底部常驻栏:「规则 / 全局」模式切换 + 「连接 / 断开」按钮。
//
// 放在节点列表下方,用户选好节点后可直接连接,不用再跑去仪表盘。
// 全局模式会把所有流量强制走当前选中节点(绕开规则里 DIRECT 默认组的坑);
// 规则模式则国内直连、国外走节点。
//
// 用到的 FlClash provider 全部来自 providers barrel,无需新增任何依赖:
//   isStartProvider                         -> bool 当前是否已连接(= 内核在跑)
//   commonActionProvider.updateStart()      -> 切换启动/停止(自读当前状态取反)
//   patchClashConfigProvider.mode           -> 当前出站模式 Mode{rule,global,direct}
//   setupActionProvider.changeMode(Mode)    -> 切模式(global 会同时把当前组切到 GLOBAL)
//
// 注入方式见文件末尾注释(改 lib/views/proxies/proxies.dart 一处 body)。

import 'package:fl_clash/enum/enum.dart'; // Mode { rule, global, direct }
import 'package:fl_clash/providers/providers.dart'; // isStart/common/setup/patchClashConfig
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Color _kIndigo = Color(0xFF2B2F77);
const Color _kGreen = Color(0xFF2E7D53); // 未连接:绿色「连接」
const Color _kRed = Color(0xFFB23A48); // 已连接:红色「断开」

class ProxiesConnectBar extends ConsumerWidget {
  const ProxiesConnectBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isStart = ref.watch(isStartProvider);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withOpacity(0.4)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 连接状态小标
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle,
                    size: 9, color: isStart ? _kGreen : theme.hintColor),
                const SizedBox(width: 6),
                Text(
                  isStart ? '已连接' : '未连接',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isStart ? _kGreen : theme.hintColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 规则 / 全局 分段切换
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _seg(context, '规则', mode == Mode.rule,
                      () => ref.read(setupActionProvider.notifier).changeMode(Mode.rule)),
                  _seg(context, '全局', mode == Mode.global,
                      () => ref.read(setupActionProvider.notifier).changeMode(Mode.global)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 连接 / 断开
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () =>
                    ref.read(commonActionProvider.notifier).updateStart(),
                icon: Icon(
                    isStart ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(
                  isStart ? '断开' : '连接',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isStart ? _kRed : _kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _kIndigo : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : theme.hintColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 注入(改 FlClash 原文件 lib/views/proxies/proxies.dart,仅一处):
//
// 1) 顶部 import 区加一行:
//      import 'package:fl_clash/xboard/proxies_connect_bar.dart';
//
// 2) 把 CommonScaffold 的  body: switch (proxiesType) { ... }  换成:
//      body: Column(
//        children: [
//          Expanded(
//            child: switch (proxiesType) {
//              ProxiesType.tab => ProxiesTabView(key: _proxiesTabKey),
//              ProxiesType.list => const ProxiesListView(),
//            },
//          ),
//          const ProxiesConnectBar(),
//        ],
//      ),
//
//   注意:节点列表那段必须包在 Expanded 里,否则列表高度无界会报错。
// ───────────────────────────────────────────────────────────────────────────
