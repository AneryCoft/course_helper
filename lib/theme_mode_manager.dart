import 'package:flutter/material.dart';

import 'utils/storage.dart';

/// 全局主题模式管理：跟随系统 / 浅色 / 深色。
/// 通过 [notifier] 驱动 MaterialApp 的 themeMode 实时切换，并持久化到 SharedPreferences。
class ThemeModeManager {
  static const String _key = 'theme_mode';

  static final ValueNotifier<ThemeMode> notifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 在应用启动时调用，从本地存储恢复主题模式。
  static Future<void> init() async {
    final saved = StorageManager.prefs.getString(_key);
    if (saved == 'light') {
      notifier.value = ThemeMode.light;
    } else if (saved == 'dark') {
      notifier.value = ThemeMode.dark;
    } else {
      notifier.value = ThemeMode.system;
    }
  }

  /// 设置并持久化主题模式。
  static void setMode(ThemeMode mode) {
    notifier.value = mode;
    StorageManager.prefs.setString(_key, _toString(mode));
  }

  static String _toString(ThemeMode mode) {
    if (mode == ThemeMode.light) return 'light';
    if (mode == ThemeMode.dark) return 'dark';
    return 'system';
  }
}
