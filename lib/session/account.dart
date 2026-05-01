import 'dart:async';
import 'dart:convert';
import '../models/user.dart';
import '../platform.dart';
import 'cookie.dart';
import '../push/easemob.dart';
import '../utils/storage.dart';
import '../pages/accounts.dart' show AccountChangeNotifier;


/// 统一的账户管理器
class AccountManager {
  static const _chaoxingSessionKey = 'chaoxing_current_session';
  static const _rainClassroomSessionKey = 'rainclassroom_current_session';
  static const _chaoxingAccountsKey = 'chaoxing_accounts';
  static const _rainClassroomAccountsKey = 'rainclassroom_accounts';

  static List<User> _accounts = [];
  static String? _currentSessionId;

  /// 从存储中获取所有账户（异步，从当前平台读取）
  static Future<List<User>> _getAllAccountsFromStorage() async {
    final accountsKey = PlatformManager().isChaoxing ?
    _chaoxingAccountsKey : _rainClassroomAccountsKey;
    
    final String? accountsJson = StorageManager.prefs.getString(accountsKey);
    if (accountsJson != null) {
      final List<dynamic> accountsData = json.decode(accountsJson);
      return accountsData.map((data) => User.fromJson(data)).toList();
    }
    return [];
  }

  /// 保存账户列表到存储（保存到当前平台）
  static Future<void> _saveAccounts(List<User> accounts) async {
    final accountsKey = PlatformManager().isChaoxing ?
    _chaoxingAccountsKey : _rainClassroomAccountsKey;
    
    final accountsJson = json.encode(accounts.map((u) => u.toJson()).toList());
    await StorageManager.prefs.setString(accountsKey, accountsJson);
    // 同步更新缓存
    _accounts = accounts;
  }

  // ========== 对外公开方法 ==========

  /// 初始化账户管理器
  static Future<void> initialize() async {
    _accounts = await _getAllAccountsFromStorage();
    _currentSessionId = await getCurrentSession();
  }

  /// 获取当前会话的用户 ID（同步，使用缓存）
  static String? get currentSessionId => _currentSessionId;
  
  /// 获取当前会话的用户 ID
  static Future<String?> getCurrentSession() async {
    final sessionKey = PlatformManager().isChaoxing ?
    _chaoxingSessionKey : _rainClassroomSessionKey;
    _currentSessionId = StorageManager.prefs.getString(sessionKey);
    return _currentSessionId;
  }

  /// 设置当前会话的用户 ID
  static Future<void> setCurrentSession(String? userId) async {
    _currentSessionId = userId;
    final sessionKey = PlatformManager().isChaoxing ?
    _chaoxingSessionKey : _rainClassroomSessionKey;

    if (userId != null) {
      await StorageManager.prefs.setString(sessionKey, userId);
      final user = getAccountById(userId)!;
      if (user.imAccount != null) {
        EasemobIM().logout().then((_) {
          EasemobIM().loginCurrentUser();
        });
      }
    } else {
      EasemobIM().logout();
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

  /// 从存储中获取账户列表
  static Future<void> refreshAccounts() async {
    _accounts = await _getAllAccountsFromStorage();
  }

  /// 获取所有账户
  static List<User> getAllAccounts() {
    return _accounts;
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
    // 将临时Cookie迁移到该账号
    await CookieManager.saveTempCookies(user.uid);
    if (index != -1) {
      accounts[index] = user;
    } else {
      accounts.add(user);
      // 如果没有当前会话，自动设置为当前账户
      if (!hasActiveSession()) {
        await setCurrentSession(user.uid);
        AccountChangeNotifier().notifyAccountChanged(user.uid);
        if (user.imAccount != null) {
          EasemobIM().login(user.imAccount!['userName']!, user.imAccount!['password']!);
        }
      }
    }
    await _saveAccounts(accounts);
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
    final sessionKey = PlatformManager().isChaoxing ?
    _chaoxingSessionKey : _rainClassroomSessionKey;
    await StorageManager.prefs.remove(sessionKey);
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