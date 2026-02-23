import 'package:flutter/foundation.dart';

import 'api_service.dart';
import '../session/account.dart';
import '../utils/encrypt.dart';

class CourseApi {
  /// 获取课程列表
  static Future<Map<String, dynamic>?> getCourses() async {
    try {
      final url = 'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&getTchClazzType=1&mcode=';
      
      final response = await ApiService.sendRequest(url);
      return response.data;
    } catch (e) {
      debugPrint('getCourses error: $e');
    }
    return null;
  }

  /// 获取加入课程时间作为参数
  //（其实没必要）
  static Future<String?> getJoinClassTime(String courseId, String classId, String cpi) async {
    try {
      final url = 'https://mooc1-api.chaoxing.com/gas/clazzperson';
      final currentUserId = await AccountManager.getCurrentSession() ?? '';
      final params = {
        'courseid': courseId,
        'clazzid': classId,
        'userid': currentUserId,
        'personid': cpi,
        'view': 'json',
        'fields': 'clazzid,popupagreement,personid,clazzname,createtime'
      };

      final response = await ApiService.sendRequest(url, params: params);

      final joinClassTime = response.data['data'][0]['createtime'];
      return joinClassTime;
      /*
      {
          "data": [
              {
                  "createtime": "2026-01-19 11:56:27",
                  "clazzid": 134316250,
                  "personid": 534239555,
                  "popupagreement": 0
              }
          ]
      }
       */
    } catch (e) {
      debugPrint('getJoinClassTime error: $e');
    }
    return null;
  }

  /// 获取任务活动列表
  static Future<Map<String, dynamic>?> getTaskActivityList(String courseId, String classId, String cpi, String joinClassTime) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/ppt/activeAPI/taskactivelist';
      final currentUserId = await AccountManager.getCurrentSession() ?? '';

      Map<String, String> params = {
        'courseId': courseId,
        'classId': classId,
        'uid': currentUserId,
        'cpi': cpi,
        'joinclasstime': joinClassTime
      };
      params.addAll(EncryptionUtil.getEncParams(params));

      final response = await ApiService.sendRequest(url, method: 'GET', params: params);
      return response.data;
    } catch (e) {
      debugPrint('getTaskActivityList error: $e');
    }
    return null;
  }

  /// 获取任务活动列表（Web）
  static Future<Map<String, dynamic>?> getTaskActivityListWeb(String courseId, String classId) async {
    try {
      final url = 'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist';

      final timeStampMS = DateTime.now().millisecondsSinceEpoch.toString();
      // final fid = await CookieManager.getCookieValue('fid') ?? '';
      // 客户端登录的Cookie没有fid
      final params = {
        'fid': '0',
        'courseId': courseId,
        'classId': classId,
        'showNotStartedActive': '0',
        '_': timeStampMS
      };

      final response = await ApiService.sendRequest(url, method: 'GET', params: params);
      return response.data;
    } catch (e) {
      debugPrint('getTaskActivityList error: $e');
    }
    return null;
  }
}