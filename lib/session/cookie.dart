import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';

import '../api/login.dart';
import 'account.dart';
import '../platform.dart';
import '../utils/storage.dart';

class CookieInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.headers['Cookie'] == null){
      final uri = options.uri;
      List<Cookie> cookies = [];
      CookieJar? cookieJar= CookieManager.isLoggingIn ?
      CookieManager.getTempCookieJar() : CookieManager.getCurrentUserCookieJar();
      if (cookieJar != null) {
        cookies = await cookieJar.loadForRequest(uri);
      }

      if (cookies.isNotEmpty) {
        final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
        options.headers['Cookie'] = cookieStr;

        if (PlatformManager().isRainClassroom){
          final cookieMap = Map.fromEntries(cookies.map((c) => MapEntry(c.name, c.value)));
          if (cookieMap.containsKey('sid')){ // APP
            options.headers['x-csrftoken'] = cookieMap['x-csrftoken'];
            options.headers['x-uid'] = cookieMap['x-uid'];
            options.headers['sessionid'] = cookieMap['sessionid'];
          } else { // Web
            options.headers['x-client'] = 'web';
            options.headers['xt-agent'] = 'web';
          }
        }
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      final cookies = setCookieHeaders.map((s) => Cookie.fromSetCookieValue(s)).toList();
      
      if (CookieManager.isLoggingIn) {
        await CookieManager.tempSaveCookie(cookies);
      } else {
        final cookieJar = CookieManager.getCurrentUserCookieJar();
        if (cookieJar != null) {
          await cookieJar.saveFromResponse(response.realUri, cookies);
          await CookieManager.saveCurrentUserCookies();
        }
      }
    }
    handler.next(response);
  }
}

class CookieManager {
  static const cxDomain = '.chaoxing.com';
  static const rcDomain = '.yuketang.cn';
  static bool isLoggingIn = false;
  static final Map<String, CookieJar> _userCookieJars = {};
  static CookieJar? _tempCookieJar; // 临时保存登录的 Cookie

  static int refreshCounts = 0; // 只为每个平台刷新一次

  static Future<void> initialize() async {
    await loadAllCookies();
  }

  static Future<void> loadAllCookies() async {
    // 获取所有账号并预加载 CookieJar
    final accounts = AccountManager.allAccounts;
    if (accounts.isEmpty) {
      return;
    }

    for (final user in accounts) {
      try {
        await getCookieJarForUser(user.uid);
      } catch (e) {
        debugPrint('预加载账号 ${user.uid} 的 CookieJar 失败：$e');
      }
    }

    if (refreshCounts < 2){
      await _refreshAccounts();
    }
  }

  /// 刷新所有账号的Cookie和用户信息
  static Future<void> _refreshAccounts() async {
    refreshCounts++;
    final accounts = AccountManager.allAccounts;

    int successCount = 0;
    int failCount = 0;

    final currentUserId = AccountManager.currentSessionId;

    final getUserInfoApi = PlatformManager().isChaoxing?
    CXLoginApi.getUserInfo : RCLoginApi.getUserInfo;

    for (final user in accounts) {
      try {
        AccountManager.setCurrentSessionTemp(user.uid);
        final refreshedUser = await getUserInfoApi();

        if (refreshedUser != null) {
          await AccountManager.addAccount(refreshedUser);
          successCount++;
        } else {
          user.setStatus(false);
        }
      } catch (e) {
        failCount++;
        debugPrint('刷新账号 ${user.name} 失败：$e');
      }
    }
    AccountManager.setCurrentSessionTemp(currentUserId);

    if (successCount > 0 || failCount > 0) {
      debugPrint('账号刷新完成：成功 $successCount 个，失败 $failCount 个');
    }
  }

  static Uri getDomainUri() {
    return PlatformManager().isChaoxing?
    Uri.parse('https://$cxDomain') : Uri.parse('https://$rcDomain');
  }

  /// 临时保存Cookie到内存
  static Future<void> tempSaveCookie(List<Cookie> cookies) async {
    _tempCookieJar ??= CookieJar();
    
    for (var cookie in cookies) {
      late Uri uri;
      if (cookie.domain != null && cookie.domain!.isNotEmpty) {
        uri = Uri.parse('https://${cookie.domain}');
      } else {
        uri = getDomainUri();
        cookie.domain = uri.host;
        // 雨课堂的SetCookie没有domain
      }
      await _tempCookieJar!.saveFromResponse(uri, [cookie]);
    }
  }

  /// 获取临时 CookieJar
  static CookieJar? getTempCookieJar() {
    return _tempCookieJar;
  }

  static Future<CookieJar> getCookieJarForUser(String userId) async {
    if (_userCookieJars.containsKey(userId)) {
      return _userCookieJars[userId]!;
    }

    final cookieJar = CookieJar();
    _userCookieJars[userId] = cookieJar;
    await _loadCookiesForUser(userId, cookieJar);
    return cookieJar;
  }

  /// 加载用户的 Cookie
  static Future<void> _loadCookiesForUser(String userId, CookieJar cookieJar) async {
    final String? cookiesJson = StorageManager.prefs.getString('cookies_$userId');
    if (cookiesJson == null) return;

    try {
      final List<dynamic> cookiesData = json.decode(cookiesJson);
      for (var cookieData in cookiesData) {
        final cookie = Cookie(
          cookieData['name'] as String,
          cookieData['value'] as String,
        );
        if (cookieData.containsKey('domain') && cookieData['domain'] != null) {
          cookie.domain = cookieData['domain'] as String;
        }
        if (cookieData.containsKey('path') && cookieData['path'] != null) {
          cookie.path = cookieData['path'] as String;
        }
        if (cookieData.containsKey('secure') && cookieData['secure'] != null) {
          cookie.secure = cookieData['secure'] as bool;
        }
        if (cookieData.containsKey('httpOnly') && cookieData['httpOnly'] != null) {
          cookie.httpOnly = cookieData['httpOnly'] as bool;
        }

        if (cookie.domain != null && cookie.domain!.isNotEmpty) {
          final uri = Uri.parse('https://${cookie.domain}');
          await cookieJar.saveFromResponse(uri, [cookie]);
        }
      }
    } catch (e) {
      debugPrint('用户 $userId 的 Cookie 加载失败：$e');
    }
  }

  /// 保存指定用户的 Cookie 到 SharedPreferences
  static Future<void> saveCookiesForUser(String userId) async {
    final jar = await getCookieJarForUser(userId);
    final domainUri = getDomainUri();
    final cookies = await jar.loadForRequest(domainUri);
    final List<Map<String, dynamic>> cookiesData = [];
    for (var cookie in cookies) {
      cookiesData.add({
        'name': cookie.name,
        'value': cookie.value,
        'domain': cookie.domain ?? (AccountManager.getAccountById(userId)?.isChaoxing ?? true ? cxDomain : rcDomain),
        'path': cookie.path ?? '/',
        'secure': cookie.secure,
        'httpOnly': cookie.httpOnly,
      });
    }

    await StorageManager.prefs.setString('cookies_$userId', json.encode(cookiesData));
  }

  /// 保存当前用户的 Cookie
  static Future<void> saveCurrentUserCookies() async {
    final currentUserId = AccountManager.currentSessionId;
    if (currentUserId != null) {
      await saveCookiesForUser(currentUserId);
    }
  }

  static CookieJar? getCurrentUserCookieJar() {
    final currentUserId = AccountManager.currentSessionId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return null;
    }
    final cookieJar = _userCookieJars[currentUserId];

    return cookieJar;
  }

  /// 清除指定用户的所有 Cookie
  static Future<void> clearCookiesForUser(String userId) async {
    _userCookieJars.remove(userId);
    await StorageManager.prefs.remove('cookies_$userId');
  }

  /// 清除当前用户的 Cookie
  static Future<void> clearCurrentUserCookies() async {
    final currentUserId = AccountManager.currentSessionId;
    if (currentUserId != null) {
      await clearCookiesForUser(currentUserId);
    }
  }

  /// 临时Cookie保存到账号
  static Future<void> saveTempCookies(String userId) async {
    final tempJar = getTempCookieJar();
    if (tempJar == null) return;

    final targetJar = await getCookieJarForUser(userId);
    final domainUri = getDomainUri();
    final tempCookies = await tempJar.loadForRequest(domainUri);

    for (var cookie in tempCookies) {
      if (cookie.domain != null && cookie.domain!.isNotEmpty) {
        final uri = Uri.parse('https://${cookie.domain}');
        await targetJar.saveFromResponse(uri, [cookie]);
      }
    }
    _tempCookieJar?.deleteAll();

    await saveCookiesForUser(userId);
  }
}