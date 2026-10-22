import 'dart:convert';
import 'package:dio/dio.dart';

import '../utils/encrypt.dart';
import '../utils/logger.dart';
import '../utils/storage.dart';
import '../session/cookie.dart';
import '../session/account.dart';
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

  static final _uniqueId = ApiService.uniqueId;

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

class DioLoggerInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.i('${options.method} ${_HttpLogPrivacy.safeUri(options.uri)}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    logger.i(
      '${response.statusCode ?? '-'} ${options.method} '
      '${_HttpLogPrivacy.safeUri(options.uri)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    logger.e(
      '✗ ${err.response?.statusCode ?? '-'} ${options.method} '
      '${_HttpLogPrivacy.safeUri(options.uri)} (${err.type.name})',
    );
    handler.next(err);
  }
}

class _HttpLogPrivacy {
  static String safeUri(Uri uri) {
    try {
      return Uri(
        scheme: uri.scheme.isEmpty ? null : uri.scheme,
        host: uri.hasAuthority ? uri.host : null,
        port: uri.hasPort ? uri.port : null,
        pathSegments: uri.pathSegments,
      ).toString();
    } catch (_) {
      return '<invalid-uri>';
    }
  }

  static String safeUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      return uri == null ? '<invalid-uri>' : safeUri(uri);
    } catch (_) {
      return '<invalid-uri>';
    }
  }

  static String errorType(Object error) => error.runtimeType.toString();
}



class ApiService {
  static late Dio _dio;
  static void Function()? onPlatformChange;
  static const _uniqueIdKey = 'app_unique_id';

  /// 获取当前设备唯一标识（伪）
  static String get uniqueId {
    late String uniqueId;
    final prefs = StorageManager.prefs;
    if (prefs.containsKey(_uniqueIdKey)){
      uniqueId = prefs.getString(_uniqueIdKey)!;
    } else {
      uniqueId = EncryptionUtil.getUniqueId();
      prefs.setString(_uniqueIdKey, uniqueId);
    }
    return uniqueId;
  }

  /// 获取雨课堂服务器对应的 baseUrl
  static const serverBaseUrlMap = {
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
        _dio.options.baseUrl = serverBaseUrlMap[PlatformManager().currentServer]!;
        _dio.options.headers = HeadersManager.rainClassroomHeaders;
      }
    };
  }

  static Future<void> initialize() async {
    await HeadersManager.updateChaoxingHeaders();
    
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
      validateStatus: (status) => status != null && status >= 200 && status < 400
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

    _dio.interceptors.add(DioLoggerInterceptor());
  }

  /// 发送 HTTP 请求
  static Future<Response?> sendRequest(
      String url,
      {
        String method = 'GET',
        Map<String, String>? params,
        Map<String, String>? headers,
        dynamic body,
        ResponseType responseType = ResponseType.json,
        int? receiveTimeoutSeconds,
        bool allowRedirects = true,
        String? userId
      }
      ) async {
    try {
      final options = Options(
        method: method,
        headers: headers,
        responseType: responseType,
        receiveTimeout: Duration(seconds: receiveTimeoutSeconds ?? 10),
        extra: {'userId': userId ?? AccountManager.currentSessionId}
      );

      var response = await _dio.request(url, queryParameters: params, data: body, options: options);

      if (allowRedirects) {
        int redirectCount = 0;
        const maxRedirects = 3;
        
        while (redirectCount < maxRedirects) {
          var locationUrl = response.headers['location']?.first;
          if (locationUrl == null) break;
          
          // 只有路径
          if (!locationUrl.startsWith('http')){
            final uri = response.realUri;
            final baseUri = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
            locationUrl = baseUri + locationUrl;
          }
          
          response = await _dio.get(locationUrl, options: options);
          redirectCount++;
        }
      }

      if (options.responseType == ResponseType.json) {
        if (response.data is String) {
          response.data = jsonDecode(response.data);
        }
      } // dio 的 json 解析有问题

      return response;
    } catch (e) {
      logger.e(
        'HTTP request failed [$method ${_HttpLogPrivacy.safeUrl(url)}] '
        '(${_HttpLogPrivacy.errorType(e)})',
      );
    }
    return null;
  }

  /// 并发用户请求
  static Future<List<T?>> sendForEachUser<T>(
      List<User> users,
      Future<T?> Function(User user) apiFunction,
      ) async {
    if (users.isEmpty) {
      return [];
    }

    final futures = users.map((user) async {
      try {
        return await apiFunction(user);
      } catch (e) {
        logger.e(
          '用户请求失败 (${_HttpLogPrivacy.errorType(e)})',
        );
        return null;
      }
    }).toList();

    return await Future.wait(futures);
  }
}

abstract class Api {
  final User? user;

  Api([User? user]) : user = user ?? AccountManager.currentUser;
}
