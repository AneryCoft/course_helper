import 'package:dio/dio.dart';
import 'dart:convert';

import '../api/api_service.dart';
import '../utils/encrypt.dart';
import '../models/user.dart';

class CXLoginApi extends Api {
  CXLoginApi([super.user]);

  /// Web登录
  static Future<Map<String, dynamic>?> loginWeb(String username, String password) async {
    final url = 'https://passport2.chaoxing.com/fanyalogin';

    final usernameCipher = EncryptionUtil.aesCbcEncrypt(username, Constant.webLoginKey);
    final passwordCipher = EncryptionUtil.aesCbcEncrypt(password, Constant.webLoginKey);

    final formData = {
      'fid': '-1',
      'uname': usernameCipher,
      'password': passwordCipher,
      't': 'true',
      'forbidotherlogin': '0',
      'validate': ''
    };
    final response = await ApiService.sendRequest(url, method: "POST", body: formData, userId: '');
    return response?.data;
  }

  /// 发送验证码
  static Future<Map<String, dynamic>?> sendCaptcha(String phone) async {
    final url = 'https://passport2-api.chaoxing.com/api/sendcaptcha';

    final timeStampMS = DateTime.now().millisecondsSinceEpoch.toString();
    final enc = EncryptionUtil.md5Hash(phone + Constant.sendCaptchaKey + timeStampMS);

    final formData = {
      'to': phone,
      'countrycode': '86',
      'time': timeStampMS,
      'enc': enc
    };

    final response = await ApiService.sendRequest(url, method: "POST", body: formData, userId: '');
    return response?.data;
  }

  /// APP 登录
  static Future<Map<String, dynamic>?> loginAPP(String loginType, String username, String code) async {
    final url = 'https://passport2-api.chaoxing.com/v11/loginregister?cx_xxt_passport=json';

    final loginData = {
      'uname': username,
      'code': code
    };
    final loginInfo = EncryptionUtil.aesEcbEncrypt(json.encode(loginData), Constant.appLoginKey);

    final formData = {
      'logininfo': loginInfo,
      'loginType': loginType,
      'roleSelect': 'true',
      'entype': "1"
    };
    if (loginType == '2') {
      formData['countrycode'] = '86';
    }

    final response = await ApiService.sendRequest(url, method: "POST", body: formData, userId: '');
    return response?.data;
    // {"mes":"验证通过","type":1,"url":"https://sso.chaoxing.com/apis/login/userLogin4Uname.do","status":true}
  }

  /// 获取用户信息
  Future<User?> getUserInfo() async {
    final url = 'https://sso.chaoxing.com/apis/login/userLogin4Uname.do';

    final response = await ApiService.sendRequest(url, userId: user?.uid);
    if (response == null) return null;
    
    // final response = await ApiService.sendRequest(url, method: "POST", body: formData);
    final result = response.data['result'];
    if (result == 1) {
      final data = response.data['msg'];
      final user = User(
          uid: data['puid']?.toString() ?? '',
          name: data['name'] ?? '未知用户',
          avatar: data['pic'] ?? '',
          phone: data['phone'] ?? '未知手机号',
          school: data['schoolname'] ?? '未知学校',
          platform: 'chaoxing'
      );

      final imAccount = data['accountInfo']['imAccount'];
      final userName = imAccount['username'];
      final passwordCipher = imAccount['password'];
      final password = EncryptionUtil.desEcbDecrypt(passwordCipher, Constant.imKey);
      user.imAccount = {
        'userName': userName,
        'password': password
      };

      return user;
    }
    return null;
  }
  
  /// 获取二维码登录数据（uuid&enc）
  static Future<Map<String, dynamic>?> getQRCodeData() async {
    final url = 'https://passport2.chaoxing.com/refreshQRCode';
    // final createQRCode = 'https://passport2.chaoxing.com/createqr?uuid=UUID&fid=-1&type=3';

    final response = await ApiService.sendRequest(url, method: 'POST', userId: '');
    return response?.data;
  }
  
  /// 检查二维码授权状态
  static Future<Map<String, dynamic>?> checkQRAuthStatus(String uuid, String enc) async {
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
      body: formData,
      userId: ''
    );
    return response?.data;
  }
}

class RCLoginApi extends Api {
  RCLoginApi([super.user]);
  /// 发送验证码
  static Future<Map<String, dynamic>?> sendCaptcha(String phone, String ticket, String rand) async {
    final url = '/api/v3/user/code/send';

    final jsonData = {
      'phoneNumber': phone,
      'email': '',
      'ticket': ticket,
      'rand': rand
    };

    final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData, userId: '');
    return response?.data;
  }

  /// 验证验证码
  static Future<Map<String, dynamic>?> verifyCaptcha(String phone, String code) async {
    final url = 'https://www.yuketang.cn/api/v3/user/code/verify';

    final jsonData = {
      'phoneNumber': phone,
      'email': '',
      'code': code
    };

    final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData, userId: '');
    return response?.data;
  }

  /// 验证码 密码登录
  static Future<Map<String, dynamic>?> login(int loginType, String account, String code, String ticket, String rand) async {
    final url = '/api/v3/user/login/app';

    final jsonData = {
      'type': loginType,
      'phoneNumber': '',
      'password': '',
      'email': '',
      'code': '',
      'pushDeviceId': ApiService.uniqueId,
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

    final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData, userId: '');
    return response?.data;
  }

  /// 获取用户信息
  Future<User?> getUserInfo() async {
    final url = '/v/course_meta/user_info';

    final response = await ApiService.sendRequest(url, userId: user?.uid);
    if (response == null) return null;

    final userProfile = response.data['data']['user_profile'];
    if (userProfile != null) {
      final user = User(
          uid: userProfile['user_id'].toString(),
          name: userProfile['name'] ?? '未知用户',
          avatar: userProfile['avatar'].isNotEmpty ?
          userProfile['avatar'] : (userProfile['avatar_96'] ?? ''), // avatar_96为默认头像
          phone: userProfile['phone_number'] ?? '未知手机号',
          school: userProfile['school'] ?? '未知学校',
          platform: 'rainClassroom'
      );
      return user;
    }
    return null;
  }

  /// 获取微信登录二维码的UUID和state
  static Future<List<String>?> getQRCodeUuid() async {
    final authParamUrl = '/api/v3/user/login/wechat-auth-param';
    var response = await ApiService.sendRequest(authParamUrl, method: 'POST', body:{}, userId: '');
    if (response == null) return null;
    
    final data = response.data['data'];

    final qrConnectUrl = 'https://open.weixin.qq.com/connect/qrconnect';
    final String state = data['state'];
    final params = {
      'appid': data['appId'] as String,
      'scope': 'snsapi_login',
      'redirect_uri': '${data['redirectUri']}?path=%2Fauthorize%2Fwx-qrlogin%3Fsuccess%3D1',
      'state': state,
      'login_type': 'jssdk',
      'self_redirect': 'true',
      'f': 'xml' // 如果没有则输出html
    };
    response = await ApiService.sendRequest(qrConnectUrl, params: params, responseType: ResponseType.plain, userId: '');
    if (response == null) return null;

    final xml = response.data;
    final uuidRegex = RegExp(r'<uuid><!\[CDATA\[(.+?)\]\]></uuid>', dotAll: true);
    final uuidMatch = uuidRegex.firstMatch(xml);
    
    if (uuidMatch != null) {
      return [uuidMatch.group(1)!, state];
    }
    return null;
  }

  /// 检查微信二维码授权状态
  static Future<String?> checkQRAuthStatus(String uuid, String state) async {
    final connectUrl = 'https://lp.open.weixin.qq.com/connect/l/qrconnect?uuid=$uuid';
    
    var response = await ApiService.sendRequest(connectUrl, responseType: ResponseType.plain, userId: ''); // 服务端在15秒后响应
    if (response == null) return null;

    final html = response.data;
    final errorCodeRegex = RegExp(r'window\.wx_errcode=(\d+)');
    final codeRegex = RegExp(r"window\.wx_code='(.+?)'");
    
    final errorCodeMatch = errorCodeRegex.firstMatch(html);
    final codeMatch = codeRegex.firstMatch(html);
    
    if (errorCodeMatch != null) {
      final errorCode = errorCodeMatch.group(1);
      
      if (errorCode == '405') {
        // 已授权
        if (codeMatch != null) {
          final callbackUrl = '/api/v3/user/login/wechat-web-callback';
          final params = {
            'path': '/authorize/wx-qrlogin?success=1',
            'code': codeMatch.group(1)!,
            'state': state
          };
          await ApiService.sendRequest(callbackUrl, params: params, responseType: ResponseType.plain, userId: '');
          // 重定向到 authorize/wx-qrlogin?success=1
        }
      }
      return errorCode;
    }
    return null;
  }
}