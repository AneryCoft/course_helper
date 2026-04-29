import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';

import '../platform.dart';
import '../api/course.dart';
import '../api/api_service.dart';
import '../api/image.dart';
import '../session/account.dart';
import '../models/course.dart';
import '../models/active.dart';
import '../setting/course_setting.dart';
import 'widget/scan.dart';
import 'widget/avatar.dart';
import 'widget/baidu_map.dart';
import 'actives/sign_in/sign_in.dart';
import 'actives/topic_discuss.dart';
import 'actives/quiz.dart';
import 'actives/evaluate.dart';
import 'actives/vote.dart';
import 'actives/questionnaire.dart';
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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CourseSettingsPage(
                    courseId: widget.courseId
                  ),
                ),
              );
            },
            tooltip: '课程设置'
          ),
        ],
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active.description.isEmpty ?
                      '手动结束' : active.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '参与人数：${active.attendNum}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey
                      )
                    )
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  CoursesPage.navigateToActive(context, active, widget.courseId, widget.classId, widget.cpi);
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

  static void navigateToActive(BuildContext context, Active active, String courseId, String classId, String cpi) {
    if (!active.status) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该活动已结束')),
      );
      return;
    }

    switch (active.activeType) {
      case ActiveType.signIn:
      case ActiveType.signOut:
      case ActiveType.scheduledSignIn:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignInPage(
              active: active,
              courseId: courseId,
              classId: classId,
              cpi: cpi
            ),
          ),
        );
        break;
      
      case ActiveType.topicDiscuss:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TopicDiscussPage(active: active),
          ),
        );
        break;
      
      case ActiveType.quiz:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuizPage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;
      
      case ActiveType.evaluation:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EvaluatePage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;
      
      case ActiveType.vote:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VotePage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;

      case ActiveType.questionnaire:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuestionnairePage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;
      
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该活动类型暂不支持'),
          ),
        );
    }
  }
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
      return;
    }

    try {
      late List<Course>? coursesData;
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
            final response = await ApiService.sendRequest(result, responseType: ResponseType.plain, allowRedirects: false);
            final locationUrl = response.headers['location']?.first;
            // String? location = response.realUri.toString();

            // 重定向到 https://mobilelearn.chaoxing.com/newsign/preSign?
            // courseId=&classId=$classId&activePrimaryId=4000147729438&general=1&sys=1&ls=1&appType=15&uid=$uid&
            // rcode=SIGNIN%3Aaid%3D4000147729438%26source%3D15%26Code%3D4000147729438%26enc%3DE39EE73BB53907CC04850F4C6EE077B6
            final uri = Uri.parse(locationUrl!);
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
                        attendNum: 0,
                        status: true,
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
        } else if (baseUrl.contains('.yuketang.cn/api/v3/lesson/check-in/dynamic-qr-code')){
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
                                      AvatarWidget(
                                        imageUrl: course.image,
                                        size: 50,
                                        borderRadius: 6,
                                        iconSize: 25,
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

class CourseSettingsPage extends StatefulWidget {
  final String courseId;

  const CourseSettingsPage({
    super.key,
    required this.courseId,
  });

  @override
  State<CourseSettingsPage> createState() => _CourseSettingsPageState();
}

class _CourseSettingsPageState extends State<CourseSettingsPage> {
  late TextEditingController _classroomController;
  late TextEditingController _addressController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  List<String> _imageObjectIds = [];
  final Map<String, String> _localImagePaths = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _classroomController = TextEditingController();
    _addressController = TextEditingController();
    _latitudeController = TextEditingController();
    _longitudeController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await CourseSetting.getSettings(widget.courseId);
    if (mounted) {
      setState(() {
        _classroomController.text = settings?.location?.classroom ?? '';
        _addressController.text = settings?.location?.address ?? '';
        _latitudeController.text = settings?.location?.latitude ?? '';
        _longitudeController.text = settings?.location?.longitude ?? '';
        _imageObjectIds = settings?.imageObjectIds ?? [];
      });
    }
  }

  @override
  void dispose() {
    _classroomController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      List<XFile> pickedFiles;
      
      if (source == ImageSource.gallery) {
        pickedFiles = await picker.pickMultiImage();
      } else {
        final pickedFile = await picker.pickImage(source: source);
        if (pickedFile == null) return;
        pickedFiles = [pickedFile];
      }
      
      if (pickedFiles.isEmpty) return;

      final userId = AccountManager.currentSessionId!;
      // 并行上传所有图片
      final uploadFutures = pickedFiles.map((pickedFile) async {
        final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        setState(() {
          _imageObjectIds.add(tempId);
          _localImagePaths[tempId] = pickedFile.path;
        });

        try {
          final objectId = await CXImageApi.uploadImage(File(pickedFile.path), userId);

          if (objectId != null) {
            setState(() {
              final index = _imageObjectIds.indexOf(tempId);
              if (index != -1) {
                _imageObjectIds[index] = objectId;
                _localImagePaths.remove(tempId);
                _localImagePaths[objectId] = pickedFile.path;
              }
            });
            return true;
          } else {
            setState(() {
              _imageObjectIds.remove(tempId);
              _localImagePaths.remove(tempId);
            });
            return false;
          }
        } catch (e) {
          setState(() {
            _imageObjectIds.remove(tempId);
            _localImagePaths.remove(tempId);
          });
          return false;
        }
      }).toList();

      final results = await Future.wait(uploadFutures);
      final successCount = results.where((r) => r).length;
      final failCount = results.length - successCount;

      if (mounted) {
        if (failCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功上传 $successCount 张图片')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传完成：成功 $successCount 张，失败 $failCount 张')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片错误：$e')),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      final objectId = _imageObjectIds[index];
      _imageObjectIds.removeAt(index);
      _localImagePaths.remove(objectId);
    });
  }

  /// 放大图片对话框
  void _showImageDialog(BuildContext context, String objectId, String? localPath) {
    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black12,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: localPath != null
                  ? Image.file(
                      File(localPath),
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      CXImageApi.getImageUrl(objectId),
                      headers: HeadersManager.chaoxingHeaders,
                      fit: BoxFit.contain,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMapPicker() {
    BMFCoordinate? selectedCoordinate;
    String? selectedAddress;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('选择位置'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Expanded(
                child: BaiduMapWidget(
                  showLocationButton: true,
                  showCurrentLocationInfo: true,
                  onLocationSelectedWithAddress: (coordinate, address) {
                    selectedCoordinate = coordinate;
                    selectedAddress = address;
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _latitudeController.text = selectedCoordinate!.latitude.toStringAsFixed(6);
                          _longitudeController.text = selectedCoordinate!.longitude.toStringAsFixed(6);
                          _addressController.text = selectedAddress?.isEmpty ?? true
                              ? '未知位置'
                              : selectedAddress!;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('确认选择'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final latText = _latitudeController.text.trim();
      final lonText = _longitudeController.text.trim();
      final classroomText = _classroomController.text.trim();
      final addressText = _addressController.text.trim();

      CourseLocation? location;
      if (latText.isNotEmpty && lonText.isNotEmpty && 
          classroomText.isNotEmpty && addressText.isNotEmpty) {
        final latitude = double.tryParse(latText);
        final longitude = double.tryParse(lonText);
        if (latitude != null && longitude != null) {
          location = CourseLocation(
            classroom: classroomText,
            address: addressText,
            latitude: latitude.toStringAsFixed(6),
            longitude: longitude.toStringAsFixed(6),
          );
        }
      }

      final settings = CourseSettings(
        location: location,
        imageObjectIds: _imageObjectIds.isEmpty ? null : _imageObjectIds,
      );

      await CourseSetting.saveSettings(widget.courseId, settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程设置'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '位置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _classroomController,
                    decoration: const InputDecoration(
                      labelText: '教室(可选)',
                      hintText: '1教-3211',
                      prefixIcon: Icon(Icons.meeting_room),
                      border: OutlineInputBorder()
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: '地址',
                            hintText: '沧州市黄骅市 河北农业大学(渤海校区)',
                            prefixIcon: Icon(Icons.place),
                            border: OutlineInputBorder()
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        onPressed: _showMapPicker,
                        icon: const Icon(Icons.map),
                        tooltip: '选择位置'
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latitudeController,
                          decoration: const InputDecoration(
                            labelText: '纬度',
                            hintText: '38.387697',
                            prefixIcon: Icon(Icons.north),
                            border: OutlineInputBorder()
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _longitudeController,
                          decoration: const InputDecoration(
                            labelText: '经度',
                            hintText: '117.438972',
                            prefixIcon: Icon(Icons.east),
                            border: OutlineInputBorder()
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '图片',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (_imageObjectIds.isNotEmpty) ...[
                            SizedBox(
                              height: 80,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imageObjectIds.length,
                                itemBuilder: (context, index) {
                                  final objectId = _imageObjectIds[index];
                                  final localPath = _localImagePaths[objectId];
                                  final isUploading = objectId.startsWith('temp_');
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Stack(
                                      children: [
                                        GestureDetector(
                                          onTap: !isUploading ? () {
                                            _showImageDialog(context, objectId, localPath);
                                          } : null,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Stack(
                                              children: [
                                                localPath != null
                                                    ? Image.file(
                                                        File(localPath),
                                                        width: 80,
                                                        height: 80,
                                                        fit: BoxFit.contain,
                                                      )
                                                    : Image.network(
                                                        CXImageApi.getImageUrl(objectId),
                                                        width: 80,
                                                        height: 80,
                                                        fit: BoxFit.contain,
                                                        headers: HeadersManager.chaoxingHeaders,
                                                        loadingBuilder: (context, child, loadingProgress) {
                                                          if (loadingProgress == null) return child;
                                                          return Container(
                                                            width: 80,
                                                            height: 80,
                                                            color: Colors.grey.shade200,
                                                            child: Center(
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                value: loadingProgress.expectedTotalBytes != null
                                                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                                    : null,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        errorBuilder: (context, error, stackTrace) {
                                                          return Container(
                                                            width: 80,
                                                            height: 80,
                                                            color: Colors.grey.shade200,
                                                            child: const Icon(Icons.broken_image, color: Colors.grey),
                                                          );
                                                        },
                                                      ),
                                                if (isUploading)
                                                  Container(
                                                    width: 80,
                                                    height: 80,
                                                    color: Colors.black.withValues(alpha: 0.3),
                                                    child: const Center(
                                                      child: CircularProgressIndicator(
                                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () => _removeImage(index),
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(alpha: 0.8),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _pickAndUploadImage(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('拍照'),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _pickAndUploadImage(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('相册'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text(
                        '保存设置',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}