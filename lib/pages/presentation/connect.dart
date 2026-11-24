part of 'presentation.dart';

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

mixin _ConnectMixin on _PresentationPageStateBase {
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
              _notifyRandomPick(data);
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
        case 'notification':
          for (final notification in data['notifications']) {
            _handleNotification(notification['content'], notification['code']);
          }
      }
    } catch (e) {
      logger.e('解析消息失败：$e');
    }
  }

  void _notifyRandomPick(dynamic data) {
    final uid = data['uid'].toString();
    if (!AccountManager.allAccounts.any((u) => u.uid == uid)) {
      return;
    }

    NotificationService().show(
      title: '随机点名',
      body: '你被选中了：${data['name']}',
      androidDetails: const AndroidNotificationDetails(
        'random_pick_channel',
        '随机点名',
        channelDescription: '雨课堂随机点名通知'
      )
    );
  }

  Future<void> _handleNotification(String content, String code) async {
    final event = TimelineEvent(
        type: 'notification',
        code: code,
        title: content,
        timestamp: DateTime.now()
    );
    setState(() {
      _timeline.add(event);
    });
    _scrollTimelineToBottom();

    if (code != 'location_checkin_need_sign') return;

    // 查询所有账号签到状态
    final allAccounts = AccountManager.allAccounts;
    final getResults = await ApiService.sendForEachUser(
      allAccounts,
          (user) async {
        final api = RCCourseApi(user);
        return await api.getCheckIn();
      },
    );

    int signedCount = 0;

    for (int i = 0; i < getResults.length; i++) {
      final result = getResults[i];
      final user = allAccounts[i];

      if (result == null) continue;
      if (!result['needLocationSignIn']) {
        signedCount++;
        continue;
      }

      // 使用返回的位置信息自动签到
      final Map<String, dynamic> session = result['session'];

      final api = RCCourseApi(user);
      final submitResult = await api.submitLocationCheckIn(
          widget.lessonId, session['centerLat'], session['centerLng'], session['locationName']
      );

      if (submitResult != null && submitResult['code'] == 0) {
        signedCount++;
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
}
