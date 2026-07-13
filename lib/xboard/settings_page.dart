// 「设置」页 —— 主题 + 语言。从工具页移出来单独成页,从「我的」页进入。
// 主题复用 FlClash 现成的 ThemeView(整页 BaseScaffold);语言读写 FlClash 的 appSettingProvider。
// 只耦合 ThemeView + appSettingProvider 两个 FlClash 公开 API,其余用标准组件,稳。

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appSettingProvider.select((s) => s.locale));
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.style),
            title: const Text('主题'),
            subtitle: const Text('外观 / 深浅色 / 主题色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeView()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('语言'),
            subtitle: Text(
              locale == null
                  ? context.appLocalizations.defaultText
                  : Intl.message(locale),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLocale(context, ref, locale),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLocale(
      BuildContext context, WidgetRef ref, String? current) async {
    const systemKey = '__system__';
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            RadioListTile<String>(
              value: systemKey,
              groupValue: current ?? systemKey,
              title: Text(ctx.appLocalizations.defaultText),
              onChanged: (_) => Navigator.pop(ctx, systemKey),
            ),
            for (final l in AppLocalizations.delegate.supportedLocales)
              RadioListTile<String>(
                value: l.toString(),
                groupValue: current ?? systemKey,
                title: Text(Intl.message(l.toString())),
                onChanged: (_) => Navigator.pop(ctx, l.toString()),
              ),
          ],
        ),
      ),
    );
    if (result == null) return; // 用户取消
    final newLocale = result == systemKey ? null : result;
    ref
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(locale: newLocale));
  }
}
