import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../main.dart' show navigatorKey;
import '../utils/storage.dart';

class Update {
  static const _skipVersionKey = 'skip_version';

  /// 更新发布渠道（GanPengZx 的 GitHub 仓库）
  static const String repoOwner = 'GanPengZx';
  static const String repoName = 'course_helper';

  static const _latestReleaseUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const _latestReleasePageUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest';

  static Future<void> checkUpdate({bool ignoreSkip = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        // GitHub API 要求携带 User-Agent
        headers: {'User-Agent': 'CourseHelper/$currentVersion'},
      ));
      final response = await dio.get(_latestReleaseUrl);
      final data = response.data;
      final latestVersion = data['tag_name']?.toString().replaceAll('v', '') ?? '';
      final skipVersion = StorageManager.prefs.getString(_skipVersionKey) ?? '';

      if ((ignoreSkip || latestVersion != skipVersion) && _isNewerVersion(latestVersion, currentVersion)) {
        _showUpdateDialog(
          latestVersion: latestVersion,
          releaseNotes: data['body'] ?? '暂无更新说明',
          downloadUrl: _pickDownloadUrl(data),
        );
      }
    } catch (e) {
      // 忽略更新检查错误
    }
  }

  /// 优先选择与当前 CPU 架构匹配的 APK，其次通用 APK，最后回落到 Release 页面。
  static String _pickDownloadUrl(dynamic data) {
    final assets = data is Map ? data['assets'] : null;
    if (assets is List) {
      final apks = assets
          .whereType<Map>()
          .where((a) => (a['name']?.toString() ?? '').toLowerCase().endsWith('.apk'))
          .toList();

      if (apks.isNotEmpty) {
        String nameOf(Map apk) => apk['name']?.toString().toLowerCase() ?? '';
        String urlOf(Map apk) =>
            apk['browser_download_url']?.toString() ?? _latestReleasePageUrl;

        // 1. 匹配设备 CPU 架构的拆分包
        final abi = _currentAbi();
        if (abi != null) {
          for (final apk in apks) {
            if (nameOf(apk).contains(abi)) return urlOf(apk);
          }
        }
        // 2. 通用包（文件名不含任何架构标记）
        for (final apk in apks) {
          final name = nameOf(apk);
          if (!name.contains('arm') && !name.contains('x86') && !name.contains('universal')) {
            return urlOf(apk);
          }
        }
        // 3. 兜底取第一个
        return urlOf(apks.first);
      }
    }
    return data is Map
        ? (data['html_url']?.toString() ?? _latestReleasePageUrl)
        : _latestReleasePageUrl;
  }

  /// 当前设备的 ABI 关键字，用于匹配 `CourseHelper_x.y.z_arm64-v8a.apk` 这类文件名。
  ///
  /// 优先通过原生库路径判断（Flutter 引擎的 libflutter.so 位于 ABI 子目录下），
  /// 判断不出来时返回 null，回落到通用包/第一个 APK。
  static String? _currentAbi() {
    if (!Platform.isAndroid) return null;
    try {
      final libraries = Platform.executableArguments;
      for (final arg in libraries) {
        for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']) {
          if (arg.contains(abi)) return abi;
        }
      }
    } catch (_) {
      // 忽略
    }
    return null;
  }

  static List<int> _parseVersion(String v) {
    // 去掉 pre-release(-) 与 build(+)，仅保留主版本号数字，避免 1.2.2-Beta 这类版本解析失败
    var clean = v.trim();
    final dash = clean.indexOf('-');
    if (dash >= 0) clean = clean.substring(0, dash);
    final plus = clean.indexOf('+');
    if (plus >= 0) clean = clean.substring(0, plus);
    return clean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = _parseVersion(latest);
      final currentParts = _parseVersion(current);

      for (int i = 0; i < 3; i++) {
        final latestNum = i < latestParts.length ? latestParts[i] : 0;
        final currentNum = i < currentParts.length ? currentParts[i] : 0;

        if (latestNum > currentNum) return true;
        if (latestNum < currentNum) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static void _showUpdateDialog({
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl
  }) {
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最新版本: v$latestVersion',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(releaseNotes),
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await StorageManager.prefs.setString(_skipVersionKey, latestVersion);
                },
                child: const Text('跳过该版本'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('前往下载'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}