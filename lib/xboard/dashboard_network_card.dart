// 仪表盘「网络」快捷卡片 —— 局域网代理 / 端口 / IPv6。
// 这三项原来在「工具 → 基本配置」里,现搬到仪表盘直接操作。
// 用标准 Flutter 组件读写 FlClash 的 patchClashConfigProvider(与原基本配置同一份配置),
// 不依赖 FlClash 内部私有组件,也不需要 build_runner。

import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardNetworkCard extends ConsumerWidget {
  const DashboardNetworkCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allowLan =
        ref.watch(patchClashConfigProvider.select((s) => s.allowLan));
    final ipv6 = ref.watch(patchClashConfigProvider.select((s) => s.ipv6));
    final port = ref.watch(patchClashConfigProvider.select((s) => s.mixedPort));

    void setAllowLan(bool v) => ref
        .read(patchClashConfigProvider.notifier)
        .update((s) => s.copyWith(allowLan: v));
    void setIpv6(bool v) => ref
        .read(patchClashConfigProvider.notifier)
        .update((s) => s.copyWith(ipv6: v));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.device_hub),
            title: const Text('局域网代理'),
            subtitle: const Text('允许同一局域网内的其它设备使用本机代理'),
            value: allowLan,
            onChanged: setAllowLan,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.water_outlined),
            title: const Text('IPv6'),
            subtitle: const Text('开启 IPv6 支持'),
            value: ipv6,
            onChanged: setIpv6,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.adjust_outlined),
            title: const Text('端口'),
            subtitle: Text('$port'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editPort(context, ref, port),
          ),
        ],
      ),
    );
  }

  Future<void> _editPort(BuildContext context, WidgetRef ref, int current) async {
    final ctrl = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('代理端口'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '端口 (1024–49151)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 1024 || v > 49151) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('端口需在 1024–49151 之间')));
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      ref
          .read(patchClashConfigProvider.notifier)
          .update((s) => s.copyWith(mixedPort: result));
    }
  }
}
