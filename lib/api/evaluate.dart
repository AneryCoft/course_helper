import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

class EvaluateApi {
  /// 提交评分
  static Future<bool?> stuSubmitAnswer(String activeId, String classId, String courseId, int score,
      {String? content, List<int>? scoreList}) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/score/stuSubmitAnswer';
      final formData = {
        'classId': classId,
        'content': content ?? '',
        'score': score.toString(), // 总分
        'scoreList': jsonEncode(scoreList ?? []), // 分项评分
        'activeId': activeId,
        'courseId': courseId
      };

      final response = await ApiService.sendRequest(url, method: 'POST', body: formData);
      return response.data['result'] == 1;
      // {"result": 1,"msg": "评分成功","data": {"activeId":},"errorMsg": null}
    } catch (e) {
      debugPrint('stuSubmitAnswer error: $e');
    }
    return null;
  }

  /// 获取评分详细信息
  static Future<Map<String, dynamic>?> getStuScoreDetail(String activeId, String classId, String courseId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/score/getStuScoreDetail';
      final params = {
        'activeId': activeId,
        'classId': classId,
        'courseId': courseId
      };

      final response = await ApiService.sendRequest(url, method: 'GET', params: params);
      return response.data;
    } catch (e) {
      debugPrint('getStuScoreDetail error: $e');
    }
    return null;
  }
}
