import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_service.dart';
import '../session/account.dart';

/// 平台类型枚举
enum PlatformType {
  chaoxing, // 学习通
  rainClassroom // 雨课堂
}

/// 平台状态管理器
class PlatformManager {
  static final PlatformManager _instance = PlatformManager._internal();
  factory PlatformManager() => _instance;
  PlatformManager._internal();

  late SharedPreferences _prefs;
  static const _platformKey = 'current_platform';
  PlatformType _currentPlatform = PlatformType.chaoxing;

  /// 获取当前平台
  PlatformType get currentPlatform => _currentPlatform;

  bool get isChaoxing => _currentPlatform == PlatformType.chaoxing;
  bool get isRainClassroom => _currentPlatform == PlatformType.rainClassroom;

  /// 初始化平台
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final platformStr = _prefs.getString(_platformKey);

      if (platformStr != null && platformStr.isNotEmpty) {
        switch (platformStr.toLowerCase()) {
          case 'chaoxing':
            _currentPlatform = PlatformType.chaoxing;
            break;
          case 'rainclassroom':
            _currentPlatform = PlatformType.rainClassroom;
            break;
        }
      }

      // 触发平台变化回调，初始化 headers
      if (ApiService.onPlatformChange != null) {
        ApiService.onPlatformChange!(_currentPlatform);
      }
    } catch (e) {
      debugPrint('加载平台失败：$e');
    }
  }

  /// 设置平台
  Future<void> setPlatform(PlatformType platform) async {
    final oldPlatform = _currentPlatform;

    if (oldPlatform != platform) {
      _currentPlatform = platform;
      try {
        await _prefs.setString(_platformKey, currentPlatformName);
      } catch (e) {
        debugPrint('保存平台失败：$e');
      }
      await AccountManager.switchToPlatformAccount();
      ApiService.onPlatformChange?.call(platform);
    }
  }

  /// 获取平台字符串标识
  String get currentPlatformName {
    return _currentPlatform == PlatformType.chaoxing ?
    'chaoxing' : 'rainClassroom';
  }
}
