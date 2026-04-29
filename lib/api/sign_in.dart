import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import 'api_service.dart';
import '../utils/encrypt.dart';
import '../session/cookie.dart';
import '../models/user.dart';


class SignInApi{
  static const String _signUrl = 'https://mobilelearn.chaoxing.com/pptSign/stuSignajax';
  static String get _deviceCode => EncryptionUtil.getDeviceCode();

  /// 获取用户的Cookie字符串
  static Future<String?> _getUserCookie(String userId) async {
    try {
      final cookieJar = await CookieManager.getCookieJarForUser(userId);
      final domainUri = CookieManager.getDomainUri();
      final cookies = await cookieJar.loadForRequest(domainUri);
      
      if (cookies.isNotEmpty) {
        return cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (e) {
      debugPrint('获取用户 $userId 的Cookie失败: $e');
    }
    return null;
  }

  /// 普通签到（可带照片）
  static Future<String?> normalSign(String courseId, String activeId, User user,
      {String? objectId, String? validate}) async {
    try {
      Map<String, String> params = {
        'activeId': activeId,
        'courseId': courseId,
        'uid': user.uid,
        'clientip': '',
        'latitude': '-1',
        'longitude': '-1',
        'appType': '15',
        'fid': '0',
        'objectId': '',
        'name': user.name,
        'validate': '',
        'deviceCode': _deviceCode
      };
      if (objectId == null) {
        params.remove('objectId');
      } else {
        params['objectId'] = objectId;
      }

      if (validate == null) {
        params.remove('validate');
      } else {
        params['validate'] = validate;
      }

      final cookieStr = await _getUserCookie(user.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(_signUrl, params: params, headers: headers, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('normalSign error: $e');
    }
    return null;
  }

  /// 检查手势 签到码
  static Future<bool?> checkSignCode(String activeId, String signCode) async {
    try {
      String url = 'https://mobilelearn.chaoxing.com/widget/sign/pcStuSignController/checkSignCode';

      final params = {
        'activeId': activeId,
        'signCode': signCode
      };

      final response = await ApiService.sendRequest(url, method: "GET", params: params);
      return response.data['result'] == 1;
      // {"result":1,"msg":"验证成功","data":null,"errorMsg":null}
      // {"result":0,"msg":null,"data":null,"errorMsg":"手势不正确"}
    } catch (e) {
      debugPrint('checkSignCode error: $e');
    }
    return null;
  }

  /// 手势 签到码签到
  static Future<String?> codeSign(String courseId, String activeId, String signCode,
  User user, {String? validate}) async {
    try {
      final params = {
        'activeId': activeId,
        'courseId': courseId,
        'uid': user.uid,
        'clientip': '',
        'latitude': '-1',
        'longitude': '-1',
        'appType': '15',
        'fid': '0',
        'name': user.name,
        'signCode': signCode,
        'validate': '',
        'deviceCode': _deviceCode
      };
      if (validate == null) {
        params.remove('validate');
      } else {
        params['validate'] = validate;
      }

      final cookieStr = await _getUserCookie(user.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(_signUrl, params: params, headers: headers, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('codeSign error: $e');
    }
    return null;
  }

  /// 获取首次采集的人脸图片ID
  static Future<String?> getFaceId(User user) async {
    try {
      final enc = EncryptionUtil.md5Hash(user.uid + Constant.getFaceSalt);
      final url = 'https://passport2-api.chaoxing.com/api/getUserFaceid?enc=$enc';

      final cookieStr = await _getUserCookie(user.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(url, headers: headers);
      final data = response.data;
      // {"result":1,"msg":"获取成功","data":{"http":"http://p.ananas.chaoxing.com/star3/origin/$objectid.jpg","objectid":objectid},"errorMsg":""}
      // 如果没有采集过人脸则为空字符串
      if (data['result'] == 1) {
        return data['data']['objectid'];
      }
    } catch (e) {
      debugPrint('getFace error: $e');
    }
    return null;
  }

  /// 位置签到
  static Future<String?> locationSign(String courseId, String activeId, String address,
      double latitude, double longitude, User user, {String? validate, String? faceId}) async {
    try {
      Map<String, String> params = {
        'name': user.name,
        'address': address,
        'activeId': activeId,
        'courseId': courseId,
        'uid': user.uid,
        'clientip': '',
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
        'fid': '0',
        'appType': '15',
        'ifTiJiao': '1',
        'validate': '',
        'deviceCode': _deviceCode,
        'vpProbability': '-1', // 此定位点作弊概率，3代表高概率，2代表中概率，1代表低概率，0代表概率为0
        'vpStrategy': '', // 防作弊策略识别码，用于辅助分析排查问题
        'currentFaceId': '',
        'ifCFP': '0'
      };

      if (validate == null) {
        params.remove('validate');
      } else {
        params['validate'] = validate;
      }

      if (faceId != null){
        params['currentFaceId'] = faceId;
      }

      final cookieStr = await _getUserCookie(user.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(_signUrl, params: params, headers: headers, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('locationSign error: $e');
    }
    return null;
  }

  /// 获取签到详细
  // 经测试 所有签到可用
  static Future<Map<String, dynamic>?> getSignDetail(String activeId, [String? code]) async {
    try {
      String url = 'https://mobilelearn.chaoxing.com/newsign/signDetail?activePrimaryId=$activeId&type=1';
      if (code != null) {
        url += '&msg=$code';
      }

      final response = await ApiService.sendRequest(url);
      return response.data;
    } catch (e) {
      debugPrint('getSignDetail error: $e');
    }
    return null;
  }

  /// 二维码签到（可带定位）
  /// 需要验证码时第一次发送会返回validate_${enc2}
  /// enc2用于固定enc
  static Future<String?> qrCodeSign(String courseId, String activeId, String enc, User user,
      {String? address, double? latitude, double? longitude, String? enc2, String? validate, String? faceId}) async {
    try {
      Map<String, String> params = {
        'enc': enc,
        'name': user.name,
        'activeId': activeId,
        'uid': user.uid,
        'clientip': '',
        'location': '',
        'latitude': '-1',
        'longitude': '-1',
        'fid': '0',
        'appType': '15',
        'deviceCode': _deviceCode,
        'vpProbability': '',
        'vpStrategy': '',
        'enc2': '',
        'validate': '',
        'currentFaceId': '',
        'ifCFP': '0',
        'courseId': courseId
      };

      if (address != null && latitude != null && longitude != null) {
        String locationJson = '{"result":1,"latitude":$latitude,"longitude":$longitude,"mockData":{"strategy":0,"probability":-1},"address":"$address"}';
        params['location'] = locationJson;
      }

      if (enc2 == null || validate == null) {
        params.remove('enc2');
        params.remove('validate');
      } else {
        params['enc2'] = enc2;
        params['validate'] = validate;
      }

      if (faceId != null){
        params['currentFaceId'] = faceId;
      }

      final cookieStr = await _getUserCookie(user.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(_signUrl, params: params, headers: headers, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('qrCodeSign error: $e');
    }
    return null;
  }

  /// 获取参与详细
  /// 仅签到活动可用
  static Future<Map<String, dynamic>?> getAttendInfoWeb(String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/sign/getAttendInfo?activeId=$activeId&moreClassAttendEnc=';

      final response = await ApiService.sendRequest(url);
      final data = response.data;
      if (data['result'] == 1){
        return data['data'];
      }
    } catch (e) {
      debugPrint('getActiveInfo error: $e');
    }
    return null;
  }
  // https://mobilelearn.chaoxing.com/widget/sign/pcTeaSignController/getAttendList
  // 存在权鉴

  /// 群聊签到
  /// 群聊签到没有签到码、防作弊
  /// 且相对于课程签到漏洞较多 没有严格权鉴
  // 手势 二维码不需要验证
  static Future<String?> groupSign(String activeId, User user,
      {String? objectId, String? address, double? latitude, double? longitude}) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/sign/stuSignajax';
      final params = {
        'activeId': activeId,
        'uid': user.uid,
        'clientip': '', // 10.0.85.*
        // 'useragent': HeadersManager.chaoxingHeaders['user-agent'] as String
      };

      if (objectId != null) {
        params['objectId'] = objectId;
      } else if (address != null) {
        final locationParams = {
          'address': address,
          'latitude': latitude!.toStringAsFixed(6),
          'longitude': longitude!.toStringAsFixed(6),
          'fid': '',
          'ifTiJiao': '1'
        };
        params.addAll(locationParams);
      }

      final cookieStr = await _getUserCookie(user.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(url, params: params, headers: headers, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('groupSign error: $e');
    }
    return null;
  }

  /// 签到回执
  static Future<Map<String, dynamic>?> getSignReceipt(String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/sign/signReceipt2?activeId=$activeId';

      final response = await ApiService.sendRequest(url);
      return response.data;
    } catch (e) {
      debugPrint('getSignReceipt error: $e');
    }
    return null;
  }

  /// 获取群聊签到详细
  static Future<Map<String, dynamic>?> getGroupSignDetail(String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/sign/getSignDetail?id=$activeId';

      final response = await ApiService.sendRequest(url);
      return response.data;
    } catch (e) {
      debugPrint('getGroupSignDetail error: $e');
    }
    return null;
  }

  /// 获取群聊签到列表（越权）
  static Future<Map<String, dynamic>?> getGroupAttendList(String activeId) async {
    try {
    final url = 'https://mobilelearn.chaoxing.com/widget/sign/group/pcTeaSignGroupController/getAttendList?activeId=$activeId';

      final response = await ApiService.sendRequest(url);
      if (response.data['result'] == 1){
        return response.data['data'];
      }
    } catch (e) {
      debugPrint('getGroupAttendList error: $e');
    }
    return null;
  }

  /// 使用指定用户数据进行群聊签到（越权）
  static Future<String?> groupSignWithUserData(String activeId, User currentUser, 
      Map<String, dynamic> targetUserData) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/sign/stuSignajax';
      final params = <String, String>{
        'activeId': activeId,
        'uid': currentUser.uid,
        'clientip': '',
        'name': targetUserData['name'] ?? currentUser.name,
        'fid': targetUserData['activeFid']?.toString() ?? '',
      };

      // 如果是位置签到
      if (targetUserData['title'] != null && targetUserData['title'].toString().isNotEmpty && targetUserData['longitude'] != null && targetUserData['latitude'] != null) {
        params.addAll({
          'address': targetUserData['title'].toString(),
          'latitude': targetUserData['latitude'].toString(),
          'longitude': targetUserData['longitude'].toString(),
          'ifTiJiao': '1'
        });
      }

      // 如果是拍照签到
      if (targetUserData['title'] != null && targetUserData['title'].toString().isNotEmpty) {
        params['objectId'] = targetUserData['title'].toString();
      }

      final cookieStr = await _getUserCookie(currentUser.uid) ?? '';
      final headers = {'Cookie': cookieStr};

      final response = await ApiService.sendRequest(url, params: params, headers: headers, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('groupSignWithUserData error: $e');
    }
    return null;
  }

  /// 获取群聊签到人数（越权）
  static Future<Map<String, dynamic>?> getGroupAttendCount(String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/widget/sign/group/pcTeaSignGroupController/getCount?activeId=$activeId';

      final response = await ApiService.sendRequest(url);
      if (response.data['result'] == 1){
        return response.data['data'];
      }
    } catch (e) {
      debugPrint('getGroupAttendCount error: $e');
    }
    return null;
  }
}