import 'api_service.dart';
import '../utils/encrypt.dart';

class TopicDiscussApi extends Api {
  TopicDiscussApi([super.user]);

  /// 获取主题讨论
  Future<Map<String, dynamic>?> getTopic(String topicId) async {
    final url = 'https://groupyd.chaoxing.com/apis/topic/getTopic';
    final params = EncryptionUtil.getEncParams({});
    final formData = {
      'puid': user!.uid,
      'maxW': '1080',
      'topicId': topicId
    };

    final response = await ApiService.sendRequest(url, method: 'POST', params: params, body: formData, userId: user?.uid);
    return response?.data;
  }

  /// 获取回复
  Future<Map<String, dynamic>?> getReplies(String uuid) async {
    // getTopicReplys 无法获取内容
    final url = 'https://groupyd.chaoxing.com/apis/invitation/getReplys2';
    final params = EncryptionUtil.getEncParams({});
    final formData = {
      'puid': user!.uid,
      'uuid': uuid,
      'maxW': '1080',
      'lastValue': '',
      'lastAuxValue': '',
      // 'uuid': '',
      'order': '0'
    };
    final response = await ApiService.sendRequest(url, method:'POST', params: params, body: formData, userId: user?.uid);
    return response?.data;
  }

  /// 添加回复
  Future<Map<String, dynamic>?> addReply(String message, bool anonymous, String uuid) async {
    final url = 'https://groupyd.chaoxing.com/apis/invitation/addReply';
    final params = {
      'puid': user!.uid,
      'uuid': EncryptionUtil.getUuid(),
      'maxW': '1080',
      'topicUUID': uuid,
      'anonymous': anonymous? '1':'0'
    };
    params.addAll(EncryptionUtil.getEncParams(params));
    final formData = {
      'content': message
    };

    final response = await ApiService.sendRequest(url, method:'POST', params: params, body: formData, userId: user?.uid);
    return response?.data;
    // {"result":0,"errorMsg":"该话题至少回复10字"}
  }
}
