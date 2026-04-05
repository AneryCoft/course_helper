import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket, File;

import '../api/course.dart';
import '../models/presentation.dart';
import '../session/account.dart';

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

  bool _isLoading = false;
  bool _isInitialized = false;
  final List<TimelineEvent> _timeline = [];

  Problem? _currentProblem;
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
  bool _hasUnlockedProblem = false;


  @override
  void initState() {
    super.initState();
    _initialize();
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

      ws.listen((message) {_handleMessage(message);});

      ws.done.then((value) {
        debugPrint('连接已关闭');
      });
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
          final limit = problemData['limit'];
          if (limit != null && limit > 0) {
            setState(() {
              _countdownSeconds = limit;
              _hasUnlockedProblem = true;
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
            timestamp: DateTime.fromMillisecondsSinceEpoch(dt)
          ));
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
                                    ? Image.network(
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
                                          if (_hasUnlockedProblem && _countdownSeconds != null)
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
                                      if (_hasUnlockedProblem && _countdownSeconds != null) ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            ElevatedButton(
                                              onPressed: _countdownSeconds != null && _countdownSeconds! > 0
                                                  ? () async {await _submitAnswer();} : null,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _countdownSeconds != null && _countdownSeconds! > 0
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                                foregroundColor: _countdownSeconds != null && _countdownSeconds! > 0
                                                    ? Theme.of(context).colorScheme.onPrimary
                                                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
    
    return Container(
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
                  Text(
                    _getEventTitle(event),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
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

  Future<void> _submitAnswer() async {
    if (_currentProblem == null) return;

    final problemType = _currentProblem!.problemType;
    final problemId = _currentProblem!.problemId;

    // 检查是否有答案或图片
    if (_answer == null && _textAnswer == null && _uploadedImageUrls.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择或填写答案')),
        );
      }
      return;
    }

    // 为所有用户提交答案（带已上传的图片 URL）
    await _submitForAllAccounts(problemId, problemType, _uploadedImageUrls);
  }

  Future<void> _submitForAllAccounts(String problemId, int problemType, List<String>? imageUrls) async {
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
      case 1: // 单选题
      case 2: // 多选题
        return _buildChoiceOptions();
      case 3: // 投票题
        return _buildPollingOptions();
      case 4: // 填空题
        return _buildFillBlankInputs();
      case 5: // 主观题
        return _buildShortAnswerInputs();
      case 6: // 判断题
        return _buildChoiceOptions();
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
            final imageUrl = await RCCourseApi.uploadImageToQiniu(file);
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
      
    final isMultiple = _currentProblem!.problemType == 2;
      
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
            toggleable: isMultiple,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPollingOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();
    
    final options = _currentProblem!.options;
    if (options == null || options.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final pollingCount = _currentProblem!.pollingCount ?? 1;
    final isMultiple = pollingCount > 1;
    
    if (isMultiple) {
      // 多选投票题
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
                  // 选中：添加选项，但不超过最大限制
                  if (selectedKeys.length < pollingCount) {
                    selectedKeys.add(key);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('最多只能选择$pollingCount项')),
                    );
                    return;
                  }
                } else {
                  // 取消选中
                  selectedKeys.remove(key);
                }
                _answer = selectedKeys.toList();
              });
            },
          );
        }).toList(),
      );
    } else {
      // 单选投票题
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

  TimelineEvent({
    required this.type,
    required this.code,
    required this.title,
    this.slideIndex,
    this.total,
    this.limit,
    required this.timestamp
  });
}
