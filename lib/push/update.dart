import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../main.dart' show navigatorKey;
import '../ui/design_tokens.dart';
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
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.system_update_rounded, color: cs.primary, size: 30),
          title: const Text('发现新版本'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本号高亮
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.new_releases_outlined,
                            size: 16, color: cs.onPrimaryContainer),
                        const SizedBox(width: 6),
                        Text(
                          '最新版本  v$latestVersion',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '更新内容',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // 渲染 Markdown：去掉标题符号、把 - 转为圆点
                  ..._renderNotes(releaseNotes, cs),
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await StorageManager.prefs.setString(_skipVersionKey, latestVersion);
              },
              child: const Text('跳过此版本'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('稍后'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final uri = Uri.parse(downloadUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text('前往下载'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 把 GitHub Release 的 Markdown 简单渲染为可读文本：
  /// 去掉 ### 等标记，列表项转成带圆点的段落，跳过空行。
  static List<Widget> _renderNotes(String raw, ColorScheme cs) {
    final widgets = <Widget>[];
    for (final line in raw.split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;

      // 跳过纯标题行（内容与弹窗标题重复）
      if (RegExp(r'^#{1,6}\s').hasMatch(text)) {
        final heading = text.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        if (heading.trim().isEmpty) continue;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 2),
          child: Text(
            heading,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ));
        continue;
      }

      // 列表项
      final isBullet = RegExp(r'^[-*+]\s').hasMatch(text);
      final isOrdered = RegExp(r'^\d+[.)]\s').hasMatch(text);
      if (isBullet || isOrdered) {
        final content = isBullet
            ? text.replaceFirst(RegExp(r'^[-*+]\s+'), '')
            : text.replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 7),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _stripInlineMarkdown(content),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // 引用块
      if (text.startsWith('>')) {
        widgets.add(Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _stripInlineMarkdown(text.replaceFirst(RegExp(r'^>\s*'), '')),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: cs.onSurfaceVariant,
            ),
          ),
        ));
        continue;
      }

      // 普通段落
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          _stripInlineMarkdown(text),
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: cs.onSurfaceVariant,
          ),
        ),
      ));
    }
    return widgets;
  }

  /// 去掉行内 Markdown 标记：`code`、**bold**、[text](url) 等
  static String _stripInlineMarkdown(String text) {
    var result = text;
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => m.group(1) ?? '',
    );
    result = result.replaceAll(RegExp(r'`{1,3}'), '');
    result = result.replaceAll(RegExp(r'\*\*|__'), '');
    result = result.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
    return result.trim();
  }
}