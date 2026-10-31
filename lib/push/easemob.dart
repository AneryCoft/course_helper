import 'dart:async';

import 'package:course_helper/session/account.dart';
import 'package:flutter/material.dart';
import 'package:im_flutter_sdk/im_flutter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../pages/courses/list.dart';
import '../models/active.dart';
import '../platform.dart';
import '../utils/logger.dart';
import '../utils/time.dart';
import 'notification.dart';

/// 环信即时通讯
class EasemobIM {
  static final EasemobIM _instance = EasemobIM._internal();
  factory EasemobIM() => _instance;
  EasemobIM._internal();

  static const _appKey = 'cx-dev#cxstudy';

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  Function(bool)? _onConnectionChanged;

  final List<_ActivityPayload> _pending = [];
  Timer? _dialogDebounce;

  void setConnectionCallback(Function(bool)? callback) {
    _onConnectionChanged = callback;
  }

  Future<void> initialize({
    Function(bool)? onConnectionChanged,
    Function(ChatMessage)? onMessageReceived
  }) async {
    try {
      final options = ChatOptions.withAppKey(_appKey, osType: 2);
      // 使用Linux登录 避免让移动设备掉线

      // deviceName: 'webim', osType: 16 无法使用网页登录
      // code: 214 desc: User is logged in to too many devices
      /*
      OsType: {
        values: {
          OS_IOS: 0,
          OS_ANDROID: 1,
          OS_LINUX: 2,
          OS_OSX: 3,
          OS_WIN: 4,
          OS_OTHER: 16
        }
      },
      */
      await ChatClient.getInstance.init(options);

      ChatClient.getInstance.addConnectionEventHandler(
        'easemob_conn_handler',
        ConnectionEventHandler(
          onConnected: () {
            _isLoggedIn = true;
            logger.i('已连接到环信服务器');
            _onConnectionChanged?.call(true);
          },
          onDisconnected: () {
            logger.i('断开连接');
            _onConnectionChanged?.call(false);
          },
          // 用户从其他设备登录
          onUserDidLoginFromOtherDevice: (info) {
            _isLoggedIn = false;
            _onConnectionChanged?.call(false);
            _showKickedDialog(info);
          }
        ),
      );

      ChatClient.getInstance.chatManager.addEventHandler(
        'easemob_msg_handler',
        ChatEventHandler(
          onMessagesReceived: (List<ChatMessage> messages) {
            logger.i('收到 ${messages.length} 条新消息');
            for (var message in messages) {
              onMessageReceived?.call(message);
              _handleMessage(message);
            }
          }
        ),
      );

      _isLoggedIn = await ChatClient.getInstance.isLoginBefore();
    } catch (e) {
      logger.e('初始化错误: $e');
      rethrow;
    }
  }

  Future<void> login(String userName, String password) async {
    try {
      await ChatClient.getInstance.loginWithPassword(userName, password);
      _isLoggedIn = true;
      
      // 登录后检查并请求通知权限
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      logger.e('Easemob登录失败: $e');
      // code: 200 desc: The user is already logged in
      // code: 218 desc: Another user is already logged in
    }
  }

  Future<void> loginCurrentAccount() async {
    final user = AccountManager.getAccountById(AccountManager.currentSessionId!)!;
    await login(user.imAccount!['userName']!, user.imAccount!['password']!);
  }

  Future<void> logout() async {
    try {
      await ChatClient.getInstance.logout(true);
      _isLoggedIn = false;
      _onConnectionChanged?.call(false);
    } catch (e) {
      logger.e('Easemob退出失败: $e');
    }
  }

  Future<void> _handleMessage(ChatMessage message) async {
    if (message.attributes != null) {
      final attachment = message.attributes!['attachment'];
      final activeInfo = attachment['att_chat_course'];

      final String activeTypeName = activeInfo['atypeName'];
      Active active = Active(
        type: activeInfo['atype'],
        id: activeInfo['aid'].toString(),
        name: activeInfo['title'],
        description: activeInfo['subTitle'],
        startTime: 0,
        url: activeInfo['url'],
        attendNum: 0,
        status: true
      );

      final courseInfo = activeInfo['courseInfo'];
      final courseId = (courseInfo?['courseid'] ?? '').toString();
      final classId = (courseInfo?['classid'] ?? '').toString();
      final courseName = (courseInfo?['coursename'] ??
          message.attributes!['em_apns_ext']['em_push_title'] ?? '').toString();

      await NotificationService().show(
        title: '课程活动',
        body: '收到来自$courseName的$activeTypeName活动',
        payload: '${active.id}|$courseId|$classId',
        androidDetails: const AndroidNotificationDetails(
          'course_activity_channel',
          '课程活动',
          channelDescription: '接收课程活动通知',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
      );

      ActivityMessageStore().add(courseId, classId);
      _pending.add(_ActivityPayload(
        active: active,
        activeTypeName: activeTypeName,
        courseId: courseId,
        classId: classId,
        courseName: courseName,
        serverTime: message.serverTime
      ));
      _scheduleDialog();
    }

    logger.d('消息: ${message.toJson()}');
  }

  void _scheduleDialog() {
    _dialogDebounce?.cancel();
    _dialogDebounce = Timer(const Duration(milliseconds: 400), () {
      final pending = List<_ActivityPayload>.from(_pending);
      _pending.clear();
      if (pending.isEmpty) return;

      if (pending.length == 1) {
        _showActivityDialog(pending.first);
      } else {
        _showActivityListDialog(pending);
      }
    });
  }

  void _showActivityDialog(_ActivityPayload payload) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('课程活动'),
        content: SingleChildScrollView(
          child: Text(
            '收到来自${payload.courseName}的${payload.activeTypeName}活动',
            style: const TextStyle(fontSize: 15),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await PlatformManager().setPlatform(PlatformType.chaoxing);
              Navigator.pop(dialogContext);
              CoursesPage.navigateToActive(
                context,
                payload.active,
                payload.courseId,
                payload.classId,
                '',
              );
            },
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }

  void _showActivityListDialog(List<_ActivityPayload> list) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final reversed = list.reversed.toList();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('课程活动'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: reversed.length,
            itemBuilder: (itemContext, index) {
              final payload = reversed[index];
              final title = payload.active.name.isEmpty ?
              payload.activeTypeName : payload.active.name;
              final subtitle = payload.courseName.isEmpty ?
              payload.activeTypeName : payload.courseName;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(itemContext).colorScheme.secondaryContainer,
                  child: Icon(
                    payload.active.getIcon(),
                    color: Theme.of(itemContext).colorScheme.onSecondaryContainer
                  )
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis
                ),
                trailing: Text(
                  formatRelativeTime(DateTime.fromMillisecondsSinceEpoch(payload.serverTime)),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)
                ),
                onTap: () async {
                  await PlatformManager().setPlatform(PlatformType.chaoxing);
                  // Navigator.pop(dialogContext);
                  CoursesPage.navigateToActive(
                    context,
                    payload.active,
                    payload.courseId,
                    payload.classId,
                    ''
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }


  void _showKickedDialog(LoginExtensionInfo info) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(
          // User-Agent: ${info.ext}
          child: Text(
              '当前学习通IM账号在${info.deviceName}登录',
              style: const TextStyle(fontSize: 15)
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await PlatformManager().setPlatform(PlatformType.chaoxing);
              loginCurrentAccount();
              Navigator.pop(dialogContext);
            },
            child: const Text('重新登录'),
          ),
        ],
      ),
    );
  }

  void dispose() {
    ChatClient.getInstance.chatManager.removeEventHandler('easemob_msg_handler');
    ChatClient.getInstance.removeConnectionEventHandler('easemob_conn_handler');
    _isLoggedIn = false;
  }
}

class _ActivityPayload {
  final Active active;
  final String activeTypeName;
  final String courseId;
  final String classId;
  final String courseName;
  final int serverTime;

  _ActivityPayload({
    required this.active,
    required this.activeTypeName,
    required this.courseId,
    required this.classId,
    required this.courseName,
    required this.serverTime,
  });
}

/// 课程活动未读消息存储。
class ActivityMessageStore {
  static final ActivityMessageStore _instance = ActivityMessageStore._internal();
  factory ActivityMessageStore() => _instance;
  ActivityMessageStore._internal();

  final Map<String, _CourseUnread> _unread = {};
  final StreamController<void> _controller = StreamController.broadcast();

  Stream<void> get changes => _controller.stream;

  String _key(String courseId, String classId) => '$courseId|$classId';

  void add(String courseId, String classId) {
    _unread.putIfAbsent(_key(courseId, classId), () => _CourseUnread()).count++;
    _controller.add(null);
  }

  int countOf(String courseId, String classId) =>
      _unread[_key(courseId, classId)]?.count ?? 0;

  void clear(String courseId, String classId) {
    if (_unread.remove(_key(courseId, classId)) != null) {
      _controller.add(null);
    }
  }

  void clearAll() {
    if (_unread.isNotEmpty) {
      _unread.clear();
      _controller.add(null);
    }
  }
}

class _CourseUnread {
  int count = 0;
}
