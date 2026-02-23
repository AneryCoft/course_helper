import 'package:flutter/foundation.dart';

import '../session/account.dart';
import 'api_service.dart';

class QuizApi {
  /// 检查练习是否开启
  static Future<bool?> checkStatus(String classId, String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/pptTestPaperStu/checkActiveStatus';
      final formData = {
        'classId': classId,
        'activePrimaryId': activeId,
        'appType': '15'
      };
      final response = await ApiService.sendRequest(url, method: 'POST', body: formData);
      // {"status":1,"type":42,"source":15}
      if (response.data['status'] != null) {
        return response.data['status'] == 1;
      }
    } catch (e) {
      debugPrint('checkStatus error: $e');
    }
    return null;
  }

  /// 提交答案
  static Future<Map<String, dynamic>?> submitAnswer(String classId, String courseId, String activeId, String answer) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/studentQuestion/doQuestionAnswering';
      final params = {
        'activeId': activeId,
        'courseId': courseId,
        'classId': classId,
        'DB_STRATEGY': 'PRIMARY_KEY',
        'STRATEGY_PARA': 'activeId'
      };
      final headers = {'Content-Type': 'application/json'};
      final response = await ApiService.sendRequest(
          url,
          method: 'POST',
          params: params,
          headers: headers,
          body: answer
      );
      // {"result":1,"msg":"success","data":null,"errorMsg":null}
      return response.data;
    } catch (e) {
      debugPrint('submitAnswer error: $e');
    }
    return null;
  }

  /// 向群聊发送回执消息（不必要）
  static Future<Map<String, dynamic>?> answerReceipt(String classId, String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/pptTestPaperStu/answerReceipt';
      String currentUid = await AccountManager.getCurrentSession() ?? '';
      final params = {
        'classId': classId,
        'activePrimaryId': activeId,
        'uid': currentUid,
        'chatId': '',
        'appType': '15',
        'openChatView': 'false'
      };
      final response = await ApiService.sendRequest(url, params: params);
      return response.data;
    } catch (e) {
      debugPrint('checkStatus error: $e');
    }
    return null;
  }
}