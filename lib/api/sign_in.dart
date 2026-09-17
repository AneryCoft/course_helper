import 'package:dio/dio.dart';
import 'dart:convert';

import 'api_service.dart';
import '../utils/encrypt.dart';
import '../models/user.dart';


class Location {
  final User? user;
  final String address;
  final double latitude;
  final double longitude;

  Location({this.user, required this.address, required this.latitude, required this.longitude});

  // location
  String toJson() {
    return jsonEncode({
      'result': 1,
      'address': address,
      'longitude': longitude,
      'latitude': latitude
    });
  }

  // locationResult
  String toResultJson() {
    final timeStampMS = DateTime.now().millisecondsSinceEpoch.toString();
    final cxcid = user?.deviceInfo?['cid'] ?? '';
    final sc = user?.deviceInfo?['sc'] ?? '';

    final signConfigMap = {
      'data': '{"latitude":$latitude,"longitude":$longitude,"address":"$address"}',
      'cxtime': timeStampMS,
      'cxcid': cxcid
    };

    final sortedKeys = signConfigMap.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      buffer.write('$key${signConfigMap[key]}');
    }
    buffer.write(sc);
    final signToken = EncryptionUtil.md5Hash(buffer.toString());


    return jsonEncode({
      'result': 1,
      'latitude': latitude,
      'longitude': longitude,
      'mockData': {'strategy': 0, 'probability': -1},
      'locType': 161, // -200 说明客户端获取到了经纬度，但是没有获取到位置描述
      'address': address,
      'signConfig': {
        'signToken': signToken,
        'cxcid': cxcid,
        'cxtime': timeStampMS
      }
    });
  }
}

class SignInApi extends Api {
  SignInApi([super.user]);
  
  static const String _signUrl = 'https://mobilelearn.chaoxing.com/pptSign/stuSignajax';
  String get _deviceCode => EncryptionUtil.getDeviceCode();

  /// 普通签到（可带照片）
  Future<String?> normalSign(String courseId, String activeId,
      {String? objectId, String? validate}) async {
    final params = {
      'activeId': activeId,
      'courseId': courseId,
      'uid': user?.uid ?? '',
      'clientip': '',
      'latitude': '-1',
      'longitude': '-1',
      'appType': '15',
      'fid': '0',
      'objectId': '',
      'name': user?.name ?? '',
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

    final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain, userId: user?.uid);
    return response?.data;
  }

  /// 检查手势 签到码
  static Future<String?> checkSignCode(String activeId, String signCode) async {
    final url = 'https://mobilelearn.chaoxing.com/widget/sign/pcStuSignController/checkSignCode';

    final params = {
      'activeId': activeId,
      'signCode': signCode
    };

    final response = await ApiService.sendRequest(url, params: params);
    return response?.data['errorMsg'];
    // {"result":1,"msg":"验证成功","data":null,"errorMsg":null}
    // {"result":0,"msg":null,"data":null,"errorMsg":"手势不正确"}
    // {"result":-1,"msg":null,"data":null,"errorMsg":"验证失败次数过多，本次签到已锁定，请 1 小时后重试"}
  }

  /// 手势 签到码签到
  Future<String?> codeSign(String courseId, String activeId, String signCode,
      {String? address, double? latitude, double? longitude, String? validate}) async {
    final params = {
      'activeId': activeId,
      'courseId': courseId,
      'uid': user?.uid ?? '',
      'clientip': '',
      'latitude': '-1',
      'longitude': '-1',
      'appType': '15',
      'fid': '0',
      'name': user?.name ?? '',
      'signCode': signCode,
      'validate': '',
      'deviceCode': _deviceCode
    };
    if (validate == null) {
      params.remove('validate');
    } else {
      params['validate'] = validate;
    }
    if (address != null && latitude != null && longitude != null) {
      params['latitude'] = latitude.toStringAsFixed(6);
      params['longitude'] = longitude.toStringAsFixed(6);

      final location = Location(user: user, address: address, latitude: latitude, longitude: longitude);
      params['location'] = location.toJson();
      params['locationResult'] = location.toResultJson();
    }

    final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain, userId: user?.uid);
    return response?.data;
  }

  /// 位置签到
  Future<String?> locationSign(String courseId, String activeId, String address,
      double latitude, double longitude, {String? validate, String? faceId, String? faceEnc}) async {
    final data = {
      'name': user?.name ?? '',
      'address': address,
      'activeId': activeId,
      'courseId': courseId,
      'uid': user?.uid ?? '',
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
      'ifCFP': '0',
      'faceEnc': ''
    };

    if (validate == null) {
      data.remove('validate');
    } else {
      data['validate'] = validate;
    }

    if (faceId != null) {
      data['currentFaceId'] = faceId;
      data['ifCFP'] = '1';
    }
    if (faceEnc != null) {
      data['faceEnc'] = faceEnc;
    }

    final location = Location(user: user, address: address, latitude: latitude, longitude: longitude);
    data['locationResult'] = location.toResultJson();

    final response = await ApiService.sendRequest(_signUrl, method: 'POST', body: data, responseType: ResponseType.plain, userId: user?.uid);
    return response?.data;
  }

  /// 获取签到详细
  // 经测试 所有签到可用
  static Future<Map<String, dynamic>?> getSignDetail(String activeId, [String? code]) async {
    String url = 'https://mobilelearn.chaoxing.com/newsign/signDetail?activePrimaryId=$activeId&type=1';
    if (code != null) {
      url += '&msg=$code';
    }

    final response = await ApiService.sendRequest(url);
    return response?.data;
  }

  /// 二维码签到（可带定位）
  /// 需要验证码时第一次发送会返回validate_${enc2}
  /// enc2用于固定enc
  Future<String?> qrCodeSign(String courseId, String activeId, String enc,
      {String? address, double? latitude, double? longitude, String? enc2, String? validate, String? faceId, String? faceEnc}) async {
    final params = {
      'enc': enc,
      'name': user?.name ?? '',
      'activeId': activeId,
      'uid': user?.uid ?? '',
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
      'courseId': courseId,
      'faceEnc': ''
    };

    if (address != null && latitude != null && longitude != null) {
      final location = Location(user: user, address: address, latitude: latitude, longitude: longitude);
      params['location'] = location.toJson();
      params['locationResult'] = location.toResultJson();
    }

    if (enc2 == null || validate == null) {
      params.remove('enc2');
      params.remove('validate');
    } else {
      params['enc2'] = enc2;
      params['validate'] = validate;
    }

    if (faceId != null) {
      params['currentFaceId'] = faceId;
      params['ifCFP'] = '1';
    }
    if (faceEnc != null) {
      params['faceEnc'] = faceEnc;
    }

    final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain, userId: user?.uid);
    return response?.data;
  }

  /// 获取参与详细
  /// 仅签到活动可用
  /// 可通过 userId 指定账号查询（使用对应账号的 Cookie）
  static Future<Map<String, dynamic>?> getAttendInfoWeb(String activeId, {String? userId}) async {
    final url = 'https://mobilelearn.chaoxing.com/v2/apis/sign/getAttendInfo?activeId=$activeId&moreClassAttendEnc=';

    final response = await ApiService.sendRequest(url, userId: userId);
    if (response == null) return null;
    
    final data = response.data;
    if (data['result'] == 1){
      return data['data'];
    }
    return null;
  }
  // https://mobilelearn.chaoxing.com/widget/sign/pcTeaSignController/getAttendList
  // 存在权鉴

  /// 群聊签到
  /// 群聊签到没有签到码、防作弊
  /// 且相对于课程签到漏洞较多 没有严格权鉴
  // 手势 二维码不需要验证
  Future<String?> groupSign(String activeId,
      {String? objectId, String? address, double? latitude, double? longitude}) async {
    final url = 'https://mobilelearn.chaoxing.com/sign/stuSignajax';
    final params = {
      'activeId': activeId,
      'uid': user?.uid ?? '',
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

    final response = await ApiService.sendRequest(url, params: params, responseType: ResponseType.plain, userId: user?.uid);
    return response?.data;
  }

  /// 签到回执
  static Future<Map<String, dynamic>?> getSignReceipt(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/sign/signReceipt2?activeId=$activeId';

    final response = await ApiService.sendRequest(url);
    return response?.data;
  }

  /// 获取群聊签到详细
  static Future<Map<String, dynamic>?> getGroupSignDetail(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/sign/getSignDetail?id=$activeId';

    final response = await ApiService.sendRequest(url);
    return response?.data;
  }

  /// 获取群聊签到列表（越权）
  static Future<Map<String, dynamic>?> getGroupAttendList(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/widget/sign/group/pcTeaSignGroupController/getAttendList?activeId=$activeId';

    final response = await ApiService.sendRequest(url);
    if (response == null) return null;
    
    if (response.data['result'] == 1){
      return response.data['data'];
    }
    return null;
  }

  /// 使用指定用户数据进行群聊签到（越权）
  Future<String?> groupSignWithUserData(String activeId, 
      Map<String, dynamic> targetUserData) async {
    final url = 'https://mobilelearn.chaoxing.com/sign/stuSignajax';
    final params = <String, String>{
      'activeId': activeId,
      'uid': user?.uid ?? '',
      'clientip': '',
      'name': targetUserData['name'] ?? user?.name ?? '',
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

    final response = await ApiService.sendRequest(url, params: params, responseType: ResponseType.plain, userId: user?.uid);
    return response?.data;
  }

  /// 获取群聊签到人数（越权）
  static Future<Map<String, dynamic>?> getGroupAttendCount(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/widget/sign/group/pcTeaSignGroupController/getCount?activeId=$activeId';

    final response = await ApiService.sendRequest(url);
    if (response == null) return null;
    
    if (response.data['result'] == 1){
      return response.data['data'];
    }
    return null;
  }
}