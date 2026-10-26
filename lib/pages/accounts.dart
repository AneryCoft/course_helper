import 'package:flutter/material.dart';
import 'dart:async';

import '../session/account.dart';
import '../models/user.dart';
import '../platform.dart';
import '../push/easemob.dart';
import '../ui/design_tokens.dart';
import '../ui/widgets.dart';
import 'widget/avatar.dart';
import 'widget/image_viewer.dart';
import 'login.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
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

    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((_) {
      if (mounted) _loadAccounts();
    });

    EasemobIM().setConnectionCallback((connected) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _accountChangeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    setState(() {
      _accounts = AccountManager.allAccounts;
      _currentAccountId = AccountManager.currentSessionId;
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
    if (_selectedAccounts.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除账号',
      message: '确定删除选中的 ${_selectedAccounts.length} 个账号？该操作不可撤销。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;

    await AccountManager.removeAccounts(_selectedAccounts.toList());
    await _loadAccounts();
    if (mounted) _toggleMultiSelect();
  }

  Future<void> _switchToAccount(User user) async {
    if (user.uid == _currentAccountId) return;
    await AccountManager.setCurrentSession(user.uid);
    await _loadAccounts();
  }

  Future<void> _navigateToPasswordLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage(initialLoginType: 'password')),
    );
    if (result == true) await _loadAccounts();
  }

  Future<void> _navigateToCaptchaLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage(initialLoginType: 'captcha')),
    );
    if (result == true) await _loadAccounts();
  }

  /// 底部弹出的添加账号方式选择
  Future<void> _showAddAccountSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page + 4,
                0,
                AppSpacing.page,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    '添加账号',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            _AddOption(
              icon: Icons.qr_code_rounded,
              title: '二维码登录',
              subtitle: '使用手机 App 扫码，最快捷',
              onTap: () => Navigator.pop(ctx, 'qrcode'),
            ),
            _AddOption(
              icon: Icons.sms_outlined,
              title: '验证码登录',
              subtitle: '通过手机号接收验证码',
              onTap: () => Navigator.pop(ctx, 'captcha'),
            ),
            _AddOption(
              icon: Icons.password_rounded,
              title: '密码登录',
              subtitle: '使用账号密码直接登录',
              onTap: () => Navigator.pop(ctx, 'password'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'qrcode':
        await _showQRCodeLoginDialog();
        break;
      case 'captcha':
        await _navigateToCaptchaLogin();
        break;
      case 'password':
        await _navigateToPasswordLogin();
        break;
    }
  }

  Future<void> _showQRCodeLoginDialog() async {
    final qrState = QRCodeLoginState();
    final wasUsingChaoxing = PlatformManager().isChaoxing;

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

    if (!mounted) {
      qrState.dispose();
      return;
    }

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final cs = Theme.of(context).colorScheme;
            qrState.onRefresh = () => setLocalState(() {});

            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: qrState.qrImageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: Image.network(
                                qrState.qrImageUrl!,
                                fit: BoxFit.contain,
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
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.error_outline,
                                          size: 40, color: cs.outline),
                                      const SizedBox(height: 8),
                                      Text(
                                        '二维码加载失败',
                                        style: TextStyle(color: cs.outline, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      wasUsingChaoxing ? '使用学习通 App 扫码登录' : '使用微信扫码登录',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '二维码失效时会自动刷新',
                      style: Theme.of(context).textTheme.bodySmall,
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
                ],
              ),
            );
          },
        );
      },
    );

    qrState.dispose();
  }

  Future<void> _showServerPicker() async {
    final servers = <(RainClassroomServerType, String)>[
      (RainClassroomServerType.yuketang, '雨课堂'),
      (RainClassroomServerType.pro, '荷塘 · 雨课堂'),
      (RainClassroomServerType.changjiang, '长江 · 雨课堂'),
      (RainClassroomServerType.huanghe, '黄河 · 雨课堂'),
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
              child: Row(
                children: [
                  Text('雨课堂服务器', style: Theme.of(ctx).textTheme.titleLarge),
                ],
              ),
            ),
            RadioGroup<RainClassroomServerType>(
              groupValue: PlatformManager().currentServer,
              onChanged: (value) async {
                if (value == null) return;
                await PlatformManager().setServer(value);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: Column(
                children: [
                  for (final (type, name) in servers)
                    RadioListTile<RainClassroomServerType>(
                      title: Text(name),
                      value: type,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _showPlatformPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
              child: Row(
                children: [
                  Text('选择平台', style: Theme.of(ctx).textTheme.titleLarge),
                ],
              ),
            ),
            RadioGroup<PlatformType>(
              groupValue: _selectedPlatform,
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _selectedPlatform = value);
                Navigator.pop(ctx);
                await PlatformManager().setPlatform(value);
                if (mounted) await _loadAccounts();
              },
              child: const Column(
                children: [
                  RadioListTile<PlatformType>(
                    title: Text('学习通'),
                    value: PlatformType.chaoxing,
                  ),
                  RadioListTile<PlatformType>(
                    title: Text('雨课堂'),
                    value: PlatformType.rainClassroom,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRain = PlatformManager().isRainClassroom;

    return Scaffold(
      backgroundColor: cs.surface,
      // MainPage 使用 extendBody，FAB 需上抬导航栏高度，否则会被遮住
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AnimatedSlide(
        duration: AppDuration.normal,
        offset: _isMultiSelectMode ? const Offset(0, 2) : Offset.zero,
        child: AnimatedOpacity(
          duration: AppDuration.fast,
          opacity: _isMultiSelectMode ? 0 : 1,
          child: Padding(
            padding: const EdgeInsets.only(
              bottom: AppSpacing.navBar + AppSpacing.fabGap,
            ),
            child: IgnorePointer(
              ignoring: _isMultiSelectMode,
              child: FloatingActionButton.extended(
                onPressed: _showAddAccountSheet,
                elevation: 2,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('添加账号'),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPageHeader(
              title: _isMultiSelectMode ? '已选 ${_selectedAccounts.length} 项' : '账号',
              subtitle: _isMultiSelectMode
                  ? '点击选择要删除的账号'
                  : '共 ${_accounts.length} 个账号',
              actions: _isMultiSelectMode
                  ? [
                      IconButton(
                        onPressed: _selectedAccounts.isEmpty
                            ? null
                            : _deleteSelectedAccounts,
                        tooltip: '删除',
                        icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                      ),
                      IconButton(
                        onPressed: _toggleMultiSelect,
                        tooltip: '取消',
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ]
                  : [
                      IconButton(
                        onPressed: _showPlatformPicker,
                        tooltip: '切换平台',
                        icon: Icon(
                          isRain ? Icons.cloud_outlined : Icons.school_outlined,
                        ),
                      ),
                      if (isRain)
                        IconButton(
                          onPressed: _showServerPicker,
                          tooltip: '切换服务器',
                          icon: const Icon(Icons.dns_outlined),
                        ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
            ),

            // 当前平台提示
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.xs,
                  AppSpacing.page,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    MetaChip(
                      label: isRain ? '雨课堂' : '学习通',
                      icon: isRain ? Icons.cloud_outlined : Icons.school_outlined,
                      color: cs.primary,
                    ),
                    if (isRain) ...[
                      const SizedBox(width: 6),
                      MetaChip(
                        label: _serverName(PlatformManager().currentServer),
                        icon: Icons.dns_outlined,
                      ),
                    ],
                    const Spacer(),
                    if (_accounts.isNotEmpty && !_isMultiSelectMode)
                      Text(
                        '长按账号可多选',
                        style: TextStyle(fontSize: 11, color: cs.outline),
                      ),
                  ],
                ),
              ),
            ),

            if (_accounts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.person_add_alt_1_rounded,
                  title: '还没有账号',
                  description: '添加学习通或雨课堂账号后即可查看课程和参与活动',
                  actionLabel: '添加账号',
                  onAction: _showAddAccountSheet,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.bottomInset,
                ),
                sliver: SliverList.builder(
                  // 多一项：列表末尾的「添加账号」卡片
                  itemCount: _accounts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _accounts.length) {
                      return _AddAccountTile(
                        onTap: _showAddAccountSheet,
                        hidden: _isMultiSelectMode,
                      );
                    }
                    final user = _accounts[index];
                    return AccountCard(
                      user: user,
                      isCurrent: user.uid == _currentAccountId,
                      isSelected: _selectedAccounts.contains(user.uid),
                      multiSelect: _isMultiSelectMode,
                      showPush: user.uid == _currentAccountId &&
                          PlatformManager().isChaoxing,
                      onTap: () {
                        if (_isMultiSelectMode) {
                          _toggleSelection(user.uid);
                        } else {
                          _switchToAccount(user);
                        }
                      },
                      onLongPress: () {
                        if (!_isMultiSelectMode) _toggleMultiSelect();
                        _toggleSelection(user.uid);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _serverName(RainClassroomServerType type) {
    switch (type) {
      case RainClassroomServerType.yuketang:
        return '雨课堂';
      case RainClassroomServerType.pro:
        return '荷塘';
      case RainClassroomServerType.changjiang:
        return '长江';
      case RainClassroomServerType.huanghe:
        return '黄河';
    }
  }
}

class AccountCard extends StatelessWidget {
  final User user;
  final bool isCurrent;
  final bool isSelected;
  final bool multiSelect;
  final bool showPush;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const AccountCard({
    super.key,
    required this.user,
    required this.isCurrent,
    required this.isSelected,
    required this.multiSelect,
    required this.showPush,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isValid = user.status;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm - 2,
      ),
      child: Material(
        color: isCurrent ? cs.primaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: cs.primary, width: 2)
                  : isCurrent
                      ? Border.all(color: cs.primary.withValues(alpha: 0.25))
                      : null,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                if (multiSelect)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected ? cs.primary : cs.outline,
                      size: 22,
                    ),
                  ),
                AvatarWidget(
                  key: ValueKey(user.avatar),
                  imageUrl: user.avatar,
                  size: 48,
                  borderRadius: AppRadius.md,
                  onTap: user.avatar.isNotEmpty
                      ? () => showImageViewer(
                            context,
                            imageUrl: user.avatar,
                            title: user.name,
                          )
                      : null,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.name,
                              style: tt.titleMedium?.copyWith(
                                fontSize: 15,
                                color: isCurrent ? cs.onPrimaryContainer : cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimary,
                                ),
                              ),
                            ),
                          ],
                          if (!isValid) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '已失效',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.phone.isEmpty ? 'ID: ${user.uid}' : user.phone,
                        style: tt.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (showPush && !multiSelect)
                  IconButton(
                    icon: Icon(
                      EasemobIM().isLoggedIn
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      size: 21,
                      color: EasemobIM().isLoggedIn ? cs.primary : cs.outline,
                    ),
                    tooltip: EasemobIM().isLoggedIn ? '关闭消息推送' : '开启消息推送',
                    onPressed: () async {
                      if (EasemobIM().isLoggedIn) {
                        await EasemobIM().logout();
                      } else {
                        await EasemobIM().loginCurrentAccount();
                      }
                    },
                  ),
                if (isCurrent && !multiSelect)
                  Icon(Icons.check_circle_rounded, size: 20, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddAccountTile extends StatelessWidget {
  final VoidCallback onTap;
  final bool hidden;

  const _AddAccountTile({required this.onTap, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (hidden) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm - 2,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.8),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    size: 20, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '添加账号',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: cs.primary, size: 22),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
      onTap: onTap,
    );
  }
}
