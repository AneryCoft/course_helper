import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../session/account.dart';
import 'api_service.dart';
import '../utils/encrypt.dart';

class TopicDiscussApi {
  static String _userId = '';
  static User? _user;

  static String get userId => _userId;
  static User? get user => _user;
  static String get userName => _user?.name ?? '';
  
  /// 更新当前用户信息（从会话管理器获取）
  static void updateUser() {
    String? currentUid = AccountManager.currentSessionId;
    if (currentUid != null) {
      User? currentUser = AccountManager.getAccountById(currentUid);
      if (currentUser != null) {
        _user = currentUser;
        _userId = currentUser.uid;
      }
    }
  }

  /// 获取主题讨论
  static Future<Map<String, dynamic>?> getTopic(String topicId) async {
    try {
      final url = 'https://groupyd.chaoxing.com/apis/topic/getTopic';
      final params = EncryptionUtil.getEncParams({});
      final formData = {
        'puid': userId,
        'maxW': '1080',
        'topicId': topicId
      };

      final response = await ApiService.sendRequest(url, method: 'POST', params: params, body: formData);
      return response.data;
    } catch (e) {
      debugPrint('getTopic error: $e');
    }
    return null;
  }

  /// 获取回复
  static Future<Map<String, dynamic>?> getReplies(String uuid) async {
    try {
      // getTopicReplys 无法获取内容
      final url = 'https://groupyd.chaoxing.com/apis/invitation/getReplys2';
      final params = EncryptionUtil.getEncParams({});
      final formData = {
        'puid': userId,
        'uuid': uuid,
        'maxW': '1080',
        'lastValue': '',
        'lastAuxValue': '',
        // 'uuid': '',
        'order': '0'
      };
      final response = await ApiService.sendRequest(url, method:'POST', params: params, body: formData);
      return response.data;
    } catch (e) {
      debugPrint('getReplies error: $e');
    }
    return null;
  }

  /// 添加回复
  static Future<Map<String, dynamic>?> addReply(String message, bool anonymous, String uuid) async {
    try {
      final url = 'https://groupyd.chaoxing.com/apis/invitation/addReply';
      Map<String, String> params = {
        'puid': userId,
        'uuid': EncryptionUtil.getUuid(),
        'maxW': '1080',
        'topicUUID': uuid,
        'anonymous': anonymous? '1':'0'
      };
      params.addAll(EncryptionUtil.getEncParams(params));
      final formData = {
        'content': message
      };

      final response = await ApiService.sendRequest(url, method:'POST', params: params, body: formData);
      return response.data;
      // {"result":0,"errorMsg":"该话题至少回复10字"}
    } catch (e) {
      debugPrint('addReply error: $e');
    }
    return null;
  }
}