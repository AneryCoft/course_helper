import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket, File;

import '../api/course.dart';
import '../api/upload.dart';
import '../models/presentation.dart';
import '../session/account.dart';

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
  Future<void> onDestroy(DateTime timestamp) async {}
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
  
  // 菜单位置
  Offset _menuPosition = Offset.zero;


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
    super.dispose();
  }

  Future<void> _initialize() async {
    await _checkToken();
    _connectWebSocket();
  }

  Future<void> _checkToken() async {
    final lessonToken = RCCourseApi.getLessonToken();
    if (lessonToken == null) {
      final allAccounts = AccountManager.getAllAccounts();
      final currentUserId = AccountManager.currentSessionId;
        
      for (final user in allAccounts) {
        AccountManager.setCurrentSessionTemp(user.uid);
        final result = await RCCourseApi.checkIn(widget.lessonId);
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
      AccountManager.setCurrentSessionTemp(currentUserId!);
    }
  }

  Future<void> _startForegroundService() async {
    // 请求忽略电池优化
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
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
      final ws = await WebSocket.connect('wss://www.yuketang.cn/wsapp/');
      _ws = ws;

      final helloData = {
        "op": "hello",
        "userid": AccountManager.currentSessionId,
        "role": "student",
        "auth": RCCourseApi.getLessonToken(),
        "lessonid": widget.lessonId
      };

      ws.add(jsonEncode(helloData));

      ws.listen(
        (message) {
          _handleMessage(message);
        },
      );
    } catch (e) {
      debugPrint('WebSocket 连接失败：$e');
    }
  }

  void _handleMessage(dynamic message) async {
    try {
      final data = jsonDecode(message);
      final op = data['op'];

      debugPrint('WebSocket S2C：$message');
      
      final messageText = data['message'];

      if (op == 'hello') {
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
            final targetIndex = targetSlideIndex - 1;
            setState(() {
              _currentSlideIndex = targetIndex;
              _currentLessonSlideIndex = targetIndex; // 记录课堂当前播放的页码
              if (_currentSlideIndex >= 0 && _currentSlideIndex < _slides.length) {
                _currentProblem = _slides[_currentSlideIndex]['problem'];
              }
            });
          }
        }
        
        if (timeline != null) {
          _addTimelineEvents(timeline);
        }
        
        setState(() {
          _isInitialized = true;
        });
        
        // 等待页面构建完成后滑动到指定页
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (targetSlideIndex != null && targetSlideIndex > 0) {
            final targetIndex = targetSlideIndex - 1;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(targetIndex);
            }
          }
        });
      } else if (op == 'unlockproblem') {
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
      } else if (op == 'showpresentation') {
        final presentationId = data['presentation'];
        final slideIndex = data['slideindex'];
        final timeline = data['timeline'] as List?;
        // final shownow = data['shownow'] ?? false;
        
        if (presentationId != null && presentationId != _currentPresentationId) {
          await _loadPresentation(presentationId);
        }
        
        if (slideIndex != null) {
          final targetIndex = slideIndex - 1;
          setState(() {
            _currentLessonSlideIndex = targetIndex;
            _currentSlideIndex = targetIndex;
            if (_currentSlideIndex >= 0 && _currentSlideIndex < _slides.length) {
              _currentProblem = _slides[_currentSlideIndex]['problem'];
            }
          });
          // 滑动到指定页面
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.animateToPage(
                _currentSlideIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          });
        }
        
        if (timeline != null) {
          _addTimelineEvents(timeline);
        }
      } else if (op == 'slide') {
        final slideIndex = data['slideindex'];
        if (slideIndex != null) {
          final targetIndex = slideIndex - 1;
          setState(() {
            _currentLessonSlideIndex = targetIndex;
            _currentSlideIndex = targetIndex;
            if (_currentSlideIndex >= 0 && _currentSlideIndex < _slides.length) {
              _currentProblem = _slides[_currentSlideIndex]['problem'];
            }
          });
          // 滑动到指定页面
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.animateToPage(
                _currentSlideIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          });
        }
      } else if (op == 'slidenav') {
        // 处理幻灯片导航消息
        final slideData = data['slide'];
        if (slideData != null) {
          final slideIndex = slideData['si'];
          if (slideIndex != null) {
            final targetIndex = slideIndex - 1;
            setState(() {
              _currentLessonSlideIndex = targetIndex;
              _currentSlideIndex = targetIndex;
              if (_currentSlideIndex >= 0 && _currentSlideIndex < _slides.length) {
                _currentProblem = _slides[_currentSlideIndex]['problem'];
              }
            });
            // 滑动到指定页面
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_pageController.hasClients) {
                _pageController.animateToPage(
                  _currentSlideIndex,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            });
          }
        }
      } else if (op == 'extendtime') {
        // 处理延时消息
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
      } else if (op == 'callpaused') {
        // 处理随机点名等事件
        final eventData = data['event'];
        if (eventData != null) {
          final code = eventData['code'];
          if (code == 'RANDOM_PICK') {
            // 随机点名事件 - 添加到时间线
            setState(() {
              _timeline.add(TimelineEvent(
                type: 'randompick',
                code: 'RANDOM_PICK',
                title: eventData['title'],
                timestamp: DateTime.now(),
              ));
            });
          }
        }
      } else if (op == 'showfinished') {
        // 处理幻灯片结束放映事件
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
                title: title ?? '幻灯片结束放映',
                timestamp: DateTime.fromMillisecondsSinceEpoch(dt),
              ));
            });
          }
        }
      } else if (op == 'lessonfinished') {
        // 处理下课事件
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
                title: title ?? '下课啦！',
                timestamp: DateTime.fromMillisecondsSinceEpoch(dt),
              ));
            });
          }
        }
      }
    } catch (e) {
      debugPrint('解析消息失败：$e');
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
        // 处理特殊事件类型
        String eventType = type;
        String eventTitle = title ?? '';

        if (type == 'event' && code != null) {
          if (code == 'RANDOM_PICK') {
            eventType = 'randompick';
            eventTitle = title ?? '随机点名';
          }
        }
        
        // 过滤掉 slide 类型事件（不显示幻灯片切换）
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

  Future<void> _loadPresentation(String presentationId) async {
    if (_isLoading || presentationId == _currentPresentationId) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final pptData = await RCCourseApi.getPresentation(presentationId);
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
          if (_slides.isNotEmpty && _currentSlideIndex >= 0 && _currentSlideIndex < _slides.length) {
            _currentProblem = presentation.slides[_currentSlideIndex].problem;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载 PPT 失败：$e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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
              : Column(
                  children: [
                    // PPT 区域 - 根据屏幕宽度自动计算高度（保持幻灯片比例）
                    AspectRatio(
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
                            itemBuilder: (context, index) {
                              final slide = _slides[index];
                              final cover = slide['coverAlt'] as String?;
                              return Center(
                                child: cover != null
                                    ? GestureDetector(
                                        onLongPressDown: (details) {
                                          setState(() {
                                            _menuPosition = details.globalPosition;
                                          });
                                        },
                                        onLongPress: () async {
                                          final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
                                          if (overlay == null) return;
                                          
                                          final result = await showMenu<String>(
                                            context: context,
                                            position: RelativeRect.fromLTRB(
                                              _menuPosition.dx,
                                              _menuPosition.dy,
                                              _menuPosition.dx + 1,
                                              _menuPosition.dy + 1,
                                            ),
                                            items: [
                                              const PopupMenuItem<String>(
                                                value: 'save',
                                                child: Text('保存图片'),
                                              ),
                                            ],
                                          );
                                          
                                          if (result == 'save') {
                                            await _saveImageToGallery(cover);
                                          }
                                        },
                                        child: Image.network(
                                          cover,
                                          fit: BoxFit.contain,
                                          width: double.infinity,
                                          height: double.infinity,
                                          loadingBuilder: (context, child, progress) {
                                            if (progress == null) return child;
                                            return const Center(
                                              child: CircularProgressIndicator(),
                                            );
                                          },
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Center(
                                              child: Icon(
                                                Icons.error_outline,
                                                size: 48,
                                                color: Colors.grey,
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    : const Center(
                                        child: Text(
                                          '暂无 PPT',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                              );
                            },
                          ),
                          Positioned(
                            right: 16,
                            top: 16,
                            child: Container(
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
                            ),
                          ),
                        ],
                      ),
                    ),
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
                      _formatTime(event.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else {
      return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
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
    final allAccounts = AccountManager.getAllAccounts();
    final currentUserId = AccountManager.currentSessionId;
    
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

    try {
      for (final user in allAccounts) {
        AccountManager.setCurrentSessionTemp(user.uid);
        
        try {
          final result = await RCCourseApi.answer(
            problemId,
            problemType,
            retry: isTimeout,
            time: isTimeout ? problemDt : null,
            options: _answer,
            content: _textAnswer,
            imageUrls: imageUrls
          );

          if (result != null && result['code'] == 0) {
            successCount++;
          } else {
            failedAccounts.add('${user.name}: ${result?["msg"] ?? "提交失败"}');
          }
        } catch (e) {
          failedAccounts.add('${user.name}: 异常 - $e');
        }
      }
      AccountManager.setCurrentSessionTemp(currentUserId!);

      _showSubmitResult(successCount, allAccounts.length, failedAccounts);
      
      // 提交成功后禁用按钮并清空图片
      setState(() {
        _countdownSeconds = 0;
        _selectedImages.clear();
        _uploadedImageUrls.clear();
      });
    } finally {
      // 确保状态能被重置
      if (mounted) {
        setState(() {
        });
      }
    }
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
            final imageUrl = await RCUploadApi.uploadImage(file);
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
    
    // 解析题目中的填空位置
    final body = _currentProblem!.body;
    final blanks = <String>[];
    final pattern = RegExp(r'\[填空\d*\]');
    final matches = pattern.allMatches(body);
    
    for (var match in matches) {
      blanks.add(match.group(0) ?? '');
    }
    
    if (blanks.isEmpty) {
      return TextField(
        decoration: const InputDecoration(
          hintText: '请输入答案',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          _textAnswer = value;
        },
      );
    }
    
    // 多个填空，显示多个输入框
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(blanks.length, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            decoration: InputDecoration(
              labelText: '填空${index + 1}',
              hintText: '请输入第${index + 1}个空的答案',
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

  Future<void> _saveImageToGallery(String imageUrl) async {
    try {
      // 从缓存中获取图片文件
      final file = await DefaultCacheManager().getSingleFile(imageUrl);
      final bytes = await file.readAsBytes();
            
      await PhotoManager.editor.saveImage(
        bytes,
        filename: 'RainClassroom_${DateTime.now().millisecondsSinceEpoch}.jpg'
        // 不会被使用
      );

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
}

class TimelineEvent {
  final String type;
  final String? code;
  final String? title;
  final int? slideIndex;
  final int? total;
  final int? limit;
  final DateTime timestamp;
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
    this.problemId,
    this.presentationId,
    this.problemDt,
  });
}
