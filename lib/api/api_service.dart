import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../utils/encrypt.dart';
import '../session/cookie.dart';
import '../platform.dart';
import '../models/user.dart';

class HeadersManager {
  static const _brand = 'google';
  static const _deviceModel = 'Pixel 9 Pro';
  static const _systemVersion = '16';
  static const _buildNumber = '1610';
  static const _incremental = '14624737'; // ro.build.version.incremental
  static const _systemHttpAgent = 'Dalvik/2.1.0 (Linux; U; Android 16; Pixel 9 Pro Build/BP4A.260205.002)';

  static const _rcVersion = '1.3.3';

  static const _cxProductId = '3';
  static const _cxVersion = '6.7.4';
  static const _cxVersionCode = '10940';
  static const _cxApiVersion = '314';

  static const _uniqueIdKey = 'app_unique_id';
  static late String _uniqueId;

  static late String _cxUserAgent;

  static late Map<String, String> _cxHeaders;

  static final Map<String, String> _rcHeaders = {
    'user-agent': 'Android',
    'brand': '$_brand $_deviceModel',
    'uuid': '',
    'buildnumber': _buildNumber,
    'xtua': 'client=app&tag=$_rcVersion&platform=Android',
    'systemversion': _systemVersion,
    'incremental': _incremental,
    'accept': 'application/json',
    'isphysicaldevice': 'true',
    'xtbz': 'ykt',
    'x-client': 'app'
  };

  static Future<void> updateChaoxingHeaders() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_uniqueIdKey)){
      _uniqueId = prefs.getString(_uniqueIdKey)!;
    } else {
      _uniqueId = EncryptionUtil.getUniqueId();
      prefs.setString(_uniqueIdKey, _uniqueId);
    }
    // 内测版：@Azeroth
    // 正式版：@Kalimdor
    final userAgentTemp = '(device:$_deviceModel) Language/zh_CN com.chaoxing.mobile/ChaoXingStudy_${_cxProductId}_${_cxVersion}_android_phone_${_cxVersionCode}_$_cxApiVersion (@Kalimdor)_$_uniqueId';
    final schild = EncryptionUtil.md5Hash('(schild:${Constant.schildSalt}) $userAgentTemp');
    _cxUserAgent = '$_systemHttpAgent (schild:$schild) $userAgentTemp';

    _cxHeaders = {
      'User-Agent': _cxUserAgent,
      'Accept-Language': 'zh_CN',
      'Connection': 'keep-alive',
      'Accept-Encoding': 'gzip',
      'content-type': 'application/x-www-form-urlencoded'
      // 'X-Requested-With': 'com.chaoxing.mobile'
    };
  }

  static Map<String, String> get chaoxingHeaders => Map.unmodifiable(_cxHeaders);

  static Map<String, String> get rainClassroomHeaders => Map.unmodifiable(_rcHeaders);
}



class ApiService {
  static late Dio _dio;
  static void Function()? onPlatformChange;

  /// 获取雨课堂服务器对应的 baseUrl
  static const _serverBaseUrlMap = {
    RainClassroomServerType.yuketang: 'https://www.yuketang.cn',
    RainClassroomServerType.pro: 'https://pro.yuketang.cn',
    RainClassroomServerType.changjiang: 'https://changjiang.yuketang.cn',
    RainClassroomServerType.huanghe: 'https://huanghe.yuketang.cn'
  };


  // 初始化平台变化回调函数
  static void _setupPlatformChangeCallback() {
    onPlatformChange = () async {
      if (PlatformManager().isChaoxing) {
        _dio.options.baseUrl = '';
        _dio.options.headers = HeadersManager.chaoxingHeaders;
      } else if (PlatformManager().isRainClassroom) {
        _dio.options.baseUrl = _serverBaseUrlMap[PlatformManager().currentServer]!;
        _dio.options.headers = HeadersManager.rainClassroomHeaders;
      }
    };
  }

  static Future<void> initialize() async {
    await HeadersManager.updateChaoxingHeaders();
    
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
      validateStatus: (status) => status! < 500
      // contentType: Headers.formUrlEncodedContentType, // application/x-www-form-urlencoded
      // headers: HeadersManager.chaoxingHeaders,
    ));

    /*
    // 初始化平台变化回调
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.userAgent = HeadersManager._cxUserAgent;
      return client;
    }; // dio 自动重定向会使用默认的 User-Agent
    // 似乎无法在初始化结束后进行更改
     */
    _setupPlatformChangeCallback();

    _dio.interceptors.add(CookieInterceptor());

    _dio.interceptors.add(PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: false,
        maxWidth: 90,
        enabled: kDebugMode,
        filter: (options, args){
          if(args.data.toString().contains('<html>')){
            return false;
          }
          return !args.isResponse || !args.hasUint8ListData;
        }
    ));
  }

  /// 发送 HTTP 请求
  static Future<Response> sendRequest(
      String url,
      {
        String method = 'GET',
        Map<String, String>? params,
        Map<String, String>? headers,
        dynamic body,
        ResponseType responseType = ResponseType.json,
        bool allowRedirects = true
      }
      ) async {
    final options = Options(
      method: method,
      headers: headers,
      responseType: responseType
    );

    var response = await _dio.request(url, queryParameters: params, data: body, options: options);

    if (allowRedirects) {
      var locationUrl = response.headers['location']?.first;
      if (locationUrl != null) {
        // 只有路径
        if (!locationUrl.startsWith('http')){
          final uri = response.realUri;
          final baseUri = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
          locationUrl = baseUri + locationUrl;
        }
        response = await _dio.get(locationUrl, options: options);
      }
    }
    // 暂时只重定向一次

    if (options.responseType == ResponseType.json) {
      if (response.data is String) {
        response.data = jsonDecode(response.data);
      }
    } // dio 的 json 解析有问题

    return response;
  }

  /// 为指定用户列表并发发送请求
  /// [users] 用户列表
  /// [requestBuilder] 用于构建每个用户的请求参数
  /// 返回每个用户的响应结果列表（顺序与用户列表一致）
  static Future<List<Response?>> sendForEachUser(
    List<User> users,
    String url, {
    required Map<String, dynamic> Function(User user) requestBuilder,
    String method = 'POST',
    ResponseType responseType = ResponseType.json,
  }) async {
    if (users.isEmpty) {
      return [];
    }

    final futures = users.map((user) async {
      try {
        final cookieJar = await CookieManager.getCookieJarForUser(user.uid);
        final domainUri = CookieManager.getDomainUri();
        final cookies = await cookieJar.loadForRequest(domainUri);
        
        final requestData = requestBuilder(user);
        Map<String, String>? headers = requestData['headers'];
        
        if (cookies.isNotEmpty) {
          final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
          headers ??= {};
          headers['Cookie'] = cookieStr;
          
          if (PlatformManager().isRainClassroom) {
            final cookieMap = Map.fromEntries(cookies.map((c) => MapEntry(c.name, c.value)));
            headers['x-csrftoken'] = cookieMap['x-csrftoken'] ?? '';
            headers['x-uid'] = cookieMap['x-uid'] ?? '';
            headers['sessionid'] = cookieMap['sessionid'] ?? '';
          }
        }
        
        final response = await sendRequest(
          url,
          method: method,
          body: requestData['body'],
          params: requestData['params'],
          headers: headers,
          responseType: responseType
        );

        return response;
      } catch (e) {
        debugPrint('用户 ${user.name} 请求失败: $e');
        return null;
      }
    }).toList();

    return await Future.wait(futures);
  }
}