import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final accessControl = ref.watch(
      vpnSettingProvider.select((state) => state.accessControlProps),
    );
    final isSmartMode = mode == Mode.rule;
    final String accessSubtitle;
    if (!isSmartMode) {
      accessSubtitle = '仅智能模式下可用（当前为全局模式，所有应用均走代理）';
    } else if (!accessControl.enable) {
      accessSubtitle = '未开启（所有应用按智能分流规则运行）';
    } else if (accessControl.mode == AccessControlMode.acceptSelected) {
      accessSubtitle = '白名单模式 · 仅 ${accessControl.acceptList.length} 个选中应用走代理';
    } else {
      accessSubtitle = '黑名单模式 · ${accessControl.rejectList.length} 个选中应用强制直连';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          if (system.isAndroid)
            ListTile(
              enabled: isSmartMode,
              leading: const Icon(Icons.apps_rounded),
              title: const Text('分应用代理'),
              subtitle: Text(accessSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: isSmartMode
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccessView()),
                    )
                  : null,
            ),
          ListTile(
            leading: const Icon(Icons.style),
            title: const Text('主题'),
            subtitle: const Text('外观 / 深浅色 / 主题色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeView()),
            ),
          ),
        ],
      ),
    );
  }
}
