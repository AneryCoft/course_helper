import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';

import '../api/api_service.dart';
import '../api/login.dart';
import '../models/user.dart';
import 'account.dart';
import '../platform.dart';
import '../utils/storage.dart';

class CookieInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.headers['Cookie'] == null) {
      final uri = options.uri;
      List<Cookie> cookies = [];
      final String? userId = options.extra['userId'];

      if (userId != null) {
        CookieJar? cookieJar = userId.isEmpty ?
        CookieManager.tempCookieJar : CookieManager.getCookieJarForUser(userId);

        if (cookieJar != null) {
          cookies = await cookieJar.loadForRequest(uri);
        }

        if (cookies.isNotEmpty) {
          final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
          options.headers['Cookie'] = cookieStr;

          if (PlatformManager().isRainClassroom) {
            final cookieMap = Map.fromEntries(cookies.map((c) => MapEntry(c.name, c.value)));
            if (cookieMap.containsKey('sid')) { // APP
              options.headers['x-csrftoken'] = cookieMap['csrftoken'];
              options.headers['x-uid'] = userId;
              options.headers['sessionid'] = cookieMap['sessionid'];
            } else { // Web
              options.headers['x-client'] = 'web';
              options.headers['xt-agent'] = 'web';
            }
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

      final String? userId = response.requestOptions.extra['userId'];

      if (userId != null) {
        if (userId.isEmpty) {
          await CookieManager._tempCookieJar.saveFromResponse(response.realUri, cookies);
        } else {
          CookieJar? cookieJar = CookieManager.getCookieJarForUser(userId);

          if (cookieJar != null) {
            await cookieJar.saveFromResponse(response.realUri, cookies);
            CookieManager._saveCookiesToStorage(userId, cookieJar);
          }
        }
      }
    }
    handler.next(response);
  }
}

class CookieManager {
  static Uri get domainUri {
    return PlatformManager().isChaoxing ?
    Uri.parse('https://.chaoxing.com') : Uri.parse(ApiService.serverBaseUrlMap[PlatformManager().currentServer]!);
  }
  static final Map<String, CookieJar> _userCookieJars = {};
  static final CookieJar _tempCookieJar = CookieJar(); // 临时保存登录的 Cookie
  static CookieJar get tempCookieJar => _tempCookieJar;

  static int _refreshCounts = 0; // 只为每个平台刷新一次

  static Future<void> initialize() async {
    await loadAllCookies();
  }

  static Future<void> loadAllCookies() async {
    // 获取所有账号并预加载 CookieJar
    final accounts = AccountManager.allAccounts;
    if (accounts.isEmpty) {
      return;
    }

    await Future.wait(
      accounts.map((user) async {
        try {
          final cookieJar = CookieJar();
          _userCookieJars[user.uid] = cookieJar;
          await _loadCookiesForUser(user.uid, cookieJar);
        } catch (e) {
          debugPrint('预加载账号 ${user.uid} 的 CookieJar 失败：$e');
        }
      }),
    );

    if (_refreshCounts < 2) {
      await _refreshAccounts();
    }
  }

  /// 刷新所有账号的Cookie和用户信息
  static Future<void> _refreshAccounts() async {
    _refreshCounts++;
    final accounts = AccountManager.allAccounts;

    if (accounts.isEmpty) return;

    late List<User?> results;
    if (PlatformManager().isChaoxing) {
      results = await ApiService.sendForEachUser<User?>(
        accounts,
        (user) => CXLoginApi(user).getUserInfo(),
      );
    } else {
      results = await ApiService.sendForEachUser<User?>(
        accounts,
        (user) => RCLoginApi(user).getUserInfo(),
      );
    }

    // 处理结果
    int successCount = 0;
    int failCount = 0;
    for (int i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      final refreshedUser = results[i];

      if (refreshedUser != null) {
        await AccountManager.addAccount(refreshedUser);
        successCount++;
      } else {
        account.setStatus(false);
        failCount++;
      }
    }

    if (successCount > 0 || failCount > 0) {
      debugPrint('账号刷新完成：成功 $successCount 个，失败 $failCount 个');
    }
  }

  /// 从内存中获取用户 CookieJar
  static CookieJar? getCookieJarForUser(String userId) {
    return _userCookieJars[userId];
  }

  /// 加载用户的 Cookie
  static Future<void> _loadCookiesForUser(String userId, CookieJar cookieJar) async {
    final String? cookiesJson = StorageManager.prefs.getString('cookies_$userId');
    if (cookiesJson == null) return;

    try {
      final List<dynamic> cookiesData = json.decode(cookiesJson);
      final List<Cookie> cookies = [];
      
      for (var cookieData in cookiesData) {
        final cookie = Cookie(cookieData['name'], cookieData['value']);
        cookie.domain = cookieData['domain'];
        cookie.path = cookieData['path'] ?? '/';
        cookie.secure = cookieData['secure'] ?? false;
        cookie.httpOnly = cookieData['httpOnly'] ?? false;
        
        cookies.add(cookie);
      }
      await cookieJar.saveFromResponse(domainUri, cookies);
    } catch (e) {
      debugPrint('用户 $userId 的 Cookie 加载失败：$e');
    }
  }

  /// 将 CookieJar 保存到存储
  static Future<void> _saveCookiesToStorage(String userId, CookieJar jar) async {
    final cookies = await jar.loadForRequest(domainUri);
    final List<Map<String, dynamic>> cookiesData = [];
    for (var cookie in cookies) {
      cookiesData.add({
        'name': cookie.name,
        'value': cookie.value,
        'domain': cookie.domain,
        'path': cookie.path ?? '/',
        'secure': cookie.secure,
        'httpOnly': cookie.httpOnly
      });
    }

    await StorageManager.prefs.setString('cookies_$userId', json.encode(cookiesData));
  }

  /// 清除指定用户的所有 Cookie
  static Future<void> clearCookiesForUser(String userId) async {
    _userCookieJars.remove(userId);
    await StorageManager.prefs.remove('cookies_$userId');
  }

  /// 临时Cookie保存到账号
  static Future<void> saveTempCookies(String userId) async {
    // 复制一份CookieJar
    final newCookieJar = CookieJar();
    final tempCookies = await _tempCookieJar.loadForRequest(domainUri);
    if (tempCookies.isNotEmpty) {
      await newCookieJar.saveFromResponse(domainUri, tempCookies);
    }

    _userCookieJars[userId] = newCookieJar;
    await _saveCookiesToStorage(userId, newCookieJar);
    await _tempCookieJar.deleteAll();
  }
}