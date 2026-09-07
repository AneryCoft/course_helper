import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'image.dart';
import '../utils/encrypt.dart';

class FaceApi extends Api {
  FaceApi([super.user]);

  /// 获取首次采集的人脸图片ID
  /// 绕过人脸复用检测
  Future<String?> getFaceId() async {
    final enc = EncryptionUtil.md5Hash((user?.uid ?? '') + Constant.getFaceSalt);
    final url = 'https://passport2-api.chaoxing.com/api/getUserFaceid?enc=$enc';

    final response = await ApiService.sendRequest(url, userId: user?.uid);
    if (response == null) return null;

    final data = response.data;
    // {"result":1,"msg":"获取成功","data":{"http":"http://p.ananas.chaoxing.com/star3/origin/$objectid.jpg","objectid":objectid},"errorMsg":""}
    if (data['result'] == 1 && data['data'] != null) {
      final String? imageUrl = data['data']['http'];
      final String? originalObjectId = data['data']['objectid'];

      if (imageUrl == null || imageUrl.isEmpty) {
        return null;
      }

      try {
        final imageResponse = await ApiService.sendRequest(
            imageUrl,
            responseType: ResponseType.bytes,
            userId: user?.uid
        );

        // 写入临时文件
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/face_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(imageResponse?.data as List<int>);

        // 修改EXIF
        final exif = await Exif.fromPath(file.path);
        final randomStr = EncryptionUtil.md5Hash(DateTime.now().toString()).substring(0, 10);
        await exif.writeAttribute('UserComment', 'CourseHelper_$randomStr');
        await exif.close();

        final imageApi = CXImageApi(user);
        final newObjectId = await imageApi.uploadImage(file);

        if (await file.exists()) {
          await file.delete();
        }

        return newObjectId ?? originalObjectId;
      } catch (e) {
        return originalObjectId;
      }
    }
    return null;
  }

  /// 获取人脸加密参数
  Future<String?> getFaceEnc(String activeId, String faceId) async {
    final url = 'https://mobilelearn.chaoxing.com/pptSign/check-face-result';
    final timeStampMS = DateTime.now().millisecondsSinceEpoch.toString();
    final faceResult = {
      "currentFaceId": faceId,
      "LiveDetectionStatus": '1',
      "collectStatus": '1',
      "cxcid": user!.deviceInfo!['cid'],
      "cxtime": timeStampMS
    };

    faceResult['signToken'] = getSignToken(faceResult);

    final params = {
      "DB_STRATEGY": "PRIMARY_KEY",
      "STRATEGY_PARA": "activeId",
      "activeId": activeId,
      "faceResult": jsonEncode(faceResult)
    };

    final response = await ApiService.sendRequest(url, params: params, userId: user?.uid);
    if (response == null) return null;

    final data = response.data;
    // {"status":1,"enc":""}
    if (data['status'] == 1) {
      return data['enc'];
    }
    return null;
  }

  String getSignToken(Map<String, dynamic> map) {
    final sortedKeys = map.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      final value = map[key] ?? '';
      buffer.write('$key$value');
    }
    buffer.write(user!.deviceInfo!['sc']);

    final signToken = EncryptionUtil.md5Hash(buffer.toString());
    return signToken;
  }
}