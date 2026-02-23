import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import 'api_service.dart';
import '../utils/encrypt.dart';
import '../models/user.dart';
import '../session/account.dart';


class SignInApi{
  static const String _signUrl = 'https://mobilelearn.chaoxing.com/pptSign/stuSignajax';
  static String get _deviceCode => EncryptionUtil.getDeviceCode();

  static String _userId = '';
  static User? _user;

  static String get userId => _userId;
  static User? get user => _user;
  static String get userName => _user?.name ?? '';

  /// 更新当前用户信息（从会话管理器获取）
  static Future<void> updateUser() async {
    String? currentUid = await AccountManager.getCurrentSession();
    if (currentUid != null) {
      User? currentUser = AccountManager.getAccountById(currentUid);
      if (currentUser != null) {
        _user = currentUser;
        _userId = currentUser.uid;
      }
    }
  }

  /// 上传图片
  static Future<String?> uploadImage(File imageFile) async {
    try {
      final tokenUrl = 'https://pan-yz.chaoxing.com/api/token/uservalid';
      final tokenResponse = await ApiService.sendRequest(tokenUrl, method: "GET");

      if (tokenResponse.data == null) {
        debugPrint('Failed to get token');
        return null;
      }
      String token = tokenResponse.data['_token'];

      final crcUrl = 'https://pan-yz.chaoxing.com/api/crcStorageStatus';

      final crc = await EncryptionUtil.getCRC(imageFile);
      final crcParams = {
        'puid': userId,
        'crc': crc,
        '_token': token
      };

      await ApiService.sendRequest(crcUrl, method: "GET", params: crcParams);

      DateTime now = DateTime.now();
      String timestamp = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
      final milliseconds = DateTime.now().millisecond.toString().padLeft(3, '0');
      String formattedTime = '$timestamp$milliseconds';
      String fileName = "$formattedTime.jpg";
      // 20260205191805009.jpg

      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
        'puid': userId
      });

      String uploadUrl = 'https://pan-yz.chaoxing.com/upload?_from=mobilelearn&_token=$token';

      final uploadResponse = await ApiService.sendRequest(
        uploadUrl,
        method: "POST",
        body: formData,
      );

      Map<String, dynamic> responseData = uploadResponse.data;
      String? objectId = responseData['data']['objectId'];
      return objectId;
    } catch (e) {
      debugPrint('uploadImage error: $e');
    }
    return null;
  }

  /// 普通签到（可带照片）
  static Future<String?> normalSign(String courseId, String activeId,
      {String? objectId, String? validate}) async {
    try {
      Map<String, String> params = {
        'activeId': activeId,
        'courseId': courseId,
        'uid': userId,
        'clientip': '',
        'latitude': '-1',
        'longitude': '-1',
        'appType': '15',
        'fid': '0',
        'objectId': '',
        'name': userName,
        'validate': '',
        'deviceCode': _deviceCode
      };
      if (objectId == null) {
        params.remove(objectId);
      } else {
        params['objectId'] = objectId;
      }

      if (validate == null) {
        params.remove(validate);
      } else {
        params['validate'] = validate;
      }

      final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain);
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
      {String? validate}) async {
    try {
      final params = {
        'activeId': activeId,
        'courseId': courseId,
        'uid': userId,
        'clientip': '',
        'latitude': '-1',
        'longitude': '-1',
        'appType': '15',
        'fid': '0',
        'name': userName,
        'signCode': signCode,
        'validate': '',
        'deviceCode': _deviceCode
      };
      if (validate == null) {
        params.remove(validate);
      } else {
        params['validate'] = validate;
      }

      final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('codeSign error: $e');
    }
    return null;
  }

  /// 位置签到
  static Future<String?> locationSign(String courseId, String activeId, String address,
      double latitude, double longitude, {String? validate}) async {
    try {
      Map<String, String> params = {
        'name': userName,
        'address': address,
        'activeId': activeId,
        'courseId': courseId,
        'uid': userId,
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

      final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain);
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
  static Future<String?> qrCodeSign(String courseId, String activeId, String enc,
      {String? address, double? latitude, double? longitude, String? enc2, String? validate}) async {
    try {
      Map<String, String> params = {
        'enc': enc,
        'name': userName,
        'activeId': activeId,
        'uid': userId,
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

      final response = await ApiService.sendRequest(_signUrl, params: params, responseType: ResponseType.plain);
      return response.data;
    } catch (e) {
      debugPrint('qrCodeSign error: $e');
    }
    return null;
  }
}