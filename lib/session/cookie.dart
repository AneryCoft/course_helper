import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account.dart';

class CookieInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final cookieJar = await CookieManager.getCurrentUserCookieJar();
    if (cookieJar != null) {
      final uri = options.uri;
      final cookies = await cookieJar.loadForRequest(uri);
      if (cookies.isNotEmpty) {
        final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
        options.headers['Cookie'] = cookieStr;
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      final cookies = setCookieHeaders.map((s) => Cookie.fromSetCookieValue(s)).toList();
      final uidCookie = cookies.where((c) => c.name == 'UID').firstOrNull;

      if (uidCookie != null) {
        final String userId = uidCookie.value;
        final currentUserId = await AccountManager.getCurrentSession();

        if (currentUserId != userId) {
          // 新用户
          await CookieManager.saveCookiesForUser(userId, newCookies: cookies);
          await AccountManager.setCurrentSession(userId);
          handler.next(response);
          return;
        }
      }
      await _saveToCurrentUser(cookies, response.realUri);
    }
    handler.next(response);
  }

  /// 将Cookie保存到当前用户的存储中
  Future<void> _saveToCurrentUser(List<Cookie> cookies, Uri uri) async {
    final cookieJar = await CookieManager.getCurrentUserCookieJar();
    if (cookieJar != null) {
      await cookieJar.saveFromResponse(uri, cookies);
      await CookieManager.saveCurrentUserCookies();
    }
  }
}

class CookieManager {
  static const String domain = '.chaoxing.com';
  static final Uri domainUri = Uri.parse('https://$domain');
  // ID->CookieJar
  static final Map<String, CookieJar> _userCookieJars = {};

  /// 获取用户的 CookieJar
  static Future<CookieJar> getCookieJarForUser(String userId) async {
    if (_userCookieJars.containsKey(userId)) {
      return _userCookieJars[userId]!;
    }

    final cookieJar = CookieJar();
    _userCookieJars[userId] = cookieJar;

    await _loadCookiesForUser(userId, cookieJar);

    return cookieJar;
  }

  /// 加载用户的Cookie
  static Future<void> _loadCookiesForUser(String userId, CookieJar cookieJar) async {
    final prefs = await SharedPreferences.getInstance();
    final String? cookiesJson = prefs.getString('cookies_$userId');
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
      debugPrint('用户 $userId 的 Cookie 加载失败: $e');
    }
  }

  /// 保存指定用户的 Cookie（可选直接传入新 Cookie）
  static Future<void> saveCookiesForUser(String userId, {List<Cookie>? newCookies}) async {
    final jar = await getCookieJarForUser(userId);

    // 如果有新 Cookie 需要直接存入
    if (newCookies != null) {
      for (var cookie in newCookies) {
        if (cookie.domain != null && cookie.domain!.isNotEmpty) {
          final uri = Uri.parse('https://${cookie.domain}');
          await jar.saveFromResponse(uri, [cookie]);
        }
      }
    }

    // 保存主域名的所有 Cookie 到 SharedPreferences
    final cookies = await jar.loadForRequest(domainUri);
    final List<Map<String, dynamic>> cookiesData = [];
    for (var cookie in cookies) {
      cookiesData.add({
        'name': cookie.name,
        'value': cookie.value,
        'domain': cookie.domain ?? domain,
        'path': cookie.path ?? '/',
        'secure': cookie.secure,
        'httpOnly': cookie.httpOnly,
      });
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cookies_$userId', json.encode(cookiesData));
  }

  /// 保存当前用户的 Cookie
  static Future<void> saveCurrentUserCookies() async {
    final currentUserId = await AccountManager.getCurrentSession();
    if (currentUserId != null) {
      await saveCookiesForUser(currentUserId);
    }
  }

  /// 获取当前登录用户的 CookieJar
  static Future<CookieJar?> getCurrentUserCookieJar() async {
    final currentUserId = await AccountManager.getCurrentSession();
    if (currentUserId == null || currentUserId.isEmpty) return null;
    return getCookieJarForUser(currentUserId);
  }

  /// 清除指定用户的所有 Cookie
  static Future<void> clearCookiesForUser(String userId) async {
    _userCookieJars.remove(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cookies_$userId');
  }

  /// 清除当前用户的 Cookie
  static Future<void> clearCurrentUserCookies() async {
    final currentUserId = await AccountManager.getCurrentSession();
    if (currentUserId != null) {
      await clearCookiesForUser(currentUserId);
    }
  }

  /// 初始化时预加载当前用户的 Cookie
  static Future<void> initialize() async {
    final currentUserId = await AccountManager.getCurrentSession();
    if (currentUserId != null) {
      await getCookieJarForUser(currentUserId);
    }
  }
}