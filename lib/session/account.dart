import 'dart:async';
import 'dart:convert';
import '../models/user.dart';
import '../platform.dart';
import 'cookie.dart';
import '../push/easemob.dart';
import '../utils/storage.dart';

class AccountChangeNotifier {
  static final AccountChangeNotifier _instance = AccountChangeNotifier._internal();
  factory AccountChangeNotifier() => _instance;
  AccountChangeNotifier._internal();

  final StreamController<void> _controller = StreamController.broadcast();

  Stream<void> get accountChanges => _controller.stream;

  void notifyAccountChanged() {
    _controller.add(null);
  }
}

/// 统一的账户管理器
class AccountManager {
  static const _chaoxingSessionKey = 'chaoxing_current_session';
  static const _rainClassroomSessionKey = 'rainclassroom_current_session';
  static const _chaoxingAccountsKey = 'chaoxing_accounts';
  static const _rainClassroomAccountsKey = 'rainclassroom_accounts';

  static String get _sessionKey => PlatformManager().isChaoxing ?
    _chaoxingSessionKey : _rainClassroomSessionKey;

  static String get _accountsKey => PlatformManager().isChaoxing ?
    _chaoxingAccountsKey : _rainClassroomAccountsKey;

  static List<User> _accounts = [];
  static String? _currentSessionId;

  /// 获取所有账户
  static List<User> get allAccounts => _accounts;

  /// 获取当前会话的用户 ID（同步，使用缓存）
  static String? get currentSessionId => _currentSessionId;


  /// 初始化账户管理器
  static Future<void> initialize() async {
    _accounts = await _getAllAccountsFromStorage();
    _currentSessionId = await getCurrentSession();
  }

  /// 从存储中获取所有账户（异步，从当前平台读取）
  static Future<List<User>> _getAllAccountsFromStorage() async {
    final accountsJson = StorageManager.prefs.getString(_accountsKey);
    if (accountsJson != null) {
      final List<dynamic> accountsData = json.decode(accountsJson);
      return accountsData.map((data) => User.fromJson(data)).toList();
    }
    return [];
  }

  /// 保存账户列表到存储（保存到当前平台）
  static Future<void> _saveAccounts() async {
    final accountsJson = json.encode(_accounts.map((u) => u.toJson()).toList());
    await StorageManager.prefs.setString(_accountsKey, accountsJson);
  }
  
  /// 获取当前会话的用户 ID
  static Future<String?> getCurrentSession() async {
    _currentSessionId = StorageManager.prefs.getString(_sessionKey);
    return _currentSessionId;
  }

  /// 设置当前会话的用户 ID
  static Future<void> setCurrentSession(String? userId) async {
    _currentSessionId = userId;

    if (userId != null) {
      StorageManager.prefs.setString(_sessionKey, userId);
      final user = getAccountById(userId)!;
      _accounts.remove(user);
      _accounts.insert(0, user);
      _saveAccounts();
      // 当前账号始终在列表开头

      if (getAccountById(userId)!.imAccount != null) {
        if (EasemobIM().isLoggedIn) {
          EasemobIM().logout().then((_) {
            EasemobIM().loginCurrentAccount();
          });
        }
      }
    } else {
      StorageManager.prefs.remove(_sessionKey);

      if (PlatformManager().isChaoxing) {
        EasemobIM().logout();
      }
    }
    AccountChangeNotifier().notifyAccountChanged();
  }

  /// 临时设置当前会话的用户 ID 修改内存
  static void setCurrentSessionTemp(String? userId) {
    _currentSessionId = userId;
  }

  /// 检查是否存在活跃会话（同步，使用内存缓存）
  static bool hasActiveSession() {
    return _currentSessionId != null && _currentSessionId!.isNotEmpty;
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
    final index = _accounts.indexWhere((acc) => acc.uid == user.uid);
    // 将临时Cookie迁移到该账号
    await CookieManager.saveTempCookies(user.uid);
    if (index != -1) {
      _accounts[index] = user;
      if (user.uid == _currentSessionId) {
        AccountChangeNotifier().notifyAccountChanged();
      }
    } else {
      _accounts.add(user);
      // 如果没有当前会话，自动设置为当前账户
      if (!hasActiveSession()) {
        await setCurrentSession(user.uid);
        if (user.imAccount != null) {
          EasemobIM().login(user.imAccount!['userName']!, user.imAccount!['password']!);
        }
      }
    }
    _saveAccounts();
  }

  /// 批量删除账户
  static Future<void> removeAccounts(List<String> userIds) async {
    _accounts.removeWhere((acc) => userIds.contains(acc.uid));
    _saveAccounts();

    for (var uid in userIds) {
      if (uid == currentSessionId) {
        setCurrentSession(null);
      }
      await CookieManager.clearCookiesForUser(uid);
    }
  }

  /// 切换到对应平台的账号
  static Future<void> switchToPlatformAccounts() async {
    _accounts = await _getAllAccountsFromStorage();
    await CookieManager.loadAllCookies();
    final currentSession = await getCurrentSession();
    await setCurrentSession(currentSession);
  }
}