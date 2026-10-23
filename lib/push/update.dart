import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../main.dart' show navigatorKey;
import '../utils/storage.dart';

class Update {
  static const _skipVersionKey = 'skip_version';

  static const _latestReleaseUrl = 'https://api.github.com/repos/AneryCoft/course_helper/releases/latest';
  static const _latestReleasePageUrl = 'https://github.com/AneryCoft/course_helper/releases/latest';

  static Future<void> checkUpdate({bool ignoreSkip = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final dio = Dio();
      final response = await dio.get(_latestReleaseUrl);
      final data = response.data;
      final latestVersion = data['tag_name']?.toString().replaceAll('v', '') ?? '';
      final skipVersion = StorageManager.prefs.getString(_skipVersionKey) ?? '';

      if ((ignoreSkip || latestVersion != skipVersion) && _isNewerVersion(latestVersion, currentVersion)) {
        _showUpdateDialog(
          latestVersion: latestVersion,
          releaseNotes: data['body'] ?? '暂无更新说明',
          downloadUrl: data['html_url'] ?? _latestReleasePageUrl
        );
      }
    } catch (e) {
      // 忽略更新检查错误
    }
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