import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';

import '../../platform.dart';
import '../../api/course.dart';
import '../../api/api_service.dart';
import '../../session/account.dart';
import '../../models/course.dart';
import '../../models/active.dart';
import '../../ui/design_tokens.dart';
import '../../ui/widgets.dart';
import '../../utils/logger.dart';
import '../widget/scan.dart';
import '../widget/avatar.dart';
import '../widget/image_viewer.dart';
import '../actives/sign_in/sign_in.dart';
import '../actives/topic_discuss.dart';
import '../actives/quiz.dart';
import '../actives/evaluate.dart';
import '../actives/vote.dart';
import '../actives/questionnaire.dart';
import '../accounts.dart';
import 'content.dart';
import '../presentation.dart';
import '../push/groups.dart';
import '../../push/easemob.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  CoursesPageState createState() => CoursesPageState();

  static void navigateToActive(BuildContext context, Active active, String courseId, String classId, String cpi) {
    if (!active.status) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该活动已结束')),
      );
      return;
    }

    Widget page;
    switch (active.activeType) {
      case ActiveType.signIn:
      case ActiveType.signOut:
      case ActiveType.scheduledSignIn:
        page = SignInPage(active: active, courseId: courseId, classId: classId, cpi: cpi);
        break;
      case ActiveType.topicDiscuss:
        page = TopicDiscussPage(active: active);
        break;
      case ActiveType.quiz:
        page = QuizPage(active: active, courseId: courseId, classId: classId);
        break;
      case ActiveType.evaluation:
        page = EvaluatePage(active: active, courseId: courseId, classId: classId);
        break;
      case ActiveType.vote:
        page = VotePage(active: active, courseId: courseId, classId: classId);
        break;
      case ActiveType.questionnaire:
        page = QuestionnairePage(active: active, courseId: courseId, classId: classId);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该活动类型暂不支持')),
        );
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

/// 课程页的全局 Key，类型化后可安全访问 [CoursesPageState] 的公开方法。
final GlobalKey<CoursesPageState> coursesPageKey = GlobalKey<CoursesPageState>();

class CoursesPageState extends State<CoursesPage> with WidgetsBindingObserver {
  /// 正在上课的课程（按是否有未读消息排序）
  List<Course> _courses = [];

  /// 全部课程（不限于正在上课）
  List<Course> _allCourses = [];

  bool _isLoading = true;
  bool _isLoadingAll = false;
  String? _allCoursesError;

  /// 当前页：0 = 正在上课，1 = 全部课程
  final PageController _pageController = PageController();
  int _currentPage = 0;

  StreamSubscription? _accountChangeSubscription;
  StreamSubscription? _messageStoreSubscription;
  Timer? _refreshTimer;
  List<dynamic> _lastOnLessonCourses = [];
  bool _isVisible = false;

  void refreshCourses() {
    _loadCourses();
    _loadAllCourses();
  }

  void onVisibilityChanged(bool visible) {
    _isVisible = visible;
    if (visible) {
      _startPeriodicRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void updateWithOnLessonCourses(List<Map<String, dynamic>>? onLessonCourses) {
    _loadCourses(onLessonCourses);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isVisible = true;
    _loadCourses();

    _messageStoreSubscription = ActivityMessageStore().changes.listen((_) {
      if (mounted) setState(() {});
    });

    _accountChangeSubscription = AccountChangeNotifier().accountChanges.listen((_) {
      ActivityMessageStore().clearAll();
      if (mounted) {
        _lastOnLessonCourses = [];
        _loadCourses();
      }
      _startPeriodicRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _refreshTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _startPeriodicRefresh();
    }
  }

  void _startPeriodicRefresh() {
    if (!_isVisible || PlatformManager().isChaoxing) return;
    if (_refreshTimer != null && _refreshTimer!.isActive) return;

    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !AccountManager.hasActiveSession()) return;
      try {
        final onLessonCourses = await RCCourseApi.getOnLesson();
        if (onLessonCourses != null && mounted) {
          if (!const DeepCollectionEquality().equals(_lastOnLessonCourses, onLessonCourses)) {
            _lastOnLessonCourses = onLessonCourses;
            _loadCourses(onLessonCourses);
          }
        }
      } catch (e) {
        logger.e('Periodic refresh error: $e');
      }
    });
  }

  Future<void> _loadCourses([List<dynamic>? onLessonCourses]) async {
    setState(() => _isLoading = true);

    if (!AccountManager.hasActiveSession()) {
      setState(() {
        _courses = [];
        _allCourses = [];
        _isLoading = false;
      });
      return;
    }

    try {
      List<Course>? coursesData;
      if (PlatformManager().isChaoxing) {
        coursesData = await CXCourseApi.getCoursesList();
      } else if (PlatformManager().isRainClassroom) {
        coursesData = await RCCourseApi.getCoursesList(onLessonCourses);
      }
      setState(() {
        _courses = coursesData ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
    }
  }

  /// 加载全部课程（学习通与雨课堂都支持）
  Future<void> _loadAllCourses() async {
    if (!AccountManager.hasActiveSession()) {
      setState(() {
        _allCourses = [];
        _allCoursesError = null;
      });
      return;
    }

    setState(() {
      _isLoadingAll = true;
      _allCoursesError = null;
    });

    try {
      List<Course>? all;
      if (PlatformManager().isRainClassroom) {
        all = await RCCourseApi.getAllCoursesList();
      } else {
        all = await CXCourseApi.getCoursesList();
      }
      if (!mounted) return;
      setState(() {
        _allCourses = all ?? [];
        _isLoadingAll = false;
      });
    } catch (e) {
      logger.e('加载全部课程失败: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingAll = false;
        _allCoursesError = '$e';
      });
    }
  }

  Future<void> handleScanContent(String result) async {
    if (!AccountManager.hasActiveSession()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showRawResult('二维码内容', result);
      });
      return;
    }

    if (!result.startsWith('http')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描结果：$result')),
      );
      return;
    }

    try {
      final uri = Uri.parse(result);
      final baseUrl = uri.origin + uri.path;
      final params = uri.queryParameters;

      if (baseUrl == 'https://mobilelearn.chaoxing.com/widget/sign/e') {
        if (!PlatformManager().isChaoxing) {
          await PlatformManager().setPlatform(PlatformType.chaoxing);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('自动切换平台为学习通')),
          );
        }
        if (!AccountManager.hasActiveSession()) {
          if (!mounted) return;
          _showRawResult('提示', '没有可用账号');
          return;
        }

        final activeId = params['id'];
        if (activeId == null) return;

        final response = await ApiService.sendRequest(
          result,
          responseType: ResponseType.plain,
          allowRedirects: false,
        );
        if (response == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请求失败')),
          );
          return;
        }

        final locationUrl = response.headers['location']?.first;
        if (locationUrl == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未获取到签到跳转地址')),
          );
          return;
        }

        final locationUri = Uri.parse(locationUrl);
        final locationParams = locationUri.queryParameters;
        final classId = locationParams['classId'] ?? '';
        final decodedRcode = Uri.decodeComponent(locationParams['rcode'] ?? '');
        final match = RegExp(r'enc=([^&\s]+)').firstMatch(decodedRcode);

        if (match == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到 enc 参数')),
          );
          return;
        }

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SignInPage(
              active: Active(
                type: 2,
                id: activeId,
                name: '二维码签到',
                description: '',
                startTime: 0,
                url: '',
                attendNum: 0,
                status: true,
                signType: SignType.qrCode,
              ),
              courseId: '',
              classId: classId,
              cpi: '',
              enc: match.group(1),
            ),
          ),
        );
      } else if (baseUrl.contains('.yuketang.cn/api/v3/lesson/check-in/dynamic-qr-code')) {
        if (!PlatformManager().isRainClassroom) {
          await PlatformManager().setPlatform(PlatformType.rainClassroom);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('自动切换平台为雨课堂')),
          );
        }
        if (!AccountManager.hasActiveSession()) {
          if (!mounted) return;
          _showRawResult('提示', '没有可用账号');
          return;
        }
        await _multiScan(result);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showRawResult('扫描到链接', result);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('URL 解析失败：$e')),
      );
    }
  }

  void _showRawResult(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(content)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _multiScan(String qrCodeUrl) async {
    final allAccounts = AccountManager.allAccounts;
    if (allAccounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的账号进行签到')),
      );
      return;
    }

    setState(() => _isLoading = true);

    var successCount = 0;
    final failedAccounts = <String>[];

    final results = await ApiService.sendForEachUser(
      allAccounts,
      (user) async => await RCCourseApi(user).scan(qrCodeUrl),
    );

    for (var i = 0; i < results.length; i++) {
      final status = results[i];
      final user = allAccounts[i];
      if (status == 0) {
        successCount++;
      } else if (status == 51203) {
        failedAccounts.add('${user.name} (动态二维码过期)');
      } else {
        failedAccounts.add('${user.name} (错误码：$status)');
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    _showMultiScanResult(successCount, allAccounts.length, failedAccounts);
  }

  void _showMultiScanResult(int successCount, int totalCount, List<String> failedAccounts) {
    final ok = successCount == totalCount;
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(
            ok ? Icons.task_alt_rounded : Icons.report_problem_outlined,
            color: ok ? cs.primary : cs.error,
            size: 32,
          ),
          title: Text(ok ? '全部签到成功' : '部分签到失败'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('成功 $successCount / $totalCount'),
                if (failedAccounts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  ...failedAccounts.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $e'),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  List<Course> _sortedCourses() {
    final unread = _courses
        .where((c) => ActivityMessageStore().countOf(c.courseId, c.classId) > 0)
        .toList();
    final rest = _courses
        .where((c) => ActivityMessageStore().countOf(c.courseId, c.classId) == 0)
        .toList();
    return [...unread, ...rest];
  }

  int get _totalUnread => _courses.fold<int>(
        0,
        (sum, c) => sum + ActivityMessageStore().countOf(c.courseId, c.classId),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      floatingActionButton: PlatformManager().isChaoxing
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupsPage()),
                );
              },
              tooltip: '群聊',
              elevation: 2,
              child: const Icon(Icons.forum_outlined),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶部标题 + 分段切换
            SliverPageHeaderProxy(
              title: '课程',
              subtitle: _currentPage == 0
                  ? (_isLoading
                      ? '正在同步…'
                      : _courses.isEmpty
                          ? '暂无正在上课的课程'
                          : '${_courses.length} 门正在上课'
                              '${_totalUnread > 0 ? ' · $_totalUnread 条新消息' : ''}')
                  : (_isLoadingAll
                      ? '正在加载…'
                      : '共 ${_allCourses.length} 门课程'),
              actions: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScanPage(onScanResult: handleScanContent),
                      ),
                    );
                  },
                  tooltip: '扫码',
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
                IconButton(
                  onPressed: refreshCourses,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),

            // 分段切换
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.sm,
              ),
              child: _SegmentSwitcher(
                current: _currentPage,
                labels: const ['正在上课', '全部课程'],
                counts: [_courses.length, _allCourses.length],
                onChanged: (index) {
                  _pageController.animateToPage(
                    index,
                    duration: AppDuration.normal,
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),

            // 双页滑动
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  if (index == 1 && _allCourses.isEmpty && !_isLoadingAll) {
                    _loadAllCourses();
                  }
                },
                children: [
                  _buildOnLessonPage(context),
                  _buildAllCoursesPage(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 第一页：正在上课
  Widget _buildOnLessonPage(BuildContext context) {
    final courses = _sortedCourses();

    return RefreshIndicator(
      onRefresh: _loadCourses,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_isLoading && _courses.isEmpty)
            const SliverToBoxAdapter(child: ListSkeleton(count: 4))
          else if (courses.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.school_outlined,
                title: PlatformManager().isRainClassroom
                    ? '暂无正在上课的课程'
                    : '还没有课程',
                description: PlatformManager().isRainClassroom
                    ? '老师开始上课后，课程会自动出现在这里\n向右滑动可查看全部课程'
                    : '请先添加并登录账号，课程会自动同步',
                actionLabel: AccountManager.hasActiveSession()
                    ? '刷新试试'
                    : '添加账号',
                onAction: AccountManager.hasActiveSession()
                    ? _loadCourses
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccountsPage(),
                          ),
                        ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.bottomInset,
              ),
              sliver: SliverList.builder(
                itemCount: courses.length,
                itemBuilder: (context, index) {
                  final course = courses[index];
                  return CourseCard(
                    course: course,
                    unread: ActivityMessageStore()
                        .countOf(course.courseId, course.classId),
                    index: index,
                    onTap: () => _openCourse(course),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 第二页：全部课程
  Widget _buildAllCoursesPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoadingAll && _allCourses.isEmpty) {
      return const ListSkeleton(count: 6);
    }

    if (_allCoursesError != null && _allCourses.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: '加载失败',
        description: _allCoursesError,
        actionLabel: '重试',
        onAction: _loadAllCourses,
      );
    }

    if (_allCourses.isEmpty) {
      return EmptyState(
        icon: Icons.library_books_outlined,
        title: '暂无课程',
        description: '当前账号还没有加入任何课程',
        actionLabel: '刷新试试',
        onAction: _loadAllCourses,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllCourses,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          top: AppSpacing.xs,
          bottom: AppSpacing.bottomInset,
        ),
        itemCount: _allCourses.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page + AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.page,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    '全部课程',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  MetaChip(
                    label: '${_allCourses.length}',
                    color: cs.primary,
                  ),
                  const Spacer(),
                  if (_allCourses.any((c) => c.isTeacher))
                    MetaChip(
                      label: '含任教课程',
                      icon: Icons.badge_outlined,
                      color: cs.tertiary,
                    ),
                ],
              ),
            );
          }

          final course = _allCourses[index - 1];
          final isOnLesson = course.lessonId != null;
          return AllCourseCard(
            course: course,
            isOnLesson: isOnLesson,
            onTap: () => _openAllCourse(course),
          );
        },
      ),
    );
  }

  /// 从「全部课程」打开课程
  void _openAllCourse(Course course) {
    if (course.lessonId != null && PlatformManager().isRainClassroom) {
      // 正在上课，直接进入课堂
      _openCourse(course);
      return;
    }

    if (PlatformManager().isChaoxing) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CourseContentPage(
            courseId: course.courseId,
            courseName: course.name,
            classId: course.classId,
            cpi: course.cpi ?? '',
          ),
        ),
      );
      return;
    }

    // 雨课堂非上课状态：提示暂无课堂
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        course.name,
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                if (course.classroomName != null)
                  Text(
                    course.classroomName!,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text(
                      course.teacher,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    if (course.isTeacher)
                      MetaChip(label: '任教', color: cs.tertiary)
                    else
                      MetaChip(label: '学生', color: cs.outline),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: cs.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '该课程当前没有进行中的课堂。\n老师开始上课后可在此进入。',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openCourse(Course course) {
    ActivityMessageStore().clear(course.courseId, course.classId);
    Navigator.push(
      context,
      PlatformManager().isChaoxing
          ? MaterialPageRoute(
              builder: (_) => CourseContentPage(
                courseId: course.courseId,
                courseName: course.name,
                classId: course.classId,
                cpi: course.cpi!,
              ),
            )
          : MaterialPageRoute(
              builder: (_) => PresentationPage(
                lessonId: course.lessonId!,
                title: course.name,
              ),
            ),
    );
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountChangeSubscription?.cancel();
    _messageStoreSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}

/// 课程卡片：左侧色块头像 + 标题 + 元信息 + 未读徽标。
class CourseCard extends StatelessWidget {
  final Course course;
  final int unread;
  final int index;
  final VoidCallback onTap;

  const CourseCard({
    super.key,
    required this.course,
    required this.unread,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = accentFromSeed(cs, course.name);
    final hasUnread = unread > 0;

    Widget leading = _CourseAvatar(course: course, accent: accent);
    if (hasUnread) {
      leading = Badge(
        label: Text('$unread'),
        largeSize: 18,
        offset: const Offset(-2, -2),
        child: leading,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm - 2,
      ),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDuration.normal,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: hasUnread
                  ? Border.all(color: accent.withValues(alpha: 0.35), width: 1.2)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leading,
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: tt.titleMedium?.copyWith(fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              course.teacher.isEmpty ? '未知教师' : course.teacher,
                              style: tt.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_metaChips(context).isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _metaChips(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _metaChips(BuildContext context) {
    final chips = <Widget>[];
    if (course.schools != null && course.schools!.isNotEmpty) {
      chips.add(MetaChip(label: course.schools!, icon: Icons.apartment_rounded));
    }
    if (course.note != null && course.note!.isNotEmpty) {
      chips.add(MetaChip(label: course.note!, icon: Icons.info_outline_rounded));
    }
    if (course.beginDate != null && course.endDate != null) {
      chips.add(MetaChip(
        label: '${course.beginDate} ~ ${course.endDate}',
        icon: Icons.event_outlined,
      ));
    }
    return chips;
  }
}

class _CourseAvatar extends StatelessWidget {
  final Course course;
  final Color accent;

  const _CourseAvatar({required this.course, required this.accent});

  @override
  Widget build(BuildContext context) {
    const size = 52.0;

    if (course.image.isNotEmpty) {
      return GestureDetector(
        onTap: () => showImageViewer(
          context,
          imageUrl: course.image,
          title: course.teacher,
        ),
        child: AvatarWidget(
          imageUrl: course.image,
          size: size,
          borderRadius: AppRadius.md,
          iconSize: 26,
        ),
      );
    }

    // 无图片时用课程名首字 + 渐变底
    final initial = course.name.trim().isEmpty
        ? '课'
        : course.name.trim().characters.first;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppGradients.tint(accent),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 顶部分段切换器
class _SegmentSwitcher extends StatelessWidget {
  final int current;
  final List<String> labels;
  final List<int> counts;
  final ValueChanged<int> onChanged;

  const _SegmentSwitcher({
    required this.current,
    required this.labels,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppDuration.fast,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: current == i ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: current == i
                        ? [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: current == i
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      if (counts[i] > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: current == i
                                ? cs.primary
                                : cs.outlineVariant,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${counts[i]}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: current == i
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 「全部课程」列表项
class AllCourseCard extends StatelessWidget {
  final Course course;
  final bool isOnLesson;
  final VoidCallback onTap;

  const AllCourseCard({
    super.key,
    required this.course,
    required this.isOnLesson,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentFromSeed(cs, course.name);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm - 3,
      ),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 头像
                AvatarWidget(
                  imageUrl: course.image,
                  size: 44,
                  borderRadius: AppRadius.sm,
                  iconSize: 22,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              course.name,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOnLesson) ...[
                            const SizedBox(width: 6),
                            MetaChip(
                              label: '上课中',
                              icon: Icons.play_arrow_rounded,
                              color: cs.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              course.teacher,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (course.isTeacher) ...[
                            const SizedBox(width: 6),
                            MetaChip(label: '任教', color: accent),
                          ],
                        ],
                      ),
                      if (course.classroomName != null &&
                          course.classroomName!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          course.classroomName!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: cs.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: cs.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
