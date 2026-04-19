import 'package:flutter/foundation.dart';

import 'api_service.dart';


class ActiveApi {
  /// 获取活动详细（Web）
  static Future<Map<String, dynamic>?> getActiveInfoWeb(String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo?activeId=$activeId';
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

  /// 获取活动详细
  static Future<Map<String, dynamic>?> getActiveInfo(String activeId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/widget/active/getActiveInfo?id=$activeId';

      final response = await ApiService.sendRequest(url);
      return response.data;
    } catch (e) {
      debugPrint('getActiveInfo error: $e');
    }
    return null;
  }
}