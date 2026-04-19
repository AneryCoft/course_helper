import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../session/account.dart';
import '../models/user.dart';
import '../platform.dart';
import '../push/easemob.dart';
import 'widget/avatar.dart';
import 'login.dart';

class AccountChangeNotifier {
  static final AccountChangeNotifier _instance = AccountChangeNotifier._internal();
  factory AccountChangeNotifier() => _instance;
  AccountChangeNotifier._internal();

  final StreamController<String?> _controller = StreamController.broadcast();

  Stream<String?> get accountChanges => _controller.stream;

  void notifyAccountChanged(String? accountId) {
    _controller.add(accountId);
  }

  void dispose() {
    _controller.close();
  }
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> with TickerProviderStateMixin {
  List<User> _accounts = [];
  final Set<String> _selectedAccounts = <String>{};
  bool _isMultiSelectMode = false;
  String? _currentAccountId;
  PlatformType _selectedPlatform = PlatformManager().currentPlatform;
  StreamSubscription? _accountChangeSubscription;

  @override
  void initState() {
    super.initState();
    _loadAccounts();

    // 监听账户变更事件
    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((accountId) {
          if (mounted) {
            _loadAccounts();
          }
        });

    // 监听环信连接状态变化
    EasemobIM().setConnectionCallback((connected) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _accountChangeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final current = AccountManager.currentSessionId;
    final allAccounts = AccountManager.getAllAccounts();

    setState(() {
      _accounts = allAccounts;
      _currentAccountId = current;
    });
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedAccounts.contains(userId)) {
        _selectedAccounts.remove(userId);
      } else {
        _selectedAccounts.add(userId);
      }
      if (_selectedAccounts.isEmpty) _isMultiSelectMode = false;
    });
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) _selectedAccounts.clear();
    });
  }

  Future<void> _deleteSelectedAccounts() async {
    if (_selectedAccounts.isNotEmpty) {
      await AccountManager.removeAccounts(_selectedAccounts.toList());
      await _loadAccounts();
      _toggleMultiSelect();
    }
  }

  Future<void> _switchToAccount(User user) async {
    if (user.uid == _currentAccountId) {
      return;
    }
    await AccountManager.setCurrentSession(user.uid);
    AccountChangeNotifier().notifyAccountChanged(user.uid);

    setState(() {
      _currentAccountId = user.uid;
      _accounts.remove(user);
      _accounts.insert(0, user);
    });
  }

  Future<void> _navigateToPasswordLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage(initialLoginType: 'password')),
    );
    if (result == true) {
      await _loadAccounts();
    }
  }

  Future<void> _navigateToCaptchaLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage(initialLoginType: 'captcha')),
    );
    if (result == true) {
      await _loadAccounts();
    }
  }

  Future<void> _showQRCodeLoginDialog() async {
    final qrState = QRCodeLoginState();

    if (!await qrState.initialize()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取二维码失败')),
        );
      }
      qrState.dispose();
      return;
    }

    qrState.startPolling((bool success) async {
      if (success && await handleLoginSuccess(context) && mounted) {
        Navigator.pop(context, true);
        await _loadAccounts();
      }
      qrState.dispose();
    });

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (didPop) {
                  qrState.isLoginActive = false;
                  qrState.dispose();
                }
              },
              child: AlertDialog(
                title: const Text('二维码登录'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: qrState.qrImageUrl != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          qrState.qrImageUrl!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      )
                          : qrState.isLoading
                          ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('生成中...', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      )
                          : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('二维码加载失败', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      PlatformManager().isChaoxing ?
                      '使用学习通APP扫码登录' : '使用微信扫码登录',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '二维码失效时会自动刷新',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      qrState.isLoginActive = false;
                      qrState.dispose();
                      Navigator.pop(context);
                    },
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: qrState.isRefreshing || qrState.isLoading
                        ? null
                        : () async {
                      setState(() => qrState.isRefreshing = true);
                      await qrState.refreshQRCode();
                      setState(() => qrState.isRefreshing = false);
                    },
                    child: qrState.isRefreshing ? const Text('刷新中...') : const Text('刷新'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    qrState.dispose();
  }

  Widget _buildTitle(String name, bool isCurrentAccount) {
    return Row(
      children: [
        Text(name),
        if (isCurrentAccount)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('当前', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildListItemContent(
      BuildContext context, User user, bool isSelected, bool isCurrentAccount) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: AvatarWidget(key: ValueKey(user.avatar), imageUrl: user.avatar),
      title: _buildTitle(user.name, isCurrentAccount),
      subtitle: Text('ID: ${user.uid}\n手机号: ${user.phone}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrentAccount && PlatformManager().isChaoxing)
            IconButton(
              icon: Icon(
                EasemobIM().isLoggedIn ?
                Icons.notifications : Icons.notifications_off,
                color: EasemobIM().isLoggedIn ?
                Theme.of(context).colorScheme.primary : Colors.grey
              ),
              iconSize: 30,
              tooltip: '消息推送',
              onPressed: () async {
                if (EasemobIM().isLoggedIn) {
                  await EasemobIM().logout();
                } else {
                  await EasemobIM().loginCurrentUser();
                }
              },
            ),
          Visibility(
            visible: _isMultiSelectMode,
            child: Checkbox(
              value: isSelected,
              onChanged: (bool? value) {
                if (value != null) _toggleSelection(user.uid);
              },
            ),
          ),
        ],
      ),
      onTap: _isMultiSelectMode ? null : () => _switchToAccount(user),
      onLongPress: () {
        _toggleMultiSelect();
        _toggleSelection(user.uid);
      },
    );
  }

  void _showAboutDialog() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appIcon = Image.asset(
      'images/logo.png',
      width: 60,
      height: 60
    );
    
    showAboutDialog(
      context: context,
      applicationName: '课程助手',
      applicationVersion: packageInfo.version,
      applicationIcon: appIcon,
      // applicationLegalese: '',
      children: [
        const Text('一个管理学习通、雨课堂课程的应用。'),
        const Text('支持多账号管理、课程查看、活动签到等功能。'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('开发者：'),
            GestureDetector(
              onTap: () async {
                final Uri url = Uri.parse('https://github.com/AneryCoft');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.inAppBrowserView);
                }
              },
              child: Text(
                'AneryCoft',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedAccounts,
              tooltip: '删除选中账号',
            ),
          if (_selectedPlatform == PlatformType.rainClassroom)
            PopupMenuButton<RainClassroomServerType>(
              icon: const Icon(Icons.dns),
              tooltip: '切换服务器',
              onSelected: (RainClassroomServerType server) async {
                await PlatformManager().setServer(server);
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<RainClassroomServerType>(
                  enabled: true,
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setPopupState) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RadioGroup<RainClassroomServerType>(
                            groupValue: PlatformManager().currentServer,
                            onChanged: (RainClassroomServerType? value) async {
                              if (value != null) {
                                setPopupState(() {});
                                Navigator.pop(context);
                                await PlatformManager().setServer(value);
                              }
                            },
                            child: Column(
                              children: [
                                RadioListTile<RainClassroomServerType>(
                                  title: const Text('雨课堂'),
                                  value: RainClassroomServerType.yuketang,
                                  dense: true
                                ),
                                RadioListTile<RainClassroomServerType>(
                                  title: const Text('荷塘 · 雨课堂'),
                                  value: RainClassroomServerType.pro,
                                  dense: true
                                ),
                                RadioListTile<RainClassroomServerType>(
                                  title: const Text('长江 · 雨课堂'),
                                  value: RainClassroomServerType.changjiang,
                                  dense: true
                                ),
                                RadioListTile<RainClassroomServerType>(
                                  title: const Text('黄河 · 雨课堂'),
                                  value: RainClassroomServerType.huanghe,
                                  dense: true
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (String result) {
              if (result == 'about') {
                _showAboutDialog();
              }
            },
            itemBuilder: (BuildContext context) => [
              // 平台切换菜单项
              PopupMenuItem<String>(
                enabled: true,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioGroup<PlatformType>(
                          groupValue: _selectedPlatform,
                          onChanged: (PlatformType? value) async {
                            if (value != null) {
                              setState(() {
                                _selectedPlatform = value;
                              });
                              Navigator.pop(context);
                              await PlatformManager().setPlatform(value);
                            }
                          },
                          child: Column(
                            children: [
                              RadioListTile<PlatformType>(
                                title: const Text('学习通'),
                                value: PlatformType.chaoxing,
                                dense: true,
                              ),
                              RadioListTile<PlatformType>(
                                title: const Text('雨课堂'),
                                value: PlatformType.rainClassroom,
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  },
                ),
              ),
              // 关于菜单项
              const PopupMenuItem<String>(
                value: 'about',
                child: Row(
                  children: [
                    Text('关于'),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
      body: _accounts.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('暂无账号', style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('点击右下角添加账号', style: TextStyle(color: Colors.grey)),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _accounts.length,
        itemBuilder: (context, index) {
          final user = _accounts[index];
          final isSelected = _selectedAccounts.contains(user.uid);
          final isCurrent = user.uid == _currentAccountId;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isCurrent ? Theme.of(context).colorScheme.primaryContainer : null,
            child: _buildListItemContent(context, user, isSelected, isCurrent),
          );
        },
      ),
      floatingActionButton: SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        spacing: 5,
        spaceBetweenChildren: 2,
        overlayColor: Colors.transparent,
        overlayOpacity: 0.3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        children: [
          SpeedDialChild(
            child: const Icon(Icons.qr_code),
            label: '二维码登录',
            onTap: _showQRCodeLoginDialog,
          ),
          SpeedDialChild(
            child: const Icon(Icons.sms),
            label: '验证码登录',
            onTap: _navigateToCaptchaLogin,
          ),
          SpeedDialChild(
            child: const Icon(Icons.password),
            label: '密码登录',
            onTap: _navigateToPasswordLogin,
          ),
        ],
      ),
    );
  }
}