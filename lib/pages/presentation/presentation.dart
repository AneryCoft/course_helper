import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket, File;

import '../../api/course.dart';
import '../../api/image.dart';
import '../../api/api_service.dart';
import '../../models/presentation.dart';
import '../../session/account.dart';
import '../../platform.dart';
import '../../push/notification.dart';
import '../../utils/logger.dart';
import '../../utils/storage.dart';
import '../../utils/time.dart';
import '../widget/image_thumbnail.dart';

part 'connect.dart';
part 'timeline.dart';
part 'ppt_view.dart';

class PresentationPage extends StatefulWidget {
  final String lessonId;
  final String title;

  const PresentationPage({
    super.key,
    required this.lessonId,
    required this.title,
  });

  @override
  State<PresentationPage> createState() => _PresentationPageState();
}

abstract class _PresentationPageStateBase extends State<PresentationPage> {
  WebSocket? _ws;
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();

  int _currentSlideIndex = 0; // 当前浏览的页码
  int _currentLessonSlideIndex = 0; // 课堂播放的页码
  int _totalCount = 0;
  List<Map<String, dynamic>> _slides = [];
  String? _currentPresentationId;
  String? _currentPresentationTitle;
  final List<String> _unlockedProblemIds = [];

  bool _isLoading = false;
  bool _isInitialized = false;
  final List<TimelineEvent> _timeline = [];

  Problem? _currentProblem;
  String? _timelineProblemId; // 从timeline点击的题目
  List<String>? _answer;
  String? _textAnswer;
  bool _isProblemExpanded = true;

  // 图片选择相关
  final List<XFile> _selectedImages = [];
  static const int _maxImageCount = 9;
  final List<String> _uploadedImageUrls = []; // 已上传的图片 URL

  // 倒计时相关
  int? _countdownSeconds;
  Timer? _countdownTimer;

  // 全屏状态
  bool _isFullScreen = false;

  // 下载进度
  bool _isDownloading = false;
  int _downloadedCount = 0;
  int _downloadTotal = 0;

  void _toSlide(int slideIndex, {bool animate = true}) {
    final targetIndex = slideIndex - 1;
    if (targetIndex < 0) return;

    setState(() {
      _currentLessonSlideIndex = targetIndex;
      _currentSlideIndex = targetIndex;
      if (targetIndex < _slides.length) {
        _currentProblem = _slides[targetIndex]['problem'];
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      if (animate) {
        _pageController.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut
        );
      } else {
        _pageController.jumpToPage(targetIndex);
      }
    });
  }

  Future<void> _loadPresentation(String presentationId) async {
    if (_isLoading || presentationId == _currentPresentationId) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final pptData = await RCCourseApi().getPresentation(presentationId);
      if (pptData != null) {
        final presentation = Presentation.fromJson(pptData);
        setState(() {
          _slides = presentation.slides
              .map((slide) => {
                    'index': slide.index,
                    'cover': slide.cover,
                    'coverAlt': slide.coverAlt,
                    'thumbnail': slide.thumbnail,
                    'problem': slide.problem,
                  })
              .toList();
          _totalCount = presentation.slides.length;
          _currentPresentationId = presentationId;
          _currentPresentationTitle = presentation.title;
          if (_slides.isNotEmpty && _currentSlideIndex >= 0 && _currentSlideIndex < _slides.length) {
            _currentProblem = presentation.slides[_currentSlideIndex].problem;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('加载 PPT 失败：$e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdownSeconds != null && _countdownSeconds! > 0) {
          _countdownSeconds = _countdownSeconds! - 1;
        } else {
          timer.cancel();
        }
      });
    });
  }

  void _addTimelineEvents(List timeline) {
    for (var event in timeline) {
      final type = event['type'];
      final code = event['code'];
      final title = event['title'];
      final dt = event['dt'];
      final si = event['si'];
      final total = event['total'];
      final limit = event['limit'];
      final prob = event['prob'];
      final pres = event['pres'];

      if (type != null) {
        String eventType = type;
        String eventTitle = title ?? '';

        if (type == 'event' && code != null) {
          if (code == 'RANDOM_PICK') {
            eventType = 'randompick';
            eventTitle = title ?? '随机点名';
          }
        }

        if (eventType == 'slide') {
          continue;
        }

        setState(() {
          _timeline.add(TimelineEvent(
            type: eventType,
            code: code,
            title: eventTitle,
            slideIndex: si,
            total: total,
            limit: limit,
            timestamp: DateTime.fromMillisecondsSinceEpoch(dt),
            problemId: prob,
            presentationId: pres,
            problemDt: dt
          ));

          if (eventType == 'problem' && prob != null && !_unlockedProblemIds.contains(prob)) {
            _unlockedProblemIds.add(prob);
          }
        });
      }
    }

    _scrollTimelineToBottom();
  }

  /// 时间线滚动到底部
  void _scrollTimelineToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _getProblemTypeLabel(int type) {
    return ProblemType.fromId(type).label;
  }
}

class _PresentationPageState extends _PresentationPageStateBase
    with _ConnectMixin, _TimelineMixin, _PptViewMixin {
  @override
  void initState() {
    super.initState();
    _initialize();
    _startForegroundService();
  }

  @override
  void dispose() {
    // 发送离开课堂消息
    if (_ws != null) {
      final leaveData = {
        "op": "leavelesson",
        "lessonid": widget.lessonId
      };
      _ws?.add(jsonEncode(leaveData));
    }

    _countdownTimer?.cancel();
    _ws?.close();
    _pageController.dispose();
    _scrollController.dispose();
    _stopForegroundService();

    // 恢复方向与系统栏
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  Future<void> _initialize() async {
    await _checkToken();
    _connectWebSocket();
  }

  Future<void> _checkToken() async {
    final lessonToken = RCCourseApi().lessonToken;
    if (lessonToken == null) {
      final allAccounts = AccountManager.allAccounts;

      final results = await ApiService.sendForEachUser(
        allAccounts,
        (user) async {
          final api = RCCourseApi(user);
          return await api.checkIn(widget.lessonId);
        },
      );

      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        final user = allAccounts[i];

        if (result != 0) {
          if (result == 50070){
            // 该课堂已开启动态二维码签到，请扫码签到进班
            if (mounted) {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    content: const Text('请先扫描动态二维码'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('确定')
                      ),
                    ]
                  );
                },
              );
            }
            return;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Uid${user.uid}签到错误：$result'))
              );
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullScreen) {
          _toggleFullScreen();
        }
      },
      child: Scaffold(
        appBar: _isFullScreen ? null : AppBar(
        title: Text(widget.title),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    '加载 PPT 中...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : !_isInitialized
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        '等待课堂数据...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _isFullScreen
                  ? ColoredBox(
                      color: Colors.black,
                      child: _buildFullScreenPPT(),
                    )
                  : Column(
                  children: [
                    _buildSlideViewer(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            if (_currentProblem != null)
                              _buildProblemPanel(),
                            _buildTimelineList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
