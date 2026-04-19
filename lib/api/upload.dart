import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import 'api_service.dart';
import '../utils/encrypt.dart';

class CXUploadApi {
  /// 上传图片到学习通云盘
  static Future<String?> uploadImage(File imageFile, String userId) async {
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
}

class RCUploadApi {
  /// 上传图片到七牛云
  static Future<String?> uploadImage(File imageFile) async {
    try {
      final tokenUrl = '/pc/generate_qiniu_token';
      final jsonData = {
        'bucket_name': 'cms-attachment',
        'expired_time': 3600
      };
      final tokenResponse = await ApiService.sendRequest(tokenUrl, method: 'POST', body: jsonData);

      if (tokenResponse.data == null ||
          tokenResponse.data['success'] != true ||
          tokenResponse.data['data'] == null) {
        debugPrint('Failed to get qiniu token');
        return null;
      }

      final token = tokenResponse.data['data']['token'];

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final originalFileName = imageFile.path.split('/').last;
      final fileName = '$timestamp$originalFileName';

      final uploadUrl = 'https://upload.qiniup.com/';
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
        'token': token,
        'key': fileName,
        'fname': originalFileName
      });
      final uploadResponse = await ApiService.sendRequest(uploadUrl, method: 'POST', body: formData);

      if (uploadResponse.data == null ||
          uploadResponse.data['success'] != true) {
        debugPrint('Failed to upload to qiniu');
        return null;
      }

      final key = uploadResponse.data['key'];
      final imageUrl = 'https://qn-scd1.yuketang.cn/$key';
      return imageUrl;
    } catch (e) {
      debugPrint('uploadImageToQiniu error: $e');
    }
    return null;
  }
}