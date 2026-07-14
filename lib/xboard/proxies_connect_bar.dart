// 节点页底部常驻栏:「智能 / 全局」模式切换 +「服务模式(TUN)」开关 +「连接 / 断开」按钮。
//
// 智能(规则):国内直连、国外走节点(推荐);全局:所有流量都走当前选中节点。
// 服务模式(虚拟网卡/TUN):接管所有应用的流量,无视应用自身是否支持代理。
//
// provider 全来自 providers barrel,无需新增依赖:
//   isStartProvider / commonActionProvider.updateStart()
//   patchClashConfigProvider.mode / setupActionProvider.changeMode(Mode)
//   patchClashConfigProvider.tun.enable(服务模式开关)
//
// 注入方式见文件末尾(改 lib/views/proxies/proxies.dart 一处 body;若已注入过就无需再动)。

import 'package:fl_clash/enum/enum.dart'; // Mode { rule, global, direct }
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Color _kIndigo = Color(0xFF2B2F77);
const Color _kGreen = Color(0xFF2E7D53);
const Color _kRed = Color(0xFFB23A48);

// 鼠标悬停提示文案(按你给的图片)。
const String _kSmartTip =
    '根据规则判断是否要经过节点,例如访问谷歌、Youtube 等中国境外资源会经过节点,'
    '而访问百度、新浪等中国境内资源则不经过。推荐使用该模式。';
const String _kGlobalTip =
    '所有网络请求都会经过节点,例如访问百度、新浪等中国境内网站也将经过节点,'
    '会受境内无落地节点的网速影响。该模式建议仅当访问未包含进规则的网络请求导致没经过节点时启用。';

class ProxiesConnectBar extends ConsumerWidget {
  const ProxiesConnectBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isStart = ref.watch(isStartProvider);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final tunEnable =
        ref.watch(patchClashConfigProvider.select((s) => s.tun.enable));

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
            // 智能 / 全局 分段切换(鼠标悬停显示模式说明)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _seg(context, '智能', _kSmartTip, mode == Mode.rule,
                      () => ref.read(setupActionProvider.notifier).changeMode(Mode.rule)),
                  _seg(context, '全局', _kGlobalTip, mode == Mode.global, () {
                    // 全局跟随你选中的节点:把 mihomo 的 GLOBAL 组指向你的主节点组,
                    // 这样 GLOBAL → 你的组 → 你当前选的节点(以后换节点也自动跟随)。
                    final others = ref
                        .read(groupsProvider)
                        .where((g) => g.name != GroupName.GLOBAL.name)
                        .toList();
                    if (others.isNotEmpty) {
                      final primary = others.first.name;
                      ref
                          .read(profilesActionProvider.notifier)
                          .updateCurrentSelectedMap(GroupName.GLOBAL.name, primary);
                      ref
                          .read(proxiesActionProvider.notifier)
                          .changeProxyDebounce(GroupName.GLOBAL.name, primary);
                    }
                    ref.read(setupActionProvider.notifier).changeMode(Mode.global);
                  }),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 服务模式(虚拟网卡 / TUN)
            _serviceModeRow(context, ref, tunEnable),
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
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

  Widget _serviceModeRow(BuildContext context, WidgetRef ref, bool enable) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('服务模式',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text('TUN模式支持所有应用,无视应用是否有代理功能',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          Switch(
            value: enable,
            activeColor: _kIndigo,
            onChanged: (value) {
              ref
                  .read(patchClashConfigProvider.notifier)
                  .update((state) => state.copyWith.tun(enable: value));
            },
          ),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, String tip, bool active,
      VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 300),
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
      ),
    );
  }
}
