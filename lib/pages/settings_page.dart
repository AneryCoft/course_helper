import 'package:flutter/material.dart';

import '../push/update.dart';
import '../theme_mode_manager.dart';
import '../utils/logger.dart';
import 'about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const List<(ThemeMode, String)> _themeModes = [
    (ThemeMode.system, '跟随系统'),
    (ThemeMode.light, '浅色'),
    (ThemeMode.dark, '深色'),
  ];

  static String _modeLabel(ThemeMode mode) =>
      _themeModes.firstWhere((e) => e.$1 == mode, orElse: () => _themeModes.first).$2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            onTap: () => Update.checkUpdate(ignoreSkip: true),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出日志'),
            onTap: () async {
              final success = await exportLog();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? '日志已分享' : '日志分享失败'),
                  ),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题模式'),
            subtitle: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeModeManager.notifier,
              builder: (_, mode, _) => Text(_modeLabel(mode)),
            ),
            onTap: () => _showThemeDialog(context),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeModeManager.notifier,
          builder: (_, mode, _) {
            return AlertDialog(
              title: const Text('主题模式'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in _themeModes)
                    RadioListTile<ThemeMode>(
                      title: Text(e.$2),
                      value: e.$1,
                      groupValue: mode,
                      onChanged: (m) {
                        if (m != null) {
                          ThemeModeManager.setMode(m);
                          Navigator.of(ctx).pop();
                        }
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
