import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import 'api_service.dart';
import '../session/account.dart';
import '../utils/encrypt.dart';
import '../models/active.dart';
import '../models/course.dart';

class CXCourseApi {
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

  /// 获取处理后的课程列表
  static Future<List<Course>?> getCoursesList() async {
    try {
      final coursesData = await getCourses();
      
      if (coursesData == null || coursesData['result'] != 1) {
        return null;
      }

      List<Course> courses = [];
      List<dynamic> channelList = coursesData['channelList'];

      for (var channel in channelList) {
        if (channel['content']['course'] != null) { // 自己创建的课程
          courses.add(Course.fromCXJson(channel));
        }
      }

      // 过滤已结课的课程
      return courses.where((course) => course.state).toList();
    } catch (e) {
      debugPrint('getCoursesList error: $e');
      return null;
    }
  }

  /// 获取加入课程时间作为参数
  //（其实没必要）
  static Future<String?> getJoinClassTime(String courseId, String classId, String cpi) async {
    try {
      final url = 'https://mooc1-api.chaoxing.com/gas/clazzperson';
      final currentUserId = AccountManager.currentSessionId ?? '';
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
      final currentUserId = AccountManager.currentSessionId ?? '';

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
      // 客户端登录的 Cookie 没有 fid
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

  /// 获取合并处理后的活动列表
  static Future<List<Active>?> getActiveList(String courseId, String classId, String cpi) async {
    try {
      // 自动获取加入课程时间
      final joinClassTime = await getJoinClassTime(courseId, classId, cpi) ?? '';
        
      final results = await Future.wait([
        getTaskActivityList(courseId, classId, cpi, joinClassTime),
        getTaskActivityListWeb(courseId, classId),
      ]);
        
      final taskData = results[0];
      final webTaskData = results[1];
  
      if (taskData == null || webTaskData == null) {
        return null;
      }
  
      List<Active> contentList = [];
      List<dynamic> activeList = taskData['activeList'];
      List<dynamic> webActiveList = webTaskData['data']['activeList'];
  
      // app 和 web 的 api 活动结束时间存在差异 顺序会匹配错误
      Map<String, dynamic> activeMap = {
        for (var activeItem in webActiveList) activeItem['id'].toString(): activeItem
      };
  
      for (var activeData in activeList) {
        Active active = Active.fromJson(activeData);
        String activeId = activeData['id'].toString();
  
        if (activeMap.containsKey(activeId)) {
          var activeItem = activeMap[activeId];
          if (active.status) {
            if (active.description.isEmpty) {
              active.description = activeItem['nameFour'];
            }
          }
  
          if (active.activeType == ActiveType.signIn ||
              active.activeType == ActiveType.signOut) {
            final otherId = activeItem['otherId'];
            if (otherId != null) {
              try {
                active.signType = getSignTypeFromIndex(int.parse(otherId));
              } catch (e) {
                debugPrint('解析 otherId 失败：$otherId, 错误：$e');
              }
            }
          }
        }
        contentList.add(active);
      }
  
      return contentList;
    } catch (e) {
      debugPrint('getActiveList error: $e');
      return null;
    }
  }
}

class RCCourseApi {
  // userId -> [bearerToken, lessonToken]
  static final Map<String, List<String>> _tokens = {};

  static String get _currentSessionId => AccountManager.currentSessionId!;


  /// 获取当前用户的 bearerToken
  static String? getBearerToken() {
    return _tokens[_currentSessionId]?[0];
  }

  static String? getLessonToken() {
    return _tokens[_currentSessionId]?[1];
  }

  static void _setToken(String bearerToken, String lessonToken) {
    _tokens[_currentSessionId] = [bearerToken, lessonToken];
  }

  /// 上传图片到七牛云
  static Future<String?> uploadImageToQiniu(File imageFile) async {
    try {
      final tokenUrl = '/pc/generate_qiniu_token';
      final jsonData = {
        'bucket_name': 'cms-attachment',
        'expired_time': 3600
      };
      final tokenResponse = await ApiService.sendRequest(tokenUrl, method: 'POST', body: jsonData);

      if (tokenResponse.data == null || 
          tokenResponse.data['success'] != true ||
          tokenResponse.data['data'] == null) {
        debugPrint('Failed to get qiniu token');
        return null;
      }
      
      final token = tokenResponse.data['data']['token'];

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final originalFileName = imageFile.path.split('/').last;
      final fileName = '$timestamp$originalFileName';

      final uploadUrl = 'https://upload.qiniup.com/';
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
        'token': token,
        'key': fileName,
        'fname': originalFileName
      });
      final uploadResponse = await ApiService.sendRequest(uploadUrl, method: 'POST', body: formData);

      if (uploadResponse.data == null || 
          uploadResponse.data['success'] != true) {
        debugPrint('Failed to upload to qiniu');
        return null;
      }

      final key = uploadResponse.data['key'];
      final imageUrl = 'https://qn-scd1.yuketang.cn/$key';
      return imageUrl;
    } catch (e) {
      debugPrint('uploadImageToQiniu error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getCourses() async {
    try {
      final response = await ApiService.sendRequest(
        '/v/course_meta/learning_list/',
      );
      return response.data;
    } catch (e) {
      debugPrint('getCourses error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getOnLessonAndUpcomingExam() async {
    try {
      final response = await ApiService.sendRequest(
        '/api/v3/classroom/on-lesson-upcoming-exam',
      );
      return response.data;
    } catch (e) {
      debugPrint('getOnLessonAndUpcomingExam error: $e');
    }
    return null;
  }

  /// 获取处理后的课程列表
  static Future<List<Course>?> getCoursesList() async {
    try {
      final results = await Future.wait([
        getCourses(),
        getOnLessonAndUpcomingExam()
      ]);

      final courses = results[0];
      final onLessonCourses = results[1];

      if (courses == null || onLessonCourses == null) {
        return null;
      }

      Map<String, dynamic> coursesMap = {
        for (var courseItem in courses['data']) courseItem['course_id'].toString(): courseItem
      };
      debugPrint('coursesMap: $coursesMap');

      List<Course> contentList = [];

      final school = AccountManager.getAccountById(AccountManager.currentSessionId!)!.school;

      for (var onLessonCourseItem in onLessonCourses['data']['onLessonClassrooms']){
        final String courseId = onLessonCourseItem['courseId'];
        if (coursesMap.containsKey(courseId)) {
          var courseItem = coursesMap[courseId];
          courseItem['lesson_id'] = onLessonCourseItem['lessonId'];
          final courseObject = Course.fromRCJson(courseItem);
          courseObject.schools = school;
          contentList.add(courseObject);
        }
      }

      return contentList;
    } catch (e) {
      debugPrint('getCoursesList error: $e');
      return null;
    }
  }

  static Future<int?> checkIn(String lessonId) async {
    try {
      final url = '/api/v3/lesson/checkin';
      final jsonData = {
        'source': 21, // 21: 扫码跳转 23: 点击课堂
        'lessonId': lessonId,
        'joinIfNotIn': true
      };
      final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData);
      final data = response.data;

      final int code = data['code'];
      if (code == 0) {
        // 为当前用户保存 bearerToken（从响应头获取）
        final bearerToken = response.headers.value('set-auth')!;
        final lessonToken = data['data']['lessonToken'];
        _setToken(bearerToken, lessonToken);
        return 0;
      } else {
        // {"code":50070,"msg":"DYNAMIC_QR_CHECK_IN_REFUSED","data":null}
        return code;
      }
    } catch (e) {
      debugPrint('checkIn error: $e');
    }
    return null;
  }

  static Future<int?> scan(String qrCodeUrl) async {
    try {
      final url = '/api/v3/app/scan';
      final jsonData = {'url': qrCodeUrl};
      final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData);
      final data = response.data;

      final int code = data['code'];
      if (code == 0) {
        // {"code":0,"msg":"OK","data":{"type":"checkin","value":"1632189922935066880"}}
        final lessonId = data['data']['value'];
        final response = await checkIn(lessonId);
        return response;
      } else {
        // {"code":51203,"msg":"动态二维码过期","data":{"type":"default","value":""}}
        return code;
      }
    } catch (e) {
      debugPrint('scan error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getPresentation(String presentationId) async {
    try {
      final url = '/api/v3/lesson/presentation/fetch?presentation_id=$presentationId';
      final bearerToken = getBearerToken();
      if (bearerToken == null) {
        debugPrint('bearerToken 为空');
        return null;
      }
      final headers = {'authorization': 'Bearer $bearerToken'};
      final response = await ApiService.sendRequest(url, headers: headers);
      return response.data['data'];
    } catch (e) {
      debugPrint('getPresentation error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> answer(String problemId, int problemType,
      {List<String>? options, String? content, List<String>? imageUrls}) async {
    try {
      final url = '/api/v3/lesson/problem/answer';
      final bearerToken = getBearerToken();
      if (bearerToken == null) {
        debugPrint('bearerToken 为空');
        return null;
      }
      final headers = {'authorization': 'Bearer $bearerToken'};
      final timestampMS = DateTime.now().millisecondsSinceEpoch;
      late dynamic result;
      if (problemType == 5) { // 主观题
        var pics = [];
        if (imageUrls != null) {
          for (var imageUrl in imageUrls) {
            pics.add({
              'pic': imageUrl, // https://qn-v.yuketang.cn/tmp_.jpg
              'thumb': '$imageUrl?imageView2/2/w/568'
            });
          }
        } else {
          pics = [{
            'pic': '', // https://qn-v.yuketang.cn/tmp_.jpg
            'thumb': ''
          }];
        }
        result = {
          'content': content ?? '',
          'pics': pics,
          'videos': [] // 雨课堂对视频的支持不好 不做处理了
        };
      } else {
        result = options;
      }
      final jsonData = {
        'problemId': problemId,
        'dt': timestampMS,
        'problemType': problemType,
        'result': result
      };
      final response = await ApiService.sendRequest(url, method: 'POST', headers: headers, body: jsonData);
      return response.data;
    } catch (e) {
      debugPrint('answer error: $e');
    }
    return null;
  }
}