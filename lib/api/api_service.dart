import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../utils/encrypt.dart';
import '../session/cookie.dart';


class ApiService {
  static late Dio _dio;

  // Header
  static const String _systemHttpAgent = 'Dalvik/2.1.0 (Linux; U; Android 15; PKG110 Build/UKQ1.231108.001)';
  static const String _device = 'PKG110';
  static const String _productId = '3';
  static const String _version = '6.7.2';
  static const String _versionCode = '10936';
  static const String _apiVersion = '311';
  // 内测版: @Azeroth
  // 正式版: @Kalimdor
  static const String _uniqueIdKey = 'app_unique_id';
  static late String uniqueId;
  static late String userAgent;

  static void _updateUserAgent(String uniqueId) {
    final userAgentTemp = '(device:$_device) Language/zh_CN com.chaoxing.mobile/ChaoXingStudy_${_productId}_${_version}_android_phone_${_versionCode}_$_apiVersion (@Kalimdor)_$uniqueId';
    final schild = EncryptionUtil.md5Hash('(schild:${Constant.schildSalt}) $userAgentTemp');

    userAgent = '$_systemHttpAgent (schild:$schild) $userAgentTemp';
  }

  static Future<void> initialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_uniqueIdKey)){
      uniqueId = prefs.getString(_uniqueIdKey)!;
    } else {
      uniqueId = EncryptionUtil.getUniqueId();
      prefs.setString(_uniqueIdKey, uniqueId);
    }

    _updateUserAgent(uniqueId);

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: Headers.formUrlEncodedContentType, // application/x-www-form-urlencoded
      headers: {
        'User-Agent': userAgent,
        'Accept-Language': 'zh_CN',
        'Connection': 'keep-alive',
        'Accept-Encoding': 'gzip'
        // 'X-Requested-With': 'com.chaoxing.mobile'
      },
      // validateStatus: (status) => status! < 500
    ));

    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.userAgent = userAgent;
      return client;
    }; // dio自动重定向会使用默认的User-Agent

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

  // 发送HTTP请求
  static Future<Response> sendRequest(
      String url,
      {
        String method = 'GET',
        Map<String, String>? params,
        Map<String, String>? headers,
        dynamic body,
        ResponseType responseType = ResponseType.json
      }
      ) async {

    Options options = Options(headers: headers, responseType: responseType);
    
    late Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _dio.get(url, queryParameters: params, options: options);
        break;
      case 'POST':
        response = await _dio.post(url, data: body, queryParameters: params, options: options);
        break;
      case 'PUT':
        response = await _dio.put(url, data: body, queryParameters: params, options: options);
        break;
      case 'DELETE':
        response = await _dio.delete(url, queryParameters: params, options: options);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    if (options.responseType == ResponseType.json) {
      if (response.data is String) {
        response.data = jsonDecode(response.data);
      }
    } // dio的json解析有问题

    return response;
  }
}