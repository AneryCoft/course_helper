import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';

import '../platform.dart';
import '../api/course.dart';
import '../api/api_service.dart';
import '../session/account.dart';
import '../models/course.dart';
import '../models/active.dart';
import 'widget/scan.dart';
import 'actives/sign_in/sign_in.dart';
import 'actives/topic_discuss.dart';
import 'actives/quiz.dart';
import 'actives/evaluate.dart';
import 'accounts.dart';
import 'presentation.dart';


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
      final List<Active>? contentList = await CXCourseApi.getActiveList(
        widget.courseId,
        widget.classId,
        widget.cpi,
      );

      if (contentList != null) {
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
          SnackBar(content: Text('获取内容列表时发生错误：$e')),
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
                        active.activeType == ActiveType.scheduledSignIn) {
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
                    } else if (active.activeType == ActiveType.evaluation) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              EvaluatePage(
                                active: active,
                                courseId: widget.courseId,
                                classId: widget.classId,
                              ),
                        ),
                      );
                    }
                    else {
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

final GlobalKey coursesPageKey = GlobalKey();

class _CoursesPageState extends State<CoursesPage> with WidgetsBindingObserver {
  List<Course> _courses = [];
  bool _isLoading = true;
  StreamSubscription? _accountChangeSubscription;
  StreamSubscription? _platformChangeSubscription;
  Timer? _refreshTimer;
  Map<String, dynamic>? _lastOnLessonCourses;
  bool _isVisible = false;

  void refreshCourses() {
    _loadCourses();
  }

  void onVisibilityChanged(bool visible) {
    _isVisible = visible;
    if (visible) {
      _checkAndStartRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  /// 使用在线课堂数据更新课程列表
  void updateWithOnLessonCourses(Map<String, dynamic> onLessonCourses) {
    _loadCourses(onLessonCourses);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isVisible = true;
    _loadCourses();

    // 监听账户变更事件
    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((accountId) {
          if (mounted) {
            _loadCourses();
          }
        });

    // 监听平台变化
    _platformChangeSubscription = PlatformManager().platformChanges.listen((_) {
      if (mounted) {
        _lastOnLessonCourses = null;
        _loadCourses();
      }
      _checkAndStartRefresh();
    });

    _checkAndStartRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndStartRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _checkAndStartRefresh() {
    _refreshTimer?.cancel();
    if (_isVisible && PlatformManager().isRainClassroom) {
      _startPeriodicRefresh();
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !AccountManager.hasActiveSession()) return;

      try {
        final onLessonCourses = await RCCourseApi.getOnLessonAndUpcomingExam();
        if (onLessonCourses != null && mounted) {
          if (_lastOnLessonCourses == null || _lastOnLessonCourses.toString() != onLessonCourses.toString()) {
            _lastOnLessonCourses = onLessonCourses;
            _loadCourses(onLessonCourses);
          }
        }
      } catch (e) {
        debugPrint('Periodic refresh error: $e');
      }
    });
  }

  Future<void> _loadCourses([Map<String, dynamic>? onLessonCourses]) async {
    setState(() {
      _isLoading = true;
    });

    if (!AccountManager.hasActiveSession()) {
      setState(() {
        _isLoading = false;
      });
      return; // 没有登录账号时不加载课程
    }

    try {
      List<Course>? coursesData;
      if (PlatformManager().isChaoxing) {
        coursesData =  await CXCourseApi.getCoursesList();
      } else if (PlatformManager().isRainClassroom) {
        coursesData =  await RCCourseApi.getCoursesList(onLessonCourses);
      }

      if (coursesData != null && coursesData.isNotEmpty) {
        setState(() {
          _courses = coursesData!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _courses =  [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
    }
  }

  Future<void> handleScanContent(String result) async {
    if (!AccountManager.hasActiveSession()){
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('二维码内容'),
              content: SelectableText(result),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      });
      return;
    }
  
    if (result.startsWith('http')) {
      try {
        final uri = Uri.parse(result);
        final baseUrl = uri.origin + uri.path;
        final params = uri.queryParameters;
  
        // 判断是否为签到 URL
        if (baseUrl == 'https://mobilelearn.chaoxing.com/widget/sign/e') {
          if (!PlatformManager().isChaoxing) {
            await PlatformManager().setPlatform(PlatformType.chaoxing);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('自动切换平台为学习通')),
            );
          }
          if (!AccountManager.hasActiveSession()){
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('提示'),
                  content: const Text('没有可用账号'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                );
              },
            );
            return;
          }
  
          final activeId = params['id'];
          if (activeId != null) {
            final response = await ApiService.sendRequest(result, responseType: ResponseType.plain);
            String? location = response.realUri.toString();

            // 重定向到 https://mobilelearn.chaoxing.com/newsign/preSign?
            // courseId=&classId=$classId&activePrimaryId=4000147729438&general=1&sys=1&ls=1&appType=15&uid=$uid&
            // rcode=SIGNIN%3Aaid%3D4000147729438%26source%3D15%26Code%3D4000147729438%26enc%3DE39EE73BB53907CC04850F4C6EE077B6
            final uri = Uri.parse(location);
            final params = uri.queryParameters;

            final classId = params['classId'] ?? '';
            // final activePrimaryId = params['activePrimaryId'] ?? '';
            final decodedRcode = Uri.decodeComponent(params['rcode']!);
            RegExp encRegex = RegExp(r'enc=([^&\s]+)');
            Match? match = encRegex.firstMatch(decodedRcode);

            if (match != null) {
              final enc = match.group(1);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SignInPage(
                    active: Active(
                        type: 2,
                        id: activeId,
                        name: '二维码签到',
                        description: '',
                        startTime: 0,
                        url: '',
                        status: true,
                        extras: {},
                        signType: SignType.qrCode
                    ),
                    courseId: '',
                    classId: classId,
                    cpi: '',
                    enc: enc
                  ),
                ),
              );
            } else {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('未找到 enc 参数')),
              );
            }
          }
        } else if (baseUrl == 'https://www.yuketang.cn/api/v3/lesson/check-in/dynamic-qr-code'){
          if (!PlatformManager().isRainClassroom) {
            await PlatformManager().setPlatform(PlatformType.rainClassroom);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('自动切换平台为雨课堂')),
            );
          }
          if (!AccountManager.hasActiveSession()){
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  content: const Text('没有可用账号'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                );
              },
            );
            return;
          }
  
          // https://www.yuketang.cn/api/v3/lesson/check-in/dynamic-qr-code?
          // c=fL5xO1crTr6AC1Re3BaUEurgVNpZL0zydLypc0f2m2A&t=1772409038563&s=B53F5736FCCAF827&v=2
  
          await _multiScan(context, result);
        } else {
          // 其他 URL 处理
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('扫描到链接'),
                  content: SelectableText(result),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                );
              },
            );
          });
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL 解析失败：$e')),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描结果：$result')),
      );
    }
  }

  /// 为所有用户扫描
  Future<void> _multiScan(BuildContext context, String qrCodeUrl) async {
    final allAccounts = AccountManager.getAllAccounts();
    if (allAccounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的账号进行签到'))
      );
      return;
    }
  
    setState(() {
      _isLoading = true;
    });
  
    int successCount = 0;
    final List<String> failedAccounts = [];
  
    final currentUserId = AccountManager.currentSessionId;
    for (final user in allAccounts) {
      AccountManager.setCurrentSessionTemp(user.uid);
      try {
        // 扫描二维码并签到
        final status = await RCCourseApi.scan(qrCodeUrl);
        if (status == 0) {
          successCount++;
        } else if (status == 51203){
          failedAccounts.add('${user.name} (动态二维码过期)');
        } else {
          failedAccounts.add('${user.name} (错误码：$status)');
        }
      } catch (e) {
        failedAccounts.add('${user.name} (异常：$e)');
      }
    }
    AccountManager.setCurrentSessionTemp(currentUserId!);
  
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  
    _showMultiScanResult(context, successCount, allAccounts.length, failedAccounts);
  }

  /// 显示所有签到结果
  void _showMultiScanResult(BuildContext context, int successCount, int totalCount, List<String> failedAccounts) {
    String message = '签到完成！\n成功: $successCount/$totalCount';
    if (failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == totalCount ? '全部签到成功' : '部分失败',
          style: TextStyle(
            color: successCount == totalCount ? Colors.green : Colors.orange,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
      body: RefreshIndicator(
        onRefresh: _loadCourses,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _courses.isEmpty
            ? const Center(
                child: Text(
                  '暂无课程数据',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: _courses.length,
                itemBuilder: (context, index) {
                  var course = _courses[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          PlatformManager().isChaoxing ?
                          MaterialPageRoute(
                            builder: (context) => CourseContentPage(
                              courseId: course.courseId,
                              courseName: course.name,
                              classId: course.classId,
                              cpi: course.cpi!
                            ),
                          ) : MaterialPageRoute(
                            builder: (context) => PresentationPage(
                              lessonId: course.lessonId!,
                              title: course.name
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
                                          headers: PlatformManager().isChaoxing ? HeadersManager.chaoxingHeaders : null,
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
                                    '开课时间：${course.beginDate} 至 ${course.endDate}',
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
    WidgetsBinding.instance.removeObserver(this);
    _accountChangeSubscription?.cancel();
    _platformChangeSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}