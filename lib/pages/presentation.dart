import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket, File;

import '../api/course.dart';
import '../api/image.dart';
import '../api/api_service.dart';
import '../models/presentation.dart';
import '../session/account.dart';
import '../platform.dart';
import '../utils/logger.dart';
import '../utils/storage.dart';
import '../utils/time.dart';

@pragma('vm:entry-point')
void _startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_WebSocketKeepAliveHandler());
}

class _WebSocketKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

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

class _PresentationPageState extends State<PresentationPage> {
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

  Future<void> _startForegroundService() async {
    // 请求忽略电池优化
    final pref = StorageManager.prefs;
    // 对于各个厂商的定制系统 无法获取到电池优化的状态
    final bool isBatteryOptimizationDisabled = pref.getBool('isBatteryOptimizationDisabled') ?? false;

    if (!isBatteryOptimizationDisabled) {
      bool? isAllDisabled = await DisableBatteryOptimization.isAllBatteryOptimizationDisabled;

      if (isAllDisabled != null && !isAllDisabled) {
        // 引导用户完成手机厂商的设置（自启动和电池优化）
        await DisableBatteryOptimization.showDisableAllOptimizationsSettings(
            "开启自启动",
            "请按步骤开启自启动，否则课程在后台会断开连接",
            "检测到系统有额外的电池优化",
            "请按步骤关闭额外的电池优化，以保证连接稳定"
        );
      } else {
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
      pref.setBool('isBatteryOptimizationDisabled', true);
    }

    // 初始化前台服务
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'websocket_service',
          channelName: 'WebSocket Background Service',
          channelDescription: 'Keep WebSocket connection alive'
      ),
      iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          allowWifiLock: true
      ),
    );

    // 启动前台服务
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: '课堂助手',
        notificationText: '正在保持 WebSocket 连接...',
        callback: _startForegroundCallback,
      );
    }
  }

  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _connectWebSocket() async {
    try {
      late String lessonUrl;
      final currentServerName = PlatformManager().currentServer.name;
      lessonUrl = currentServerName == 'yuketang'?
      'wss://www.yuketang.cn/wsapp/' : 'wss://$currentServerName.yuketang.cn/wsapp/';

      final ws = await WebSocket.connect(lessonUrl);
      _ws = ws;

      final helloData = {
        "op": "hello",
        "userid": AccountManager.currentSessionId,
        "role": "student",
        "auth": RCCourseApi().lessonToken,
        "lessonid": widget.lessonId
      };

      ws.add(jsonEncode(helloData));

      ws.listen(
        (message) {
          _handleMessage(message);
        },
      );
    } catch (e) {
      logger.e('WebSocket 连接失败：$e');
    }
  }

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

  void _handleMessage(dynamic message) async {
    try {
      final data = jsonDecode(message);
      final op = data['op'];

      logger.d('WebSocket S2C：$message');
      
      final messageText = data['message'];

      switch (op) {
        case 'hello':
          if (messageText == 'lesson finished') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('课堂已结束')),
                );
              }
            });
            return;
          }

          final presentationId = data['presentation'];
          final slideIndex = data['slideindex'];
          final timeline = data['timeline'] as List?;

          String? latestPresId;
          int? latestSlideIndex;
          if (timeline != null) {
            for (var event in timeline.reversed) {
              if (event['type'] == 'slide' && event['pres'] != null) {
                latestPresId = event['pres'];
                latestSlideIndex = event['si'];
                break;
              }
            }
          }
          
          final targetPresId = latestPresId ?? presentationId;
          final targetSlideIndex = latestSlideIndex ?? slideIndex;
          
          if (targetPresId != null) {
            await _loadPresentation(targetPresId);
            if (targetSlideIndex != null && targetSlideIndex > 0) {
              _toSlide(targetSlideIndex, animate: false);
            }
          }
          
          if (timeline != null) {
            _addTimelineEvents(timeline);
          }
          
          setState(() {
            _isInitialized = true;
          });
          break;

        case 'unlockproblem':
          final problemData = data['problem'];
          if (problemData != null) {
            // WebSocket 消息中使用 'prob' 或 'sid' 作为题目ID
            final problemId = problemData['prob'];
            final limit = problemData['limit'];
            final dt = problemData['dt'];
            if (limit != null && limit > 0) {
              setState(() {
                _countdownSeconds = limit;
                if (problemId != null && !_unlockedProblemIds.contains(problemId)) {
                  _unlockedProblemIds.add(problemId);
                }
                if (_currentProblem != null && dt != null) {
                  _currentProblem = _currentProblem!.copyWith(dt: dt);
                }
              });
              _startCountdown(limit);
            }
          }
          break;

        case 'showpresentation':
          final presentationId = data['presentation'];
          final slideIndex = data['slideindex'];
          final timeline = data['timeline'] as List?;
          // final shownow = data['shownow'] ?? false;
          
          if (presentationId != null && presentationId != _currentPresentationId) {
            await _loadPresentation(presentationId);
          }
          
          if (slideIndex != null) {
            _toSlide(slideIndex);
          }
          
          if (timeline != null) {
            _addTimelineEvents(timeline);
          }
          break;

        case 'slide':
        case 'slidenav':
          final slideIndex = op == 'slide' ?
          data['slideindex'] : data['slide']?['si'];
          if (slideIndex != null) {
            _toSlide(slideIndex);
          }
          break;

        case 'extendtime':
          // 延时
          final problemData = data['problem'];
          if (problemData != null) {
            final extend = problemData['extend'];
            if (extend != null && extend > 0) {
              setState(() {
                if (_countdownSeconds != null) {
                  _countdownSeconds = (_countdownSeconds! + extend).toInt();
                }
              });
            }
          }
          break;

        case 'callpaused':
          // 随机点名
          final eventData = data['event'];
          if (eventData != null) {
            final code = eventData['code'];
            final dt = eventData['dt'];
            if (code == 'RANDOM_PICK') {
              setState(() {
                _timeline.add(TimelineEvent(
                  type: 'randompick',
                  code: 'RANDOM_PICK',
                  title: eventData['title'],
                  timestamp: DateTime.fromMillisecondsSinceEpoch(dt)
                ));
              });
            }
          }
          break;

        case 'showfinished':
          // 幻灯片结束放映
          final eventData = data['event'];
          if (eventData != null) {
            final code = eventData['code'];
            final title = eventData['title'];
            final dt = eventData['dt'];
            
            if (code == 'SHOW_FINISH') {
              setState(() {
                _timeline.add(TimelineEvent(
                  type: 'event',
                  code: code,
                  title: title,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(dt),
                ));
              });
            }
          }
          break;

        case 'lessonfinished':
          // 下课
          final eventData = data['event'];
          if (eventData != null) {
            final code = eventData['code'];
            final title = eventData['title'];
            final dt = eventData['dt'];
            
            if (code == 'LESSON_FINISH') {
              setState(() {
                _timeline.add(TimelineEvent(
                  type: 'event',
                  code: code,
                  title: title,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(dt)
                ));
              });
            }
          }
          break;

        case 'locationcheckinext':
          // 位置签到开始
          _handleLocationCheckInStart(data);
          break;

        case 'locationcheckinend':
          // 位置签到结束
          _handleLocationCheckInEnd(data);
          break;
      }
    } catch (e) {
      logger.e('解析消息失败：$e');
    }
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

  Future<void> _handleLocationCheckInStart(Map<String, dynamic> data) async {
    /// FIXME 需要根据实际参数进行调整
    final lessonId = widget.lessonId;
    final startMs = data['startMs'] ?? data['serverTime'];
    final timestamp = startMs is int
        ? DateTime.fromMillisecondsSinceEpoch(startMs)
        : DateTime.now();

    final event = TimelineEvent(
      type: 'locationcheckin_start',
      code: null,
      title: '位置签到开始',
      timestamp: timestamp,
      subtitle: '签到中...'
    );
    setState(() {
      _timeline.add(event);
    });
    _scrollTimelineToBottom();

    // 查询所有账号签到状态
    final allAccounts = AccountManager.allAccounts;
    final getResults = await ApiService.sendForEachUser(
      allAccounts,
      (user) async {
        final api = RCCourseApi(user);
        return await api.getCheckIn();
      },
    );

    final getCheckInTexts = <String>[];
    final submitTexts = <String>[];
    int signedCount = 0;

    for (int i = 0; i < getResults.length; i++) {
      final result = getResults[i];
      final user = allAccounts[i];
      getCheckInTexts.add('=== ${user.name} ===\n${const JsonEncoder.withIndent('  ').convert(result)}');

      if (result == null) continue;
      if (result['signed'] == true) {
        signedCount++;
        continue;
      }

      // 使用返回的位置信息自动签到
      final session = result['session'];
      final sessionMap = session is Map<String, dynamic> ? session : null;
      final lat = (sessionMap?['centerLat'] as num?)?.toDouble()
          ?? (result['lat'] as num?)?.toDouble()
          ?? (data['centerLat'] as num?)?.toDouble();
      final lng = (sessionMap?['centerLng'] as num?)?.toDouble()
          ?? (result['lng'] as num?)?.toDouble()
          ?? (data['centerLng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final address = (result['address'] as String?) ?? '';
      final api = RCCourseApi(user);
      final submitResult = await api.submitLocationCheckIn(lessonId, lat, lng, address);
      submitTexts.add('${user.name}\n${const JsonEncoder.withIndent('  ').convert(submitResult)}');

      if (submitResult != null && submitResult['code'] == 0) {
        signedCount++;
      }
    }

    // debug
    if (mounted) {
      _showDebugDataDialog(
        'getCheckIn 返回',
        getCheckInTexts.isEmpty ? '无账号' : getCheckInTexts.join('\n\n'),
      );
      if (submitTexts.isNotEmpty) {
        _showDebugDataDialog('submitLocationCheckIn 返回', submitTexts.join('\n\n'));
      }
    }

    // 更新时间线签到状态
    final total = allAccounts.length;
    String subtitle;
    if (total == 0) {
      subtitle = '无账号';
    } else if (signedCount >= total) {
      subtitle = '已签到 ($signedCount/$total)';
    } else if (signedCount > 0) {
      subtitle = '部分已签到 $signedCount/$total';
    } else {
      subtitle = '未签到';
    }
    if (mounted) {
      setState(() {
        event.subtitle = subtitle;
      });
    }
  }

  /// 处理位置签到结束
  void _handleLocationCheckInEnd(Map<String, dynamic> data) {
    final endMs = data['endedAt'] ?? data['endMs'] ?? data['serverTime'];
    final timestamp = endMs is int
        ? DateTime.fromMillisecondsSinceEpoch(endMs)
        : DateTime.now();

    setState(() {
      _timeline.add(TimelineEvent(
        type: 'locationcheckin_end',
        code: null,
        title: '位置签到结束',
        timestamp: timestamp
      ));
    });
    _scrollTimelineToBottom();
  }

  void _showDebugDataDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          IconButton(
            tooltip: '复制',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
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

  /// 非全屏模式下的 PPT 展示区
  Widget _buildSlideViewer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (index) {
              setState(() {
                _currentSlideIndex = index;
                _currentProblem = _slides[index]['problem'];
              });
            },
            itemBuilder: (context, index) => _buildSlideImage(_slides[index]),
          ),
          Positioned(
            left: 16,
            top: 16,
            child: _buildPageIndicator(),
          ),
          Positioned(
            right: 12,
            top: 16,
            child: _buildDownloadButton(),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _buildFullscreenButton(),
          ),
        ],
      ),
    );
  }

  /// 单张幻灯片图片 普通模式与全屏模式共用
  Widget _buildSlideImage(Map<String, dynamic> slide) {
    final cover = slide['coverAlt'] as String?;
    if (cover == null) {
      return const Center(
        child: Text('暂无 PPT', style: TextStyle(color: Colors.grey)),
      );
    }
    return Center(
      child: Image.network(
        cover,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.error_outline, size: 48, color: Colors.grey),
          );
        },
      ),
    );
  }

  /// 全屏模式下的 PPT 展示区
  Widget _buildFullScreenPPT() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentSlideIndex = index;
                      _currentProblem = _slides[index]['problem'];
                    });
                  },
                  itemBuilder: (context, index) => _buildSlideImage(_slides[index]),
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: _buildPageIndicator(),
              ),
              Positioned(
                right: 12,
                top: 16,
                child: _buildDownloadButton(),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _buildFullscreenButton(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _currentSlideIndex == _currentLessonSlideIndex
          ? RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: '当前 ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: '${_currentSlideIndex + 1}/$_totalCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Text(
              '${_currentSlideIndex + 1}/$_totalCount',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildDownloadButton() {
    return Builder(
      builder: (context) {
        return _buildOverlayIconButton(
          icon: Icons.download,
          onPressed: _isDownloading ? null : () => _showDownloadMenu(context),
          tooltip: '下载',
          progress: _downloadProgress,
        );
      },
    );
  }

  Future<void> _toggleFullScreen() async {
    if (_isFullScreen) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (mounted) {
      setState(() {
        _isFullScreen = !_isFullScreen;
      });
      // 全屏切换会改变 PageView 视口宽度，而 PageController 按像素保存页码，
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        if ((_pageController.page?.round() ?? 0) != _currentSlideIndex) {
          _pageController.jumpToPage(_currentSlideIndex);
        }
      });
    }
  }

  Widget _buildFullscreenButton() {
    return _buildOverlayIconButton(
      icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
      onPressed: _toggleFullScreen,
      tooltip: _isFullScreen ? '退出全屏' : '全屏',
    );
  }

  Widget _buildOverlayIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    double? progress,
  }) {
    return SizedBox(
      width: 24,
      height: 24,
      child: progress != null
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            )
          : IconButton(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              icon: Icon(icon, color: Colors.white, size: 24, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
              tooltip: tooltip,
            ),
    );
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
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  border: Border(
                                    top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
                                    bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _isProblemExpanded = !_isProblemExpanded;
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _getProblemTypeLabel(_currentProblem!.problemType),
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onPrimary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (_currentProblem!.problemType == 3 && _currentProblem!.pollingCount != null && _currentProblem!.pollingCount! > 1)
                                            Text(
                                              '（最多${_currentProblem!.pollingCount}项）',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          const SizedBox(width: 8),
                                          if (_currentProblem!.score > 0)
                                            Text(
                                              '(${(_currentProblem!.score / 100).toStringAsFixed(0)}分)',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          const Spacer(),
                                          if (_currentProblem != null && _unlockedProblemIds.contains(_currentProblem!.problemId) && _countdownSeconds != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.errorContainer,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.timer_outlined,
                                                    size: 18,
                                                    color: Theme.of(context).colorScheme.onErrorContainer,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '${_countdownSeconds! ~/ 60}:${(_countdownSeconds! % 60).toString().padLeft(2, '0')}',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Theme.of(context).colorScheme.onErrorContainer,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            _isProblemExpanded
                                                ? Icons.keyboard_arrow_up
                                                : Icons.keyboard_arrow_down,
                                            size: 20,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isProblemExpanded) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        _currentProblem!.body,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _buildAnswerOptions(),
                                      if ((_currentProblem != null && _unlockedProblemIds.contains(_currentProblem!.problemId)) || 
                                          (_timelineProblemId != null && _unlockedProblemIds.contains(_timelineProblemId!))) ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            ElevatedButton(
                                              onPressed: () async {await _submitAnswer();},
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Theme.of(context).colorScheme.primary,
                                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                              ),
                                              child: const Text(
                                                '提交',
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                              ),
                                            )
                                          ]
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _timeline.length,
                              itemBuilder: (context, index) {
                                final event = _timeline[index];
                                return _buildTimelineItem(event);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildTimelineItem(TimelineEvent event) {
    Color bgColor;
    IconData icon;
    
    switch (event.type) {
      case 'event':
        switch (event.code) {
          case 'LESSON_START':
            bgColor = Colors.green;
            icon = Icons.school;
            break;
          case 'SHOW_PRESENTATION':
          case 'START_PRESENTATION':
            bgColor = Colors.blue;
            icon = Icons.slideshow;
            break;
          case 'SHOW_FINISH':
            bgColor = Colors.orange;
            icon = Icons.stop_circle;
            break;
          case 'LESSON_FINISH':
            bgColor = Colors.red;
            icon = Icons.school;
          default:
            bgColor = Colors.grey;
            icon = Icons.info;
        }
        break;
      // case 'slide':
      //   bgColor = Colors.blue;
      //   icon = Icons.slideshow;
      //   break;
      case 'problem':
        bgColor = Colors.purple;
        icon = Icons.quiz;
        break;
      case 'randompick':
        bgColor = Colors.orange;
        icon = Icons.person_add;
        break;
      case 'locationcheckin_start':
        bgColor = Colors.teal;
        icon = Icons.location_on;
        break;
      case 'locationcheckin_end':
        bgColor = Colors.blueGrey;
        icon = Icons.location_off;
        break;
      default:
        bgColor = Colors.grey;
        icon = Icons.info;
    }
    
    return GestureDetector(
      onTap: event.type == 'problem' ? () => _handleTimelineProblemClick(event) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                color: bgColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _getEventTitle(event),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (event.type == 'problem')
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatRelativeTime(event.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (event.subtitle != null && event.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _getSubtitleColor(event.subtitle!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEventTitle(TimelineEvent event) {
    switch (event.type) {
      case 'slide':
        return '第 ${event.slideIndex} 页';
      case 'problem':
        final limit = event.limit;
        if (limit != null && limit > 0) {
          return '题目发布（作答时间：$limit秒）';
        }
        return '题目发布';
      default:
        return event.title ?? '';
    }
  }

  Color _getSubtitleColor(String subtitle) {
    if (subtitle.startsWith('已签到')) return Colors.green;
    if (subtitle.startsWith('部分')) return Colors.orange;
    if (subtitle.startsWith('签到中')) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Theme.of(context).colorScheme.error;
  }

  String _getProblemTypeLabel(int type) {
    return ProblemType.fromId(type).label;
  }

  Future<void> _handleTimelineProblemClick(TimelineEvent event) async {
    if (event.problemId == null || event.presentationId == null) return;
    
    // 如果当前不在对应的 presentation，先加载
    if (event.presentationId != _currentPresentationId) {
      await _loadPresentation(event.presentationId!);
    }
    
    // 找到对应的 slide 索引
    final slideIndex = event.slideIndex;
    if (slideIndex != null && slideIndex > 0) {
      final targetIndex = slideIndex;
      
      // 跳转到对应页面
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut
        );
      }
      
      setState(() {
        _currentSlideIndex = targetIndex;
        // 设置当前题目
        if (targetIndex >= 0 && targetIndex < _slides.length) {
          _currentProblem = _slides[targetIndex]['problem'];
          if (_currentProblem != null && event.problemDt != null) {
            _currentProblem = _currentProblem!.copyWith(dt: event.problemDt);
          }
        }
        // 记录从 timeline 点击的 problemId
        _timelineProblemId = event.problemId;
        if (event.problemId != null && !_unlockedProblemIds.contains(event.problemId!)) {
          _unlockedProblemIds.add(event.problemId!);
        }
        _countdownSeconds = 0;
      });
    }
  }

  Future<void> _submitAnswer() async {
    // 优先使用 _currentProblem，如果为空则使用 _timelineProblemId
    final problemId = _currentProblem?.problemId ?? _timelineProblemId;
    if (problemId == null) return;

    final problemType = _currentProblem?.problemType ?? 0;
    final problemDt = _currentProblem?.dt;

    // 检查是否有答案或图片
    if (_answer == null && _textAnswer == null && _uploadedImageUrls.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择或填写答案')),
        );
      }
      return;
    }

    // 判断是否超时（倒计时结束）
    final isTimeout = _countdownSeconds != null && _countdownSeconds! <= 0;
    
    // 为所有用户提交答案（带已上传的图片 URL）
    await _submitForAllAccounts(problemId, problemType, _uploadedImageUrls, isTimeout, problemDt);
  }

  Future<void> _submitForAllAccounts(String problemId, int problemType, List<String>? imageUrls, bool isTimeout, int? problemDt) async {
    final allAccounts = AccountManager.allAccounts;
    
    if (allAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的账号')),
        );
      }
      return;
    }

    int successCount = 0;
    final List<String> failedAccounts = [];

    final results = await ApiService.sendForEachUser(
      allAccounts,
      (user) async {
        final api = RCCourseApi(user);
        return await api.answer(
          problemId,
          problemType,
          retry: isTimeout,
          time: isTimeout ? problemDt : null,
          options: _answer,
          content: _textAnswer,
          imageUrls: imageUrls
        );
      },
    );

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final user = allAccounts[i];
      
      if (result != null && result['code'] == 0) {
        successCount++;
      } else {
        failedAccounts.add('${user.name}: ${result?["msg"] ?? "提交失败"}');
      }
    }

    _showSubmitResult(successCount, allAccounts.length, failedAccounts);
    
    // 提交成功后禁用按钮并清空图片
    setState(() {
      _countdownSeconds = 0;
      _selectedImages.clear();
      _uploadedImageUrls.clear();
    });
  }

  void _showSubmitResult(int successCount, int totalCount, List<String> failedAccounts) {
    if (!mounted) return;

    String message = '答案提交完成！\n成功：$successCount/$totalCount';
    if (failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == totalCount ? '全部提交成功' : '部分失败',
          style: TextStyle(
            color: successCount == totalCount ?
            Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();
    
    switch (_currentProblem!.problemType) {
      case 1: // 单选题 // 判断题在PPT是单选题
      case 3: // 投票题
        return _buildChoiceOptions();
      case 2: // 多选题
        return _buildMultipleChoiceOptions();
      case 4: // 填空题
        return _buildFillBlankInputs();
      case 5: // 主观题
        return _buildShortAnswerInputs();
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _pickImages() async {
    try {
      final ImagePicker picker = ImagePicker();

      final remainingCount = _maxImageCount - _selectedImages.length;

      final List<XFile> images = await picker.pickMultiImage(
          limit: remainingCount,
          imageQuality: 80
      );

      if (images.isNotEmpty) {
        // 并行上传所有图片
        final uploadFutures = images.map((image) async {
          try {
            final file = File(image.path);
            final imageUrl = await RCImageApi.uploadImage(file);
            return {'image': image, 'url': imageUrl};
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('图片上传失败：${image.path}')),
              );
            }
            return null;
          }
        }).toList();

        // 等待所有上传完成
        final results = await Future.wait(uploadFutures);

        // 更新状态
        if (mounted) {
          setState(() {
            for (final result in results) {
              if (result != null && result['url'] != null) {
                _selectedImages.add(result['image'] as XFile);
                _uploadedImageUrls.add(result['url'] as String);
              }
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _uploadedImageUrls.removeAt(index);
    });
  }

  Widget _buildShortAnswerInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '请输入答案',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (value) {
                  _textAnswer = value;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 32),
              onPressed: _pickImages,
              tooltip: '添加图片（最多 9 张）'
            ),
          ],
        ),
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_selectedImages[index].path),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
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
        ],
      ],
    );
  }

  Widget _buildFillBlankInputs() {
    if (_currentProblem == null) return const SizedBox.shrink();

    final blanks = _currentProblem!.blanks;

    if (blanks.isEmpty) {
      return TextField(
        decoration: const InputDecoration(
          hintText: '请输入答案',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          _answer = [value];
        },
      );
    }

    // 多个填空，显示多个输入框
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(blanks.length, (index) {
        final blank = blanks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            decoration: InputDecoration(
              labelText: '填空${blank.num}',
              hintText: '请输入第${blank.num}个空的答案',
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              // 存储所有答案
              final answers = List<String>.from(_answer ?? []);
              while (answers.length <= index) {
                answers.add('');
              }
              answers[index] = value;
              _answer = answers;
            },
          ),
        );
      }),
    );
  }

  Widget _buildChoiceOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();
      
    final options = _currentProblem!.options;
    if (options == null || options.isEmpty) {
      return const SizedBox.shrink();
    }
      
    return RadioGroup<String>(
      groupValue: _answer?.firstOrNull,
      onChanged: (value) {
        setState(() {
          _answer = value != null ? [value] : null;
        });
      },
      child: Column(
        children: options.map((option) {
          return RadioListTile<String>(
            value: option.key,
            title: Text('${option.key}. ${option.value}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            activeColor: Theme.of(context).colorScheme.primary,
            controlAffinity: ListTileControlAffinity.trailing,
            toggleable: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMultipleChoiceOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();
    
    final options = _currentProblem!.options;
    if (options == null || options.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: options.map((option) {
        final key = option.key;
        final isSelected = (_answer ?? []).contains(key);
        return CheckboxListTile(
          value: isSelected,
          title: Text('$key. ${option.value}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          activeColor: Theme.of(context).colorScheme.primary,
          controlAffinity: ListTileControlAffinity.trailing,
          onChanged: (value) {
            setState(() {
              final selectedKeys = _answer?.toSet() ?? <String>{};
              if (value == true) {
                selectedKeys.add(key);
              } else {
                selectedKeys.remove(key);
              }
              _answer = selectedKeys.toList();
            });
          },
        );
      }).toList(),
    );
  }

  String get _pptTitle =>
      _currentPresentationTitle?.isNotEmpty == true
          ? _currentPresentationTitle!
          : widget.title;

  double? get _downloadProgress =>
      _isDownloading && _downloadTotal > 0
          ? _downloadedCount / _downloadTotal
          : null;

  Future<void> _showDownloadMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay)
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(
          value: 'current',
          child: Text('下载当前页'),
        ),
        PopupMenuItem<String>(
          value: 'all',
          child: Text('下载所有页'),
        ),
      ],
    );

    if (result == 'current') {
      await _downloadCurrentPage();
    } else if (result == 'all') {
      await _downloadAllPages();
    }
  }

  Future<void> _downloadCurrentPage() async {
    String? cover;
    if (_slides.isNotEmpty && _currentSlideIndex < _slides.length) {
      cover = _slides[_currentSlideIndex]['coverAlt'] as String?;
    }
    if (cover == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可下载的页面')),
        );
      }
      return;
    }

    try {
      await _saveSlide(cover, title: '$_pptTitle-${_currentSlideIndex + 1}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _downloadAllPages() async {
    if (_isDownloading) return;

    final covers = _slides
        .map((slide) => slide['coverAlt'] as String?)
        .whereType<String>()
        .toList();

    if (covers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可下载的页面')),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadedCount = 0;
      _downloadTotal = covers.length;
    });

    int success = 0;
    final relativePath = 'Pictures/$_pptTitle';
    for (int i = 0; i < covers.length; i++) {
      try {
        await _saveSlide(
          covers[i],
          title: '${i + 1}',
          relativePath: relativePath,
        );
        success++;
      } catch (e) {
        logger.e('保存第 ${i + 1} 页失败：$e');
      }
      if (mounted) {
        setState(() {
          _downloadedCount = i + 1;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $success/${covers.length} 页')),
      );
    }
  }

  Future<void> _saveSlide(
    String imageUrl, {
    required String title,
    String? relativePath,
  }) async {
    // 从缓存中获取图片文件
    final file = await DefaultCacheManager().getSingleFile(imageUrl);
    final bytes = await file.readAsBytes();

    await PhotoManager.editor.saveImage(
      bytes,
      filename: '$title.jpg',
      title: title,
      relativePath: relativePath,
    );
  }
}

class TimelineEvent {
  final String type;
  final String? code;
  final String? title;
  final int? slideIndex;
  final int? total;
  final int? limit;
  final DateTime timestamp;
  String? subtitle;
  // problem
  final String? problemId;
  final String? presentationId;
  final int? problemDt;

  TimelineEvent({
    required this.type,
    required this.code,
    required this.title,
    this.slideIndex,
    this.total,
    this.limit,
    required this.timestamp,
    this.subtitle,
    this.problemId,
    this.presentationId,
    this.problemDt,
  });
}
