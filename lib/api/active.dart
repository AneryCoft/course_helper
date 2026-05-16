import 'api_service.dart';


class ActiveApi extends Api {
  ActiveApi([super.user]);

  /// 获取活动详细（Web）
  static Future<Map<String, dynamic>?> getActiveInfoWeb(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo?activeId=$activeId';
    final response = await ApiService.sendRequest(url);
    
    if (response == null || response.data['result'] != 1) {
      return null;
    }
    
    return response.data['data'];
  }

  /// 获取活动详细
  static Future<Map<String, dynamic>?> getActiveInfo(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/widget/active/getActiveInfo?id=$activeId';
    final response = await ApiService.sendRequest(url);
    return response?.data;
  }
}