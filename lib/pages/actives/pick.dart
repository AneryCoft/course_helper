import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../api/image.dart';
import '../../../api/pick.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../widget/avatar.dart';

class PickPage extends StatefulWidget {
  final Active active;

  const PickPage({super.key, required this.active});

  @override
  State<PickPage> createState() => _PickPageState();
}

class _PickPageState extends State<PickPage> {
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _pickList = [];
  bool _hasInitialData = false;

  Timer? _pollTimer;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadPickList();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 1), // 原版为3秒
      (_) => _loadPickList(),
    );
  }

  Future<void> _loadPickList() async {
    try {
      final list = await Pick().getPickList(widget.active.id);
      if (!mounted) return;

      if (list == null) {
        setState(() {
          _isLoading = false;
          if (_pickList.isEmpty) {
            _errorMessage = '获取选人列表失败';
          }
        });
        return;
      }

      final parsed = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (_hasInitialData) {
        _checkPickedAccounts(_diffNewItems(parsed, _pickList));
      }

      setState(() {
        _pickList = parsed;
        _isLoading = false;
        _errorMessage = null;
        _hasInitialData = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_pickList.isEmpty) {
            _errorMessage = '加载数据出错: $e';
          }
        });
      }
    }
  }

  List<Map<String, dynamic>> _diffNewItems(
      List<Map<String, dynamic>> current,
      List<Map<String, dynamic>> previous) {
    final previousUids = previous
        .map((e) => (e['userId'] ?? '').toString())
        .toSet();
    return current
        .where((e) => !previousUids.contains((e['userId'] ?? '').toString()))
        .toList();
  }

  void _checkPickedAccounts(List<Map<String, dynamic>> newItems) {
    final accountUids = AccountManager.allAccounts.map((u) => u.uid).toSet();
    final picked = <({String uid, String name})>[];

    for (final item in newItems) {
      final uid = item['userId'].toString();
      if (uid.isEmpty || !accountUids.contains(uid)) continue;

      picked.add((uid: uid, name: item['name']));
    }

    if (picked.isNotEmpty) {
      _notifyPicked(picked);
    }
  }

  Future<void> _notifyPicked(List<({String uid, String name})> picked) async {
    final androidDetails = AndroidNotificationDetails(
      'course_pick_channel',
      '选人',
      channelDescription: '选人通知'
    );
    final darwinDetails = DarwinNotificationDetails(
        presentSound: true,
        presentAlert: false,
        presentBanner: false,
        presentList: false
    ); // 前台只声音通知
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails
    );
    final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final displayNames = picked
        .map((p) => p.name.isEmpty ? 'ID: ${p.uid}' : p.name)
        .toList();
    final body = picked.length == 1 ?
    '你被选中了：${displayNames.first}' : '你有 ${picked.length} 个账号被选中：${displayNames.join('、')}';

    await _notificationsPlugin.show(
      id: notificationId,
      title: '选人活动',
      body: body,
      notificationDetails: notificationDetails
    );
  }

  Widget _buildScore(double? userScore) {
    if (userScore == null) {
      return const SizedBox.shrink();
    }

    final score = userScore.toInt();
    final color = score < 0 ?
    Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    final text = score > 0 ? '+$score' : '$score';

    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 16,
        fontWeight: FontWeight.bold
      )
    );
  }

  Widget _buildPickItem(Map<String, dynamic> item) {
    final uid = item['userId'].toString();
    final name = item['name'];
    final isLocalAccount = AccountManager.allAccounts.any((u) => u.uid == uid);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isLocalAccount ?
      Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: AvatarWidget(
          imageUrl: CXImageApi.getAvatarUrlByUid(uid, 80),
          size: 50,
          borderRadius: 8,
          iconSize: 20
        ),
        title: Text(name),
        subtitle: Text('ID: $uid'),
        trailing: _buildScore(item['userScore'])
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.active.name),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Theme.of(context).colorScheme.error
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadPickList,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white
                            ),
                            child: const Text('重新加载')
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : _pickList.isEmpty
                  ? const Center(
                      child: Text(
                        '暂未开始选人',
                        style: TextStyle(fontSize: 16, color: Colors.grey)
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _pickList.length,
                      itemBuilder: (context, index) => _buildPickItem(_pickList[index])
                    )
    );
  }
}
