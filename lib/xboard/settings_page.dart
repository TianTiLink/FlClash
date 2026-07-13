import 'package:fl_clash/views/theme.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
