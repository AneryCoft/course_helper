import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _nextId = 0;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  Future<void> show({
    required String title,
    required String body,
    String? payload,
    required AndroidNotificationDetails androidDetails,
  }) async {
    await initialize();

    const darwinDetails = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: false,
      presentBanner: false,
      presentList: false
    );

    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
    );
  }
}
