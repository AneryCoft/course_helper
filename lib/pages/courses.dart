import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';

import '../api/course.dart';
import '../api/api_service.dart';
import '../api/sign_in.dart';
import '../session/account.dart';
import '../models/course.dart';
import '../models/active.dart';
import 'widget/scan.dart';
import 'actives/sign_in/sign_in.dart';
import 'actives/topic_discuss.dart';
import 'actives/quiz.dart';
import 'accounts.dart';


class CourseContentPage extends StatefulWidget {
  final String courseId;
  final String courseName;
  final String classId;
  final String cpi;

  const CourseContentPage({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.classId,
    required this.cpi,
  });

  @override
  State<CourseContentPage> createState() => _CourseContentPageState();
}

class _CourseContentPageState extends State<CourseContentPage> {
  List<Active> _activeList = [];
  bool _isContentLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCourseContent();
  }

  Future<void> _loadCourseContent() async {
    setState(() {
      _isContentLoading = true;
    });

    try {
      final String joinClassTime = (await CourseApi.getJoinClassTime(
        widget.courseId,
        widget.classId,
        widget.cpi,
      )) ??
          '';
      final Map<String, dynamic>? taskData =
      await CourseApi.getTaskActivityList(
        widget.courseId,
        widget.classId,
        widget.cpi,
        joinClassTime,
      );
      final Map<String, dynamic>? pcTaskData =
      await CourseApi.getTaskActivityListWeb(
        widget.courseId,
        widget.classId,
      );

      if (taskData != null && pcTaskData != null) {
        List<Active> contentList = [];
        List<dynamic> activeList = taskData['activeList'];
        List<dynamic> pcActiveList = pcTaskData['data']['activeList'];

        // app和web的api活动结束时间存在差异 顺序会匹配错误
        Map<String, dynamic> pcMap = {
          for (var pcItem in pcActiveList) pcItem['id'].toString(): pcItem
        };

        for (var activeData in activeList) {
          Active active = Active.fromJson(activeData);
          String activeId = activeData['id'].toString();

          if (pcMap.containsKey(activeId)) {
            var pcItem = pcMap[activeId];
            if (active.status){
              if (active.description.isEmpty){
                active.description = pcItem['nameFour'];
              }
            }

            if (active.activeType == ActiveType.signIn ||
                active.activeType == ActiveType.signOut) {
              final otherId = pcItem['otherId'];
              if (otherId != null) {
                try {
                  active.signType = getSignTypeFromIndex(int.parse(otherId));
                } catch (e) {
                  debugPrint('解析 otherId 失败: $otherId, 错误: $e');
                }
              }
            }
          }
          contentList.add(active);
        }

        setState(() {
          _activeList = contentList;
          _isContentLoading = false;
        });
      } else {
        setState(() {
          _activeList = [];
          _isContentLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取内容列表失败')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _activeList = [];
        _isContentLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取内容列表时发生错误: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isContentLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeList.isEmpty
          ? const Center(
        child: Text(
          '暂无内容',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadCourseContent,
        child: ListView.builder(
          itemCount: _activeList.length,
          itemBuilder: (context, index) {
            var active = _activeList[index];
            return Card(
              margin: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    active.getIcon(),
                    color: active.status
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    size: 35,
                  ),
                ),
                title: Text(
                  active.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  active.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (active.status) {
                    if (active.activeType == ActiveType.signIn ||
                        active.activeType == ActiveType.signOut ||
                        active.activeType ==
                            ActiveType.scheduledSignIn) {
                      // 跳转到签到页面
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SignInPage(
                            active: active,
                            courseId: widget.courseId,
                            classId: widget.classId,
                            cpi: widget.cpi,
                          ),
                        ),
                      );
                    } else if (active.activeType ==
                        ActiveType.topicDiscuss) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              TopicDiscussPage(active: active),
                        ),
                      );
                    } else if (active.activeType == ActiveType.quiz) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              QuizPage(
                                active: active,
                                courseId: widget.courseId,
                                classId: widget.classId,
                              ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                            Text('该活动类型暂不支持')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('该活动已结束')),
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  List<Course> _courses = [];
  bool _isLoading = true;
  StreamSubscription? _accountChangeSubscription;

  void refreshCourses() {
    _loadCourses();
  }

  @override
  void initState() {
    super.initState();
    _loadCourses();

    // 监听账户变更事件
    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((accountId) {
          debugPrint('接收到账户变更通知: $accountId');
          if (mounted) {
            // 账户变更时自动刷新课程数据
            _loadCourses();
          }
        });
  }

  /// 解析课程数据
  static List<Course> parseCourses(Map<String, dynamic>? coursesData) {
    List<Course> courses = [];

    if (coursesData != null && coursesData['result'] == 1) {
      List<dynamic> channelList = coursesData['channelList'];

      for (var channel in channelList) {
        if (channel['content']['course'] != null){ // 自己创建的课程
          courses.add(Course.fromJson(channel));
        }
      }
    }

    return courses;
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
    });

    String? currentUserId = await AccountManager.getCurrentSession();
    if (currentUserId == null || currentUserId.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return; // 没有登录账号时不加载课程
    }

    try {
      List<Course>? coursesData = parseCourses(await CourseApi.getCourses());
      coursesData = coursesData.where((course) => course.state).toList(); // 过滤已结课的课程

      setState(() {
        _courses = coursesData!;
        _isLoading = false;
      });
        } catch (e) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
    }
  }

  void handleScanContent(String result) {
    // 简单判断是否为URL
    if (result.startsWith('http')) {
      try {
        final uri = Uri.parse(result);
        final baseUrl = uri.origin + uri.path;
        final params = uri.queryParameters;

        // 判断是否为签到URL
        if (baseUrl == 'https://mobilelearn.chaoxing.com/widget/sign/e') {
          final activeId = params['id'];
          if (activeId != null) {
            ApiService.sendRequest(result, responseType: ResponseType.plain).then((response) async {
              String? location = response.realUri.toString();

              // 重定向到https://mobilelearn.chaoxing.com/newsign/preSign?
              // courseId=&classId=$classId&activePrimaryId=4000147729438&general=1&sys=1&ls=1&appType=15&uid=$uid&
              // rcode=SIGNIN%3Aaid%3D4000147729438%26source%3D15%26Code%3D4000147729438%26enc%3DE39EE73BB53907CC04850F4C6EE077B6
              final uri = Uri.parse(location);
              final params = uri.queryParameters;

              final activeId = params['activePrimaryId'];
              final decodedRcode = Uri.decodeComponent(params['rcode']!);
              debugPrint('rcode $decodedRcode');
              RegExp encRegex = RegExp(r'enc=([^&\s]+)');
              Match? match = encRegex.firstMatch(decodedRcode);

              if (match != null) {
                final result = await SignInApi.qrCodeSign(
                    '', activeId!, match.group(1)!);
                if (result == 'success') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('签到成功')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('签到失败: $result')),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('未找到enc参数')),
                );
              }
            });
          }
        } else {
          // 其他URL处理
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('扫描到链接'),
                content: SelectableText(result),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('打开链接: $result')),
                      );
                    },
                    child: const Text('打开'),
                  ),
                ],
              );
            },
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL解析失败: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描结果: $result')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScanPage(
                    onScanResult: handleScanContent,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _courses.isEmpty
          ? const Center(
        child: Text(
          '暂无课程数据',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadCourses,
        child: ListView.builder(
          itemCount: _courses.length,
          itemBuilder: (context, index) {
            var course = _courses[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CourseContentPage(
                        courseId: course.courseId,
                        courseName: course.name,
                        classId: course.classId,
                        cpi: course.cpi,
                      ),
                    ),
                  );
                },
                child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (course.image.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  course.image,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  headers: {
                                    'User-Agent': ApiService.userAgent
                                  },
                                  // FIXME 部分图片由 star3/origin/ 重定向到 star4/
                                ),
                              )
                            else
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.school,
                                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                                    size: 25,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    course.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    course.teacher,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),
                        if (course.note != null)
                          Text(
                            course.note!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        if (course.schools != null)
                          Text(
                            course.schools!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        if (course.beginDate != null && course.endDate != null)
                          Text(
                            '开课时间: ${course.beginDate} 至 ${course.endDate}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _accountChangeSubscription?.cancel();
    super.dispose();
  }
}