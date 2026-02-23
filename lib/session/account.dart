import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'cookie.dart';


/// 统一的账户管理器
class AccountManager {
  static const String _sessionKey = 'current_session';
  static const String _accountsKey = 'accounts';

  // 缓存机制，避免频繁读取 SharedPreferences
  static List<User> _cachedAccounts = [];
  static bool _cacheInitialized = false;

  /// 确保缓存已加载
  static Future<void> _ensureCacheLoaded() async {
    if (!_cacheInitialized) {
      _cachedAccounts = await _getAllAccountsFromStorage();
      _cacheInitialized = true;
    }
  }

  /// 从存储中获取所有账户
  static Future<List<User>> _getAllAccountsFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? accountsJson = prefs.getString(_accountsKey);
    if (accountsJson != null) {
      final List<dynamic> accountsData = json.decode(accountsJson);
      return accountsData.map((data) => User.fromJson(data)).toList();
    }
    return [];
  }

  /// 保存账户列表到存储
  static Future<void> _saveAccounts(List<User> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = json.encode(accounts.map((u) => u.toJson()).toList());
    await prefs.setString(_accountsKey, accountsJson);
    // 同步更新缓存
    _cachedAccounts = accounts;
  }

  // ========== 对外公开方法 ==========

  /// 初始化账户管理器（可选，预加载缓存）
  static Future<void> initialize() async {
    await _ensureCacheLoaded();
  }

  /// 获取当前会话的用户ID
  static Future<String?> getCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  /// 设置当前会话的用户ID
  static Future<void> setCurrentSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, userId);
    await _ensureCacheLoaded();
    // 账号变更通知已在 accounts.dart 中处理
  }

  /// 检查是否存在活跃会话
  static Future<bool> hasActiveSession() async {
    final session = await getCurrentSession();
    return session != null && session.isNotEmpty;
  }

  /// 获取所有账户（同步，使用缓存）
  static List<User> getAllAccounts() {
    if (!_cacheInitialized) {
      return [];
    }
    return _cachedAccounts;
  }

  /// 异步获取所有账户（直接从存储读取，可用于强制刷新）
  static Future<List<User>> getAllAccountsAsync() async {
    final accounts = await _getAllAccountsFromStorage();
    // 更新缓存
    _cachedAccounts = accounts;
    _cacheInitialized = true;
    return accounts;
  }

  /// 根据ID获取账户（同步，使用缓存）
  static User? getAccountById(String userId) {
    if (!_cacheInitialized) return null;
    try {
      return _cachedAccounts.firstWhere((acc) => acc.uid == userId);
    } catch (e) {
      return null;
    }
  }

  /// 根据ID获取账户（异步）
  static Future<User?> getAccountByIdAsync(String userId) async {
    final accounts = await getAllAccountsAsync();
    try {
      return accounts.firstWhere((acc) => acc.uid == userId);
    } catch (e) {
      return null;
    }
  }

  /// 添加账户（如果已存在则更新）
  static Future<void> addAccount(User user) async {
    final accounts = await _getAllAccountsFromStorage();
    final index = accounts.indexWhere((acc) => acc.uid == user.uid);
    if (index != -1) {
      accounts[index] = user; // 更新
    } else {
      accounts.add(user); // 新增
    }
    await _saveAccounts(accounts);
    _cacheInitialized = true;

    // 如果没有当前会话，自动设置为当前账户
    if (!await hasActiveSession()) {
      await setCurrentSession(user.uid);
    }
  }

  /// 删除账户
  static Future<void> removeAccount(String userId) async {
    final accounts = await _getAllAccountsFromStorage();
    accounts.removeWhere((acc) => acc.uid == userId);
    await _saveAccounts(accounts);
    _cacheInitialized = true;

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
    _cacheInitialized = true;

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

  /// 更新账户信息（完全替换）
  static Future<void> updateAccount(User user) async {
    await addAccount(user); // addAccount 已包含更新逻辑
  }

  /// 清除当前会话（仅清除会话ID，不清除账户数据）
  static Future<void> clearCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = await getCurrentSession(); // 获取当前用户 ID
    await prefs.remove(_sessionKey);

    // 清除当前用户的 Cookie
    if (currentUserId != null) {
      await CookieManager.clearCookiesForUser(currentUserId);
    }
  }

  /// 清空所有会话和账户数据
  static Future<void> clearAllSessions() async {
    final prefs = await SharedPreferences.getInstance();

    // 清除所有用户的 Cookie（先获取所有账户）
    final allAccounts = await _getAllAccountsFromStorage();
    for (var user in allAccounts) {
      await CookieManager.clearCookiesForUser(user.uid);
    }

    await prefs.remove(_accountsKey);
    await prefs.remove(_sessionKey);
    _cachedAccounts = [];
    _cacheInitialized = true;
  }

  /// 获取账户数量（同步）
  static int get accountCount {
    if (!_cacheInitialized) return 0;
    return _cachedAccounts.length;
  }
}