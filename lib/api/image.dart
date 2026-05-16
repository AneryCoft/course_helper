import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import 'api_service.dart';
import '../utils/encrypt.dart';

class CXImageApi extends Api {
  CXImageApi([super.user]);

  /// 上传图片到学习通云盘
  Future<String?> uploadImage(File imageFile) async {
    final tokenUrl = 'https://pan-yz.chaoxing.com/api/token/uservalid';
    final tokenResponse = await ApiService.sendRequest(tokenUrl);

    if (tokenResponse == null || tokenResponse.data == null) {
      debugPrint('Failed to get token');
      return null;
    }
    final String token = tokenResponse.data['_token'];

    final crcUrl = 'https://pan-yz.chaoxing.com/api/crcStorageStatus';
    final crc = await EncryptionUtil.getCRC(imageFile);
    final crcParams = {
      'puid': user!.uid,
      'crc': crc,
      '_token': token
    };
    final crcResponse = await ApiService.sendRequest(crcUrl, params: crcParams);
    if (crcResponse == null) return null;
    
    final data = crcResponse.data;
    if (data['result'] && data['exist']) {
      final imageFileData = data['data'];
      return imageFileData['objectid'];
    }

    DateTime now = DateTime.now();
    final timestamp = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    final milliseconds = DateTime.now().millisecond.toString().padLeft(3, '0');
    final formattedTime = '$timestamp$milliseconds';
    final fileName = "$formattedTime.jpg";
    // DateFormat('yyyyMMddHHmmssSSS').format(DateTime.now());

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
      'puid': user!.uid
    });

    final uploadUrl = 'https://pan-yz.chaoxing.com/upload?_from=mobilelearn&_token=$token';

    final uploadResponse = await ApiService.sendRequest(uploadUrl, method: "POST", body: formData);
    if (uploadResponse == null) return null;
    
    final objectId = uploadResponse.data['data']['objectId'];

    return objectId;
  }

  /// 通过objectId获取图片Url
  static String getImageUrl(String objectId) {
    return 'https://p.ananas.chaoxing.com/star4/$objectId/origin.jpg';
  }

  static String getImageUrlWithSize(String objectId, int? width, int? height){
    final size = width == null || height == null ?
    'origin' : '${width}_${height}c';
    return 'https://p.cldisk.com/star4/$objectId/$size.jpg';
  }

  /// 通过UserId获取头像Url
  static String getAvatarUrlByUid(String uid, int size) {
    return 'https://photo.chaoxing.com/p/${uid}_$size';
    // 跳转到https://p.cldisk.com/star3
  }

  /// 将学习通的Star3图片转换为Star4 减少一次重定向
  static String toNewImageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length >= 3) {
        final size = pathSegments[1];
        final fileNameWithExt = pathSegments[2];

        final lastDotIndex = fileNameWithExt.lastIndexOf('.');
        if (lastDotIndex != -1) {
          final filename = fileNameWithExt.substring(0, lastDotIndex);
          final extension = fileNameWithExt.substring(lastDotIndex);
          return '${uri.scheme}://${uri.host}/star4/$filename/$size$extension';
        } else {
          return '${uri.scheme}://${uri.host}/star4/$fileNameWithExt/$size.png';
        }
      }
    } catch (e) {
      debugPrint('URL转换失败: $e');
    }
    return url;
  }
}

class RCImageApi {
  /// 上传图片到七牛云
  static Future<String?> uploadImage(File imageFile) async {
    final tokenUrl = '/pc/generate_qiniu_token';
    final jsonData = {
      'bucket_name': 'cms-attachment',
      'expired_time': 3600
    };
    final tokenResponse = await ApiService.sendRequest(tokenUrl, method: 'POST', body: jsonData);

    if (tokenResponse == null || tokenResponse.data == null ||
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

    if (uploadResponse == null || uploadResponse.data == null ||
        uploadResponse.data['success'] != true) {
      debugPrint('Failed to upload to qiniu');
      return null;
    }

    final key = uploadResponse.data['key'];
    final imageUrl = 'https://qn-scd1.yuketang.cn/$key';
    return imageUrl;
  }
}