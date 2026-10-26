import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../push/update.dart';
import '../setting/ai_setting.dart';
import '../theme_mode_manager.dart';
import '../ui/design_tokens.dart';
import '../ui/widgets.dart';
import '../utils/logger.dart';
import 'about_page.dart';
import 'ai_setting_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<(ThemeMode, String, IconData)> _themeModes = [
    (ThemeMode.system, '跟随系统', Icons.brightness_auto_rounded),
    (ThemeMode.light, '浅色', Icons.light_mode_rounded),
    (ThemeMode.dark, '深色', Icons.dark_mode_rounded),
  ];

  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  static String _modeLabel(ThemeMode mode) => _themeModes
      .firstWhere((e) => e.$1 == mode, orElse: () => _themeModes.first)
      .$2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.bottomInset),
          children: [
            SliverPageHeaderProxy(
              title: '设置',
              subtitle: '个性化你的使用体验',
            ),

            // ---------- AI ----------
            const SectionLabel('智能助手'),
            _CardGroup(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: AiSetting.modelNotifier,
                  builder: (context, model, _) {
                    final configured = AiSetting.isConfigured;
                    return SettingsTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI 调用设置',
                      subtitle: !configured
                          ? '未配置 API 地址，点击前往设置'
                          : model.isEmpty
                              ? '尚未选择模型'
                              : model,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiSettingPage()),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: AiSetting.enabledNotifier,
                  builder: (context, enabled, _) => SwitchListTile(
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.tertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(Icons.smart_toy_outlined,
                          size: 21, color: cs.tertiary),
                    ),
                    title: const Text('启用 AI 答题'),
                    subtitle: const Text('答题页显示「一键生成答案」按钮'),
                    value: enabled,
                    onChanged: (v) => AiSetting.setEnabled(v),
                  ),
                ),
              ],
            ),

            // ---------- 外观 ----------
            const SectionLabel('外观'),
            _CardGroup(
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeModeManager.notifier,
                  builder: (context, mode, _) => SettingsTile(
                    icon: _themeModes
                        .firstWhere((e) => e.$1 == mode,
                            orElse: () => _themeModes.first)
                        .$3,
                    title: '主题模式',
                    subtitle: _modeLabel(mode),
                    onTap: () => _showThemeSheet(context),
                  ),
                ),
                SettingsTile(
                  icon: Icons.palette_outlined,
                  title: '动态取色',
                  subtitle: '跟随系统壁纸自动配色（Android 12+）',
                  trailing: MetaChip(
                    label: '自动',
                    icon: Icons.bolt_rounded,
                    color: cs.primary,
                  ),
                  onTap: null,
                ),
              ],
            ),

            // ---------- 通用 ----------
            const SectionLabel('通用'),
            _CardGroup(
              children: [
                SettingsTile(
                  icon: Icons.system_update_alt_rounded,
                  title: '检查更新',
                  subtitle: '发现新版本时提示下载',
                  onTap: () => Update.checkUpdate(ignoreSkip: true),
                ),
                SettingsTile(
                  icon: Icons.file_upload_outlined,
                  title: '导出日志',
                  subtitle: '便于反馈问题时排查',
                  onTap: () async {
                    final success = await exportLog();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? '日志已分享' : '日志分享失败')),
                      );
                    }
                  },
                ),
              ],
            ),

            // ---------- 关于 ----------
            const SectionLabel('关于'),
            _CardGroup(
              children: [
                SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: '关于课程助手',
                  subtitle: _version.isEmpty ? null : '版本 $_version',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Column(
                children: [
                  Text(
                    '课程助手',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '开源 · 为学习而做',
                    style: TextStyle(fontSize: 11, color: cs.outline.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showThemeSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text('主题模式', style: Theme.of(ctx).textTheme.titleLarge),
                ],
              ),
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeModeManager.notifier,
              builder: (ctx2, mode, _) => RadioGroup<ThemeMode>(
                groupValue: mode,
                onChanged: (m) {
                  if (m == null) return;
                  ThemeModeManager.setMode(m);
                  Navigator.of(ctx).pop();
                },
                child: Column(
                  children: [
                    for (final (value, label, icon) in _themeModes)
                      RadioListTile<ThemeMode>(
                        value: value,
                        title: Text(label),
                        secondary: Icon(icon),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// 圆角卡片分组容器：把多个设置项包成一张卡片
class _CardGroup extends StatelessWidget {
  final List<Widget> children;

  const _CardGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 68,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
