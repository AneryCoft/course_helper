import 'package:course_helper/session/account.dart';
import 'package:flutter/material.dart';
import 'package:im_flutter_sdk/im_flutter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../pages/Courses/list.dart';
import '../models/active.dart';
import '../platform.dart';

/// 环信即时通讯
class EasemobIM {
  static final EasemobIM _instance = EasemobIM._internal();
  factory EasemobIM() => _instance;
  EasemobIM._internal();

  static const _appKey = 'cx-dev#cxstudy';

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Function(bool)? _onConnectionChanged;

  void setConnectionCallback(Function(bool)? callback) {
    _onConnectionChanged = callback;
  }

  Future<void> initialize({
    Function(bool)? onConnectionChanged,
    Function(EMMessage)? onMessageReceived
  }) async {
    try {
      // 初始化本地通知插件
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false
      );
      await _notificationsPlugin.initialize(
        settings: const InitializationSettings(android: androidSettings, iOS: iosSettings)
      );

      final options = EMOptions.withAppKey(_appKey, osType: 2);
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
      await EMClient.getInstance.init(options);

      EMClient.getInstance.addConnectionEventHandler(
        'easemob_conn_handler',
        EMConnectionEventHandler(
          onConnected: () {
            _isLoggedIn = true;
            debugPrint('已连接到环信服务器');
            _onConnectionChanged?.call(true);
          },
          onDisconnected: () {
            debugPrint('断开连接');
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

      EMClient.getInstance.chatManager.addEventHandler(
        'easemob_msg_handler',
        EMChatEventHandler(
          onMessagesReceived: (List<EMMessage> messages) {
            debugPrint('收到 ${messages.length} 条新消息');
            for (var message in messages) {
              onMessageReceived?.call(message);
              _handleMessage(message);
            }
          }
        ),
      );

      _isLoggedIn = await EMClient.getInstance.isLoginBefore();
    } catch (e) {
      debugPrint('初始化错误: $e');
      rethrow;
    }
  }

  Future<void> login(String userName, String password) async {
    try {
      await EMClient.getInstance.loginWithPassword(userName, password);
      _isLoggedIn = true;
      
      // 登录后检查并请求通知权限
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('Easemob登录失败: $e');
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
      await EMClient.getInstance.logout(true);
      _isLoggedIn = false;
      _onConnectionChanged?.call(false);
    } catch (e) {
      debugPrint('Easemob退出失败: $e');
    }
  }

  Future<void> _handleMessage(EMMessage message) async {
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
      final courseId = courseInfo?['courseid'] ?? '';
      final classId = courseInfo?['classid'].toString() ?? '';
      final courseName = courseInfo?['coursename'] ??
          message.attributes!['em_apns_ext']['em_push_title'];
      // late String? groupName;

      final androidDetails = AndroidNotificationDetails(
        'course_activity_channel',
        '课程活动',
        channelDescription: '接收课程活动通知',
        importance: Importance.high,
        priority: Priority.high
      );

      final notificationDetails = NotificationDetails(android: androidDetails);

      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _notificationsPlugin.show(
        id: notificationId,
        title: '课程活动',
        body: '收到来自$courseName的$activeTypeName活动',
        notificationDetails: notificationDetails,
        payload: '${active.id}|$courseId|$classId',
      );

      // 始终显示应用内对话框（可选）
      final context = navigatorKey.currentContext;
      if (context != null) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('课程活动'),
            content: SingleChildScrollView(
              child: Text(
                '收到来自$courseName的$activeTypeName活动',
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
                  Navigator.pop(dialogContext);
                  CoursesPage.navigateToActive(context, active, courseId, classId, '');
                },
                child: const Text('查看'),
              ),
            ],
          ),
        );
      }
    }

    debugPrint('消息: ${message.toJson()}');
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
    EMClient.getInstance.chatManager.removeEventHandler('easemob_msg_handler');
    EMClient.getInstance.removeConnectionEventHandler('easemob_conn_handler');
    _isLoggedIn = false;
  }
}
