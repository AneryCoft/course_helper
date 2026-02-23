import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import '../utils/encrypt.dart';

class CaptchaApi {
  late int _timestamp;
  late String _iv;
  static final RegExp _captchaRegExp = RegExp(r'cx_captcha_function\((.+)\)');

  
  /// 获取验证码图片
  Future<Map<String, dynamic>?> getCaptchaImages(String referer) async {
    _timestamp = DateTime.now().millisecondsSinceEpoch;
    
    try {
      final configUrl = 'https://captcha.chaoxing.com/captcha/get/conf';
      final configParams = {
        'callback': 'cx_captcha_function',
        'captchaId': Constant.captchaId,
        '_': _timestamp.toString()
      };

      final configResponse = await ApiService.sendRequest(configUrl, params: configParams, responseType: ResponseType.plain);

      // 解析配置响应
      String configResponseText = configResponse.data;
      Match? configMatch = _captchaRegExp.firstMatch(configResponseText);
      
      if (configMatch == null) {
        debugPrint('Error: Failed to parse captcha config response');
        return null;
      }

      String configJsonString = configMatch.group(1)!.trim();
      Map<String, dynamic> config = jsonDecode(configJsonString);

      int serviceTime = config['t'];
      String captchaKey = EncryptionUtil.md5Hash('$serviceTime${_uuid()}');
      String token = '${EncryptionUtil.md5Hash('$serviceTime${Constant.captchaId}slide$captchaKey')}:${serviceTime + 300000}';
      _iv = EncryptionUtil.md5Hash('${Constant.captchaId}slide$_timestamp${_uuid()}');

      final imageUrl = 'https://captcha.chaoxing.com/captcha/get/verification/image';
      final imageParams = {
        'callback': 'cx_captcha_function',
        'captchaId': Constant.captchaId,
        'type': 'slide',
        'version': '1.1.20',
        'captchaKey': captchaKey,
        'token': token,
        'referer': referer,
        'iv': _iv,
        '_': (_timestamp + 1).toString()
      };

      final response = await ApiService.sendRequest(imageUrl, params: imageParams, responseType: ResponseType.plain);

      String responseText = response.data;
      Match? match = _captchaRegExp.firstMatch(responseText);

      if (match != null) {
        String jsonString = match.group(1)!.trim();
        return jsonDecode(jsonString);
      }
    } catch (e) {
      debugPrint('Error getting captcha images: $e');
    }
    return null;
  }

  /// 提交验证码结果
  Future<String?> submitCaptcha(double xValue, String token, String referer) async {
    if (_iv.isEmpty || _timestamp <= 0) {
      debugPrint('Error: iv or timestamp not initialized');
      return null;
    }
    
    try {
      final url = 'https://captcha.chaoxing.com/captcha/check/verification/result';
      final params = {
        'callback': 'cx_captcha_function',
        'captchaId': Constant.captchaId,
        'type': 'slide',
        'token': token,
        'textClickArr': '[{"x":${xValue.round()}}]',
        'coordinate': '[]',
        'runEnv': '10',
        'version': '1.1.20',
        't': 'a',
        'iv': _iv,
        '_': (_timestamp + 2).toString()
      };
      
      final response = await ApiService.sendRequest(url, params: params, headers: {'Referer': referer}, responseType: ResponseType.plain);

      String responseText = response.data;
      Match? match = _captchaRegExp.firstMatch(responseText);

      if (match != null) {
        String jsonString = match.group(1)!.trim();
        Map<String, dynamic> result = jsonDecode(jsonString);

        if (result['error'] == 0 && result['result'] == true) {
          // 解析extraData中的validate
          String extraData = result['extraData'];
          Map<String, dynamic> extraDataMap = jsonDecode(extraData);
          return extraDataMap['validate'];
        }
      }
    } catch (e) {
      debugPrint('Error submitting captcha: $e');
    }
    return null;
  }

  /// 生成UUID
  static String _uuid() {
    Random random = Random();
    String hexChars = "0123456789abcdef";
    List<String> vA = List.generate(36, (index) => hexChars[random.nextInt(16)]);
    
    vA[14] = "4";
    String originalChar = vA[19];
    int num = int.tryParse(originalChar, radix: 16) ?? 0;
    int newValue = (num & 3) | 8;
    vA[19] = hexChars[newValue];

    List<int> dashPositions = [8, 13, 18, 23];
    for (int pos in dashPositions) {
      vA[pos] = "-";
    }
    
    return vA.join('');
  }
}