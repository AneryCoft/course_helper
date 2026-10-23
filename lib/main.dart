import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';

import './pages/accounts.dart';
import './pages/courses/list.dart';
import './pages/login.dart';
import './pages/settings_page.dart';
import './theme_mode_manager.dart';
import './api/api_service.dart';
import './session/cookie.dart';
import './session/account.dart';
import './platform.dart';
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

  await ApiService.initialize();

  await PlatformManager().initialize();

  await AccountManager.initialize();

  await CookieManager.initialize();

  await EasemobIM().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  SnackBarThemeData _snackBarTheme(ColorScheme scheme) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.secondaryContainer,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      contentTextStyle: TextStyle(
        color: scheme.onSecondaryContainer,
        fontSize: 14,
        height: 1.4
      ),
      actionTextColor: scheme.primary,
      showCloseIcon: false,
      dismissDirection: DismissDirection.horizontal
    );
  }

  ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // ===== Material 3 组件主题，全局统一视觉语言 =====
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 0,
        color: scheme.outlineVariant,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      snackBarTheme: _snackBarTheme(scheme),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeManager.notifier,
      builder: (context, themeMode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final lightScheme = lightDynamic ??
                ColorScheme.fromSeed(seedColor: Colors.deepPurple);
            final darkScheme = darkDynamic ??
                ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark,);

            return MaterialApp(
              navigatorKey: navigatorKey,
              title: '课程助手',
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [
                Locale('zh', 'CN'),
                Locale('en', 'US')
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              theme: _buildTheme(lightScheme),
              darkTheme: _buildTheme(darkScheme),
              themeMode: themeMode,
              home: const MyHomePage(),
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return const MainPage();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (coursesPageKey.currentState as dynamic)?.onVisibilityChanged(true);
      Update.checkUpdate();
      _showSponsorDialog();
    });
  }

  void _showSponsorDialog() {
    final hasSponsored = StorageManager.prefs.getBool(_hasSponsoredKey) ?? false;
    if (hasSponsored) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('支持开发者'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'images/mm_reward_qrcode.png',
                width: 250,
                height: 250
              ),
              const SizedBox(height: 16),
              const Text(
                '一款开源软件的开发纯属为爱发电\n如果可以，请您赞助支持，哪怕只是1元，谢谢！',
                style: TextStyle(fontSize: 16)
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              StorageManager.prefs.setBool(_hasSponsoredKey, true);
              Navigator.pop(context);
            },
            child: const Text('我已赞助')
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')
          ),
          FilledButton(
            onPressed: () => _saveImageAndSponsor(context),
            child: const Text('去赞助')
          ),
        ],
      ),
    );
  }

  Future<void> _saveImageAndSponsor(BuildContext context) async {
    try {
      final imageData = await DefaultAssetBundle.of(context).load('images/mm_reward_qrcode.png');
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
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          CoursesPage(key: coursesPageKey),
          const AccountsPage(),
          const SettingsPage(),
        ]
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
          (coursesPageKey.currentState as dynamic)?.onVisibilityChanged(index == 0);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '课程',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: '账号',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}