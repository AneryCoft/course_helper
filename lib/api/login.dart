import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../api/api_service.dart';
import '../utils/encrypt.dart';

class LoginApi {
  /// Web登录
  static Future<Map<String, dynamic>?> loginWeb(String username, String password) async {
    try {
      final url = 'https://passport2.chaoxing.com/fanyalogin';

      final usernameCipher = EncryptionUtil.aesCbcEncrypt(password, Constant.webLoginKey);
      final passwordCipher = EncryptionUtil.aesCbcEncrypt(password, Constant.webLoginKey);

      final formData = {
        'fid': '-1',
        'uname': usernameCipher,
        'password': passwordCipher,
        't': 'true',
        'forbidotherlogin': '0',
        'validate': ''
      };

      final response = await ApiService.sendRequest(url, method: "POST", body: formData);
      return response.data;
    } catch (e) {
      debugPrint('Login error: $e');
    }
    return null;
  }

  /// 发送验证码
  static Future<Map<String, dynamic>?> sendCaptcha(String phone) async {
    try {
      final url = 'https://passport2-api.chaoxing.com/api/sendcaptcha';

      final timestampMS = DateTime.now().millisecondsSinceEpoch.toString();
      final enc = EncryptionUtil.md5Hash(phone + Constant.sendCaptchaKey + timestampMS);

      final formData = {
        'to': phone,
        'countrycode': '86',
        'time': timestampMS,
        'enc': enc
      };

      final response = await ApiService.sendRequest(url, method: "POST", body: formData);
      return response.data;
    } catch (e) {
      debugPrint('sendCaptcha error: $e');
    }
    return null;
  }

  /// APP登录
  static Future<Map<String, dynamic>?> loginAPP(String loginType, String username, String code) async {
    try {
      final url = 'https://passport2-api.chaoxing.com/v11/loginregister?cx_xxt_passport=json';

      final loginData = {
        'uname': username,
        'code': code
      };
      final loginInfo = EncryptionUtil.aesEcbEncrypt(json.encode(loginData), Constant.appLoginKey);

      Map<String, dynamic> formData = {
        'logininfo': loginInfo,
        'loginType': loginType,
        'roleSelect': 'true',
        'entype': "1"
      };
      if (loginType == '2') {
        formData['countrycode'] = '86';
      }

      final response = await ApiService.sendRequest(url, method: "POST", body: formData);
      return response.data;
      // {"mes":"验证通过","type":1,"url":"https://sso.chaoxing.com/apis/login/userLogin4Uname.do","status":true}
    } catch (e) {
      debugPrint('Login error: $e');
    }
    return null;
  }

  /// 获取用户信息
  static Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      final url = 'https://sso.chaoxing.com/apis/login/userLogin4Uname.do';

      final response = await ApiService.sendRequest(url);
      return response.data;
    } catch (e) {
      debugPrint('getUserInfo error: $e');
    }
    return null;
  }
  
  /// 获取二维码登录数据
  static Future<Map<String, dynamic>?> getQRCodeData() async {
    try {
      final loginPageUrl = 'https://passport2.chaoxing.com/login';
      final response = await ApiService.sendRequest(loginPageUrl, responseType: ResponseType.plain);

      final html = response.data;
      
      // 提取uuid
      final uuidRegex = RegExp(r'value="(.+?)" id="uuid"');
      final uuidMatch = uuidRegex.firstMatch(html);
      final uuid = uuidMatch?.group(1);
      
      // 提取enc
      final encRegex = RegExp(r'value="(.+?)" id="enc"');
      final encMatch = encRegex.firstMatch(html);
      final enc = encMatch?.group(1);
      
      if (uuid != null && enc != null) {
        return {
          'uuid': uuid,
          'enc': enc,
        };
      }
    } catch (e) {
      debugPrint('getQRCodeData error: $e');
    }
    return null;
  }
  
  /// 获取二维码图片
  static Future<Uint8List?> getQRCodeImage(String uuid) async {
    try {
      final qrCodeUrl = 'https://passport2.chaoxing.com/createqr?uuid=$uuid&fid=-1';
      final response = await ApiService.sendRequest(
        qrCodeUrl, 
        responseType: ResponseType.bytes
      );
      
      if (response.data is List<int>) {
        return Uint8List.fromList(response.data);
      }
    } catch (e) {
      debugPrint('getQRCodeImage error: $e');
    }
    return null;
  }
  
  /// 检查二维码授权状态
  static Future<Map<String, dynamic>?> checkQRAuthStatus(String uuid, String enc) async {
    try {
      final authStatusUrl = 'https://passport2.chaoxing.com/getauthstatus/v2';
      
      final formData = {
        'enc': enc,
        'uuid': uuid,
        'doubleFactorLogin': '0',
        'forbidotherlogin': '0'
      };
      
      final response = await ApiService.sendRequest(
        authStatusUrl, 
        method: "POST", 
        body: formData
      );
      
      return response.data;
    } catch (e) {
      debugPrint('checkQRAuthStatus error: $e');
    }
    return null;
  }
}