import 'package:flutter/foundation.dart';

import '../utils/storage.dart';

/// AI 调用设置
///
/// 出于安全考虑，API 地址与 Token 不再内置到程序中，均由用户自行填写并保存在本机。
class AiSetting {
  static const String _enabledKey = 'ai_enabled';
  static const String _baseUrlKey = 'ai_base_url';
  static const String _tokenKey = 'ai_token';
  static const String _modelKey = 'ai_model';
  static const String _promptKey = 'ai_prompt';
  static const String _systemPromptKey = 'ai_system_prompt';

  static const bool _defaultEnabled = true;

  /// 启用状态通知（设置页与答题页共享）
  static final ValueNotifier<bool> enabledNotifier =
      ValueNotifier<bool>(_defaultEnabled);

  /// API 地址通知
  static final ValueNotifier<String> baseUrlNotifier = ValueNotifier<String>('');

  /// Token 通知
  static final ValueNotifier<String> tokenNotifier = ValueNotifier<String>('');

  /// 当前选中模型通知
  static final ValueNotifier<String> modelNotifier = ValueNotifier<String>('');

  /// 用户提示词通知（空字符串表示使用默认模板）
  static final ValueNotifier<String> promptNotifier = ValueNotifier<String>('');

  /// 系统提示词通知（空字符串表示使用默认）
  static final ValueNotifier<String> systemPromptNotifier = ValueNotifier<String>('');

  /// 启动时从本地恢复
  static Future<void> init() async {
    final prefs = StorageManager.prefs;
    enabledNotifier.value = prefs.getBool(_enabledKey) ?? _defaultEnabled;
    baseUrlNotifier.value = prefs.getString(_baseUrlKey) ?? '';
    tokenNotifier.value = prefs.getString(_tokenKey) ?? '';
    modelNotifier.value = prefs.getString(_modelKey) ?? '';
    promptNotifier.value = prefs.getString(_promptKey) ?? '';
    systemPromptNotifier.value = prefs.getString(_systemPromptKey) ?? '';
  }

  static bool get enabled => enabledNotifier.value;

  static String get baseUrl => baseUrlNotifier.value;

  static String get token => tokenNotifier.value;

  static String get model => modelNotifier.value;

  static String get prompt => promptNotifier.value;

  static String get systemPrompt => systemPromptNotifier.value;

  /// 是否已填写地址与 Token
  static bool get isConfigured =>
      baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  static Future<void> setEnabled(bool value) async {
    enabledNotifier.value = value;
    await StorageManager.prefs.setBool(_enabledKey, value);
  }

  static Future<void> setBaseUrl(String value) async {
    final normalized = value.trim();
    baseUrlNotifier.value = normalized;
    await StorageManager.prefs.setString(_baseUrlKey, normalized);
  }

  static Future<void> setToken(String value) async {
    final normalized = value.trim();
    tokenNotifier.value = normalized;
    await StorageManager.prefs.setString(_tokenKey, normalized);
  }

  static Future<void> setModel(String model) async {
    modelNotifier.value = model;
    await StorageManager.prefs.setString(_modelKey, model);
  }

  static Future<void> clearModel() async {
    modelNotifier.value = '';
    await StorageManager.prefs.remove(_modelKey);
  }

  static Future<void> setPrompt(String value) async {
    promptNotifier.value = value;
    if (value.trim().isEmpty) {
      await StorageManager.prefs.remove(_promptKey);
    } else {
      await StorageManager.prefs.setString(_promptKey, value);
    }
  }

  static Future<void> setSystemPrompt(String value) async {
    systemPromptNotifier.value = value;
    if (value.trim().isEmpty) {
      await StorageManager.prefs.remove(_systemPromptKey);
    } else {
      await StorageManager.prefs.setString(_systemPromptKey, value);
    }
  }

  /// 清空全部 AI 配置（切换自己的服务时使用）
  static Future<void> clearAll() async {
    await setBaseUrl('');
    await setToken('');
    await clearModel();
  }

  /// 已保存的模型是否仍在最新拉取的列表中
  static bool isModelAvailable(List<String> models) =>
      modelNotifier.value.isNotEmpty && models.contains(modelNotifier.value);
}
