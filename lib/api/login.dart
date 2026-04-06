import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../api/api_service.dart';
import '../utils/encrypt.dart';
import '../session/cookie.dart';
import '../models/user.dart';

class CXLoginApi {
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

      CookieManager.isLoggingIn = true;
      final response = await ApiService.sendRequest(url, method: "POST", body: formData);
      return response.data;
    } catch (e) {
      debugPrint('Login error: $e');
    } finally {
      CookieManager.isLoggingIn = false;
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

  /// APP 登录
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

      CookieManager.isLoggingIn = true;
      final response = await ApiService.sendRequest(url, method: "POST", body: formData);
      return response.data;
      // {"mes":"验证通过","type":1,"url":"https://sso.chaoxing.com/apis/login/userLogin4Uname.do","status":true}
    } catch (e) {
      debugPrint('Login error: $e');
    } finally {
      CookieManager.isLoggingIn = false;
    }
    return null;
  }

  /// 获取用户信息
  static Future<User?> getUserInfo() async {
    try {
      final url = 'https://sso.chaoxing.com/apis/login/userLogin4Uname.do';
      // POST https://sso.chaoxing.com/apis/login/userLogin.do?puid=&hddInfo=&len=
      // 用于在每次进入应用时刷新账号 hddInfo和data一致

      /*
      final deviceId = EncryptionUtil.getUniqueId();
      final deviceInfo = {
        "app_name": "com.chaoxing.mobile",
        "app_ver": "6.7.4",
        "board": "caiman",
        "brand": "google",
        "cdid": deviceId,
        "cdtype": "Pixel 9 Pro",
        "cpu_ar": "arm64-v8a,armeabi-v7a,armeabi",
        "device_id": deviceId,
        "dpi": "440",
        "hardware": "caiman",
        "mediaDrmId": "",
        "oaid": "1004",
        "os_lang": "",
        "os_name": "REL",
        "os_ver": "16",
        "platform": "android",
        "resolution": "1080*2243",
        "time_stamp": DateTime.now().millisecondsSinceEpoch
      };

      final formData = {'data': EncryptionUtil.rsaEncrypt(jsonEncode(deviceInfo), Constant.rsaPublicKey)};
      */

      CookieManager.isLoggingIn = true;
      final response = await ApiService.sendRequest(url);
      // final response = await ApiService.sendRequest(url, method: "POST", body: formData);

      final data = response.data['msg'];
      final user = User(
          uid: data['puid']?.toString() ?? '',
          name: data['name'] ?? '未知用户',
          avatar: data['pic'] ?? '',
          phone: data['phone'] ?? '未知手机号',
          school: data['schoolname'] ?? '未知学校',
          platform: 'chaoxing'
      );
      return user;
    } catch (e) {
      debugPrint('getUserInfo error: $e');
    } finally {
      CookieManager.isLoggingIn = false;
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

      CookieManager.isLoggingIn = true;
      final response = await ApiService.sendRequest(
        authStatusUrl, 
        method: "POST", 
        body: formData
      );
      return response.data;
    } catch (e) {
      debugPrint('checkQRAuthStatus error: $e');
    } finally {
      CookieManager.isLoggingIn = false;
    }
    return null;
  }
}

class RCLoginApi {
  /// 发送验证码
  static Future<Map<String, dynamic>?> sendCaptcha(String phone, String ticket, String rand) async {
    try {
      final url = '/api/v3/user/code/send';

      final jsonData = {
        'phoneNumber': phone,
        'email': '',
        'ticket': ticket,
        'rand': rand
      };

      final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData);
      return response.data;
    } catch (e) {
      debugPrint('sendCaptcha error: $e');
    }
    return null;
  }

  /// 验证验证码
  static Future<Map<String, dynamic>?> verifyCaptcha(String phone, String code) async {
    try {
      final url = 'https://www.yuketang.cn/api/v3/user/code/verify';

      final jsonData = {
        'phoneNumber': phone,
        'email': '',
        'code': code
      };

      final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData);
      return response.data;
    } catch (e) {
      debugPrint('verifyCaptcha error: $e');
    }
    return null;
  }

  /// 验证码 密码登录
  static Future<Map<String, dynamic>?> login(int loginType, String account, String code, String ticket, String rand) async {
    try {
      final url = '/api/v3/user/login/app';

      final jsonData = {
        'type': loginType,
        'phoneNumber': '',
        'password': '',
        'email': '',
        'code': '',
        'pushDeviceId': '', // 密码登录会有
        'ticket': ticket,
        'rand': rand
      };
      if (loginType == 2) {
        jsonData['password'] = code;
        if (account.contains('@')) {
          jsonData['email'] = account;
        } else {
          jsonData['type'] = 1;
          jsonData['phoneNumber'] = account;
        }
      } else if (loginType == 3) {
        jsonData['phoneNumber'] = account;
        jsonData['code'] = code;
      }

      CookieManager.isLoggingIn = true;
      final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData);
      return response.data;
    } catch (e) {
      debugPrint('login error: $e');
    } finally {
      CookieManager.isLoggingIn = false;
    }
    return null;
  }

  /// 获取用户信息
  static Future<User?> getUserInfo() async {
    try {
      final url = '/v/course_meta/user_info';

      CookieManager.isLoggingIn = true;
      final response = await ApiService.sendRequest(url);

      final userProfile = response.data['data']['user_profile'];
      final user = User(
          uid: userProfile['user_id']?.toString() ?? '',
          name: userProfile['name'] ?? '未知用户',
          avatar: userProfile['avatar'] ?? userProfile['avatar_96'] ?? '',
          phone: userProfile['phone_number'] ?? '未知手机号',
          school: userProfile['school'] ?? '未知学校',
          platform: 'rainClassroom'
      );
      return user;
    } catch (e) {
      debugPrint('getUserInfo error: $e');
    } finally {
      CookieManager.isLoggingIn = false;
    }
    return null;
  }
}