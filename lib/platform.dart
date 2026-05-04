import 'package:course_helper/session/cookie.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import '../api/api_service.dart';
import '../session/account.dart';
import '../utils/storage.dart';

/// 平台类型枚举
enum PlatformType {
  chaoxing, // 学习通
  rainClassroom // 雨课堂
}

/// 雨课堂服务器类型枚举
enum RainClassroomServerType {
  yuketang, // 雨课堂
  pro, // 荷塘雨课堂
  changjiang, // 长江雨课堂
  huanghe // 黄河雨课堂
}

/// 平台状态管理器
class PlatformManager {
  static final PlatformManager _instance = PlatformManager._internal();
  factory PlatformManager() => _instance;
  PlatformManager._internal();

  static const _platformKey = 'current_platform';
  static const _serverKey = 'current_server';
  PlatformType _currentPlatform = PlatformType.chaoxing;
  RainClassroomServerType _currentServer = RainClassroomServerType.yuketang;
  
  // 平台变化通知流
  final StreamController<PlatformType> _platformChangeController = StreamController<PlatformType>.broadcast();
  Stream<PlatformType> get platformChanges => _platformChangeController.stream;

  /// 获取当前平台
  PlatformType get currentPlatform => _currentPlatform;

  bool get isChaoxing => _currentPlatform == PlatformType.chaoxing;
  bool get isRainClassroom => _currentPlatform == PlatformType.rainClassroom;
  
  /// 获取当前雨课堂服务器
  RainClassroomServerType get currentServer => _currentServer;

  /// 初始化平台
  Future<void> initialize() async {
    try {
      final platformStr = StorageManager.prefs.getString(_platformKey);

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
      
      // 加载雨课堂服务器设置
      final serverStr = StorageManager.prefs.getString(_serverKey);
      if (serverStr != null && serverStr.isNotEmpty) {
        switch (serverStr.toLowerCase()) {
          case 'yuketang':
            _currentServer = RainClassroomServerType.yuketang;
            break;
          case 'pro':
            _currentServer = RainClassroomServerType.pro;
            break;
          case 'changjiang':
            _currentServer = RainClassroomServerType.changjiang;
            break;
          case 'huanghe':
            _currentServer = RainClassroomServerType.huanghe;
            break;
        }
      }
      
      // 触发平台变化回调，初始化 headers
      ApiService.onPlatformChange!();
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
        StorageManager.prefs.setString(_platformKey, _currentPlatform.name);
      } catch (e) {
        debugPrint('保存平台失败：$e');
      }
      ApiService.onPlatformChange?.call();
      _platformChangeController.add(platform);
      await AccountManager.refreshAccounts();
      await AccountManager.switchToPlatformAccount();
      await CookieManager.loadAllCookies();
    }
  }
  
  /// 设置雨课堂服务器
  Future<void> setServer(RainClassroomServerType server) async {
    if (_currentServer != server) {
      _currentServer = server;
      try {
        StorageManager.prefs.setString(_serverKey, _currentServer.name);
      } catch (e) {
        debugPrint('保存服务器失败：$e');
      }
      ApiService.onPlatformChange?.call();
    }
  }
  
  void dispose() {
    _platformChangeController.close();
  }
}
