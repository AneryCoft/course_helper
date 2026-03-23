import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../platform.dart';
import 'cookie.dart';


/// 统一的账户管理器
class AccountManager {
  static const _oldSessionKey = 'current_session'; // 旧的会话键名
  static const _oldAccountsKey = 'accounts'; // 旧的账号列表键名
  static const _chaoxingSessionKey = 'chaoxing_current_session';
  static const _rainClassroomSessionKey = 'rainclassroom_current_session';
  static const _chaoxingAccountsKey = 'chaoxing_accounts';
  static const _rainClassroomAccountsKey = 'rainclassroom_accounts';

  static late SharedPreferences _prefs;

  static List<User> _accounts = [];
  static String? _currentSessionId;

  /// 从存储中获取所有账户（异步，从当前平台读取）
  static Future<List<User>> _getAllAccountsFromStorage() async {
    final platform = PlatformManager().currentPlatform;
    final accountsKey = platform == PlatformType.chaoxing ?
    _chaoxingAccountsKey : _rainClassroomAccountsKey;
    
    final String? accountsJson = _prefs.getString(accountsKey);
    if (accountsJson != null) {
      final List<dynamic> accountsData = json.decode(accountsJson);
      return accountsData.map((data) => User.fromJson(data)).toList();
    }
    return [];
  }

  /// 保存账户列表到存储（保存到当前平台）
  static Future<void> _saveAccounts(List<User> accounts) async {
    final platform = PlatformManager().currentPlatform;
    final accountsKey = platform == PlatformType.chaoxing ?
    _chaoxingAccountsKey : _rainClassroomAccountsKey;
    
    final accountsJson = json.encode(accounts.map((u) => u.toJson()).toList());
    await _prefs.setString(accountsKey, accountsJson);
    // 同步更新缓存
    _accounts = accounts;
  }

  // ========== 对外公开方法 ==========

  /// 初始化账户管理器
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateOldSession(); // 迁移旧会话数据
    await _migrateOldAccounts(); // 迁移旧账号数据
    _accounts = await _getAllAccountsFromStorage();
    _currentSessionId = await getCurrentSession();
  }

  /// 迁移旧的会话数据到新格式（将 current_session 迁移到 chaoxing_current_session）
  static Future<void> _migrateOldSession() async {
    final oldSessionId = _prefs.getString(_oldSessionKey);
    
    if (oldSessionId != null && oldSessionId.isNotEmpty) {
      // 检查是否已经迁移过
      final chaoxingSession = _prefs.getString(_chaoxingSessionKey);
      if (chaoxingSession == null || chaoxingSession.isEmpty) {
        // 还没有迁移，执行迁移
        await _prefs.setString(_chaoxingSessionKey, oldSessionId);
        await _prefs.remove(_oldSessionKey); // 删除旧的键
        debugPrint('已将会话数据从 $_oldSessionKey 迁移到 $_chaoxingSessionKey');
      } else {
        // 已经迁移过了，直接删除旧键
        await _prefs.remove(_oldSessionKey);
      }
    }
  }

  /// 迁移旧的账号数据到新格式（将 accounts 迁移到 chaoxing_accounts）
  static Future<void> _migrateOldAccounts() async {
    final oldAccountsJson = _prefs.getString(_oldAccountsKey);
    
    if (oldAccountsJson != null && oldAccountsJson.isNotEmpty) {
      // 检查是否已经迁移过
      final chaoxingAccounts = _prefs.getString(_chaoxingAccountsKey);
      if (chaoxingAccounts == null || chaoxingAccounts.isEmpty) {
        // 还没有迁移，执行迁移
        await _prefs.setString(_chaoxingAccountsKey, oldAccountsJson);
        await _prefs.remove(_oldAccountsKey); // 删除旧的键
        debugPrint('已将账号数据从 $_oldAccountsKey 迁移到 $_chaoxingAccountsKey');
      } else {
        // 已经迁移过了，直接删除旧键
        await _prefs.remove(_oldAccountsKey);
      }
    }
  }

  /// 获取当前会话的用户 ID（同步，使用缓存）
  static String? get currentSessionId => _currentSessionId;
  
  /// 获取当前会话的用户 ID
  static Future<String?> getCurrentSession() async {
    final currentPlatform = PlatformManager().currentPlatform;

    final sessionKey = currentPlatform == PlatformType.chaoxing ?
    _chaoxingSessionKey : _rainClassroomSessionKey;
    _currentSessionId = _prefs.getString(sessionKey);
    debugPrint('当前SessionId：$_currentSessionId');
    return _currentSessionId;
  }

  /// 设置当前会话的用户 ID
  static Future<void> setCurrentSession(String? userId) async {
    _currentSessionId = userId;
    // 根据当前平台保存对应的会话 ID
    final platform = PlatformManager().currentPlatform;
    final sessionKey = platform == PlatformType.chaoxing ? 
    _chaoxingSessionKey : _rainClassroomSessionKey;
    
    if (userId != null) {
      await _prefs.setString(sessionKey, userId);
    }
  }

  /// 临时设置当前会话的用户 ID 修改内存
  static void setCurrentSessionTemp(String userId) {
    _currentSessionId = userId;
  }

  /// 检查是否存在活跃会话（同步，使用内存缓存）
  static bool hasActiveSession() {
    return _currentSessionId != null && _currentSessionId!.isNotEmpty;
  }

  /// 获取所有账户
  static List<User> getAllAccounts() {
    return _accounts;
  }

  /// 获取所有当前平台的账户
  static List<User> getPlatformsAllAccounts() {
    return _accounts.where((user) => user.platform == PlatformManager().currentPlatformName).toList();
  }

  /// 根据ID获取账户（同步，使用缓存）
  static User? getAccountById(String userId) {
    try {
      return _accounts.firstWhere((acc) => acc.uid == userId);
    } catch (e) {
      return null;
    }
  }

  /// 添加账户（如果已存在则更新）
  static Future<void> addAccount(User user) async {
    final accounts = _accounts;
    final index = accounts.indexWhere((acc) => acc.uid == user.uid);
    if (index != -1) {
      accounts[index] = user;
    } else {
      accounts.add(user);
    }
    await _saveAccounts(accounts);

    // 将临时Cookie迁移到该账号
    await CookieManager.saveTempCookies(user.uid);

    // 如果没有当前会话，自动设置为当前账户
    if (!hasActiveSession()) {
      await setCurrentSession(user.uid);
    }
  }

  /// 删除账户
  static Future<void> removeAccount(String userId) async {
    final accounts = await _getAllAccountsFromStorage();
    accounts.removeWhere((acc) => acc.uid == userId);
    await _saveAccounts(accounts);

    // 如果删除的是当前会话账户，则清除会话和该用户的 Cookie
    final current = await getCurrentSession();
    if (current == userId) {
      await clearCurrentSession();
    } else {
      // 如果不是当前用户，也要清除该用户的 Cookie 数据
      await CookieManager.clearCookiesForUser(userId);
    }
  }

  /// 批量删除账户
  static Future<void> removeAccounts(List<String> userIds) async {
    final accounts = await _getAllAccountsFromStorage();
    accounts.removeWhere((acc) => userIds.contains(acc.uid));
    await _saveAccounts(accounts);

    // 检查当前会话是否被删除
    final current = await getCurrentSession();
    if (current != null && userIds.contains(current)) {
      await clearCurrentSession();
    } else {
      // 对于其他被删除的用户，清除他们的 Cookie
      for (final uid in userIds) {
        if (uid != current) {
          await CookieManager.clearCookiesForUser(uid);
        }
      }
    }
  }

  /// 清除当前会话（仅清除会话 ID，不清除账户数据）
  static Future<void> clearCurrentSession() async {
    // 根据当前平台清除对应的会话 ID
    final platform = PlatformManager().currentPlatform;
    final sessionKey = platform == PlatformType.chaoxing ?
    _chaoxingSessionKey : _rainClassroomSessionKey;
    await _prefs.remove(sessionKey);
    final currentUserId = _currentSessionId;
    _currentSessionId = null;
    if (currentUserId != null) {
      await CookieManager.clearCookiesForUser(currentUserId);
    }
  }

  /// 切换到对应平台的账号
  static Future<void> switchToPlatformAccount() async {
    final currentSession = await getCurrentSession();
    await setCurrentSession(currentSession);
  }
}