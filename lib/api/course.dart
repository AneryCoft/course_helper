import 'package:flutter/foundation.dart';

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
  static Future<List<Course>?> getCoursesList([Map<String, dynamic>? onLessonCourses]) async {
    try {
      late Map<String, dynamic>? courses;
      if (onLessonCourses == null) {
        final results = await Future.wait([
          getCourses(),
          getOnLessonAndUpcomingExam()
        ]);
        courses = results[0];
        onLessonCourses = results[1];
      } else {
        courses = await getCourses();
      }

      if (courses == null || onLessonCourses == null) {
        return null;
      }
      if (courses['data'].isEmpty || courses['data'].isEmpty) {
        return null;
      }

      Map<String, dynamic> coursesMap = {
        for (var courseItem in courses['data']) courseItem['course_id'].toString(): courseItem
      };

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
    } catch (e, stackTrace) {
      debugPrint('getCoursesList error: $e\n$stackTrace');
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

  /// 提交答案
  /// 在answer提交失败后会反复进行retry
  static Future<Map<String, dynamic>?> answer(String problemId, int problemType,
      {bool retry = false, int? time, List<String>? options, String? content, List<String>? imageUrls}) async {
    try {
      final url = retry ?
      '/api/v3/lesson/problem/retry' : '/api/v3/lesson/problem/answer';
      final bearerToken = getBearerToken();
      if (bearerToken == null) {
        debugPrint('bearerToken 为空');
        return null;
      }
      final headers = {'authorization': 'Bearer $bearerToken'};
      final timestampMS = (time == null) ?
      DateTime.now().millisecondsSinceEpoch : time;
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
      var jsonData = {
        'problemId': problemId,
        'dt': timestampMS,
        'problemType': problemType,
        'result': result
      };
      if (retry) {
        jsonData['retry_times'] = null;
        jsonData = {'problems': [jsonData]};
      }
      final response = await ApiService.sendRequest(url, method: 'POST', headers: headers, body: jsonData);
      return response.data;
    } catch (e) {
      debugPrint('answer error: $e');
    }
    return null;
  }
}