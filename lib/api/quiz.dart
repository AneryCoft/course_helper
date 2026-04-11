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
      String currentUid = AccountManager.currentSessionId ?? '';
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

  /// 获取测试详细（Web）
  /// 投票 问卷 使用
  static Future<Map<String, dynamic>?> getQuizDetail(String activeId, [bool v2 = false]) async {
    try {
      final url = v2 ?
      'https://mobilelearn.chaoxing.com/v2/apis/quiz/quizDetail?activeId=$activeId' :
      'https://mobilelearn.chaoxing.com/v2/apis/quiz/quizDetail2?activeId=$activeId&moreClassAttendEnc=&DB_STRATEGY=PRIMARY_KEY&STRATEGY_PARA=activeId';
      // 两个接口返回内容相同 但是随堂练习用v2
      // 该接口不会返回isAnswer
      final response = await ApiService.sendRequest(url);
      return response.data['data'];
    } catch (e) {
      debugPrint('getQuizDetail error: $e');
    }
    return null;
  }

  /// 投票提交
  static Future<Map<String, dynamic>?> submitVote(String courseId, String classId, String activeId, String questionId, String answer) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/widget/quickvote/doQuestion';
      // WebAPI: https://mobilelearn.chaoxing.com/v2/apis/qvote/doQuestion
      // AppAPI返回内容更少 更高效
      final formData = {
        'courseId': courseId,
        'classId': classId,
        'activeId': activeId,
        'questionId': questionId,
        // 'answer': answer,
        'option': answer
      };
      final response = await ApiService.sendRequest(url, method: 'POST', body: formData);
      return response.data;
    } catch (e) {
      debugPrint('submitVote error: $e');
    }
    return null;
  }

  /// 问卷提交
  static Future<Map<String, dynamic>?> submitQuestionnaire(String courseId, String classId, String activeId, Map<String, List<String>> answers) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/studentQuestion/doQuestion';
      // AppAPI: https://mobilelearn.chaoxing.com/pptTestPaperStu/doQuestion
      // AppAPI参数较多
      var formData = 'preventsubmit=1&courseId=$courseId&classId=$classId&activeId=$activeId';
      for (var entry in answers.entries) {
        formData += '&questionId=${entry.key}';
        for (var answer in entry.value) {
          formData += '&answer${entry.key}=$answer';
        }
      }
      final response = await ApiService.sendRequest(url, method: 'POST', body: formData);
      return response.data;
    } catch (e) {
      debugPrint('submitQuestionnaire error: $e');
    }
    return null;
  }
}