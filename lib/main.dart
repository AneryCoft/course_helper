import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';

import './pages/accounts.dart';
import './pages/ai_chat_page.dart';
import './pages/courses/list.dart';
import './pages/login.dart';
import './pages/settings_page.dart';
import './setting/ai_setting.dart';
import './theme_mode_manager.dart';
import './api/api_service.dart';
import './session/cookie.dart';
import './session/account.dart';
import './platform.dart';
import './ui/app_theme.dart';
import './ui/design_tokens.dart';
import './utils/storage.dart';
import './utils/logger.dart';
import 'push/easemob.dart';
import 'push/update.dart';

// 赞助对话框显示状态键
const _hasSponsoredKey = 'has_sponsored';

const _baiduMapIosAk = 'ctB8LatQK24AeNLvBo2upeKtmTsYthdQ';

// 全局Navigator Key,用于在无context时显示dialog
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _initBaiduMapForIOS() async {
  if (!Platform.isIOS) return;

  BMFMapSDK.setAgreePrivacy(true);
  BMFMapSDK.setApiKeyAndCoordType(_baiduMapIosAk, BMF_COORD_TYPE.BD09LL);

  // 定位 SDK 为独立鉴权
  final locationPlugin = LocationFlutterPlugin();
  await locationPlugin.setAgreePrivacy(true);
  await locationPlugin.authAK(_baiduMapIosAk);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initLogger();

  FlutterError.onError = (details) {
    logger.e('FlutterError', error: details.exception, stackTrace: details.stack);
  };

  await _initBaiduMapForIOS();

  await StorageManager.initialize();

  await ThemeModeManager.init();

  await AiSetting.init();

  await ApiService.initialize();

  await PlatformManager().initialize();

  await AccountManager.initialize();

  await CookieManager.initialize();

  await EasemobIM().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeManager.notifier,
      builder: (context, themeMode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: '课程助手',
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [
                Locale('zh', 'CN'),
                Locale('en', 'US'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: AppTheme.light(lightDynamic),
              darkTheme: AppTheme.dark(darkDynamic),
              themeMode: themeMode,
              home: const MainPage(),
              routes: {
                '/accounts': (context) => const AccountsPage(),
                '/login': (context) => const LoginPage(),
              },
            );
          },
        );
      },
    );
  }
}

/// 应用外壳：底部导航 + 页面切换动画。
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  static const _destinations = <_NavItem>[
    _NavItem(
      label: '课程',
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories,
    ),
    _NavItem(
      label: '对话',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    _NavItem(
      label: '账号',
      icon: Icons.people_alt_outlined,
      selectedIcon: Icons.people_alt,
    ),
    _NavItem(
      label: '设置',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      coursesPageKey.currentState?.onVisibilityChanged(true);
      Update.checkUpdate();
      _showSponsorDialog();
    });
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    coursesPageKey.currentState?.onVisibilityChanged(index == 0);
  }

  void _showSponsorDialog() {
    final hasSponsored = StorageManager.prefs.getBool(_hasSponsoredKey) ?? false;
    if (hasSponsored) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.favorite_rounded, color: cs.error, size: 30),
          title: const Text('支持开发者'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.asset(
                    'images/mm_reward_qrcode.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '一款开源软件的开发纯属为爱发电\n如果可以，请您赞助支持，哪怕只是 1 元，谢谢！',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                        color: cs.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // 主按钮独占一行，两个次要操作并排在下方，避免三个按钮挤成竖排
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _saveImageAndSponsor(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: const Text('保存赞赏码并前往赞助'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('以后再说'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          StorageManager.prefs.setBool(_hasSponsoredKey, true);
                          Navigator.pop(context);
                        },
                        child: const Text('我已赞助'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveImageAndSponsor(BuildContext context) async {
    try {
      final imageData =
          await DefaultAssetBundle.of(context).load('images/mm_reward_qrcode.png');
      final bytes = imageData.buffer.asUint8List();

      await PhotoManager.editor.saveImage(bytes, filename: 'mm_reward_qrcode.png');

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('赞赏码已保存到相册，感谢您的支持！')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      // 直接使用 IndexedStack 保持各页面 State 不被销毁。
      // 注意：不要用 AnimatedSwitcher/KeyedSubtree 包裹，否则每次切换
      // 都会重建子树，导致对话记录、滚动位置等状态丢失。
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          CoursesPage(key: coursesPageKey),
          const AiChatPage(embedded: true),
          const AccountsPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: [
              for (final item in _destinations)
                NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}
