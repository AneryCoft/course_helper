import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widget/changelog.dart';

/// 独立的「关于」页面（替代原弹窗）：展示应用信息、开发者与更新日志。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _initVersion();
  }

  Future<void> _initVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Image.asset('images/logo.png', width: 56, height: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '课程助手',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '版本 $_version',
                      style: TextStyle(color: cs.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('一个管理学习通、雨课堂课程的应用。'),
          const Text('支持多账号管理、课程查看、活动签到等功能。'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('开发者：'),
              _DeveloperLink(name: 'AneryCoft', url: 'https://github.com/AneryCoft'),
              const Text('、'),
              _DeveloperLink(name: 'GanPeng', url: 'https://github.com/GanPengZx'),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 8),
              Text(
                '更新日志',
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...changelogEntries.map((entry) => _ChangelogItem(entry: entry)),
        ],
      ),
    );
  }
}

class _ChangelogItem extends StatelessWidget {
  final ChangelogEntry entry;

  const _ChangelogItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'v${entry.version}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Text(entry.date, style: TextStyle(color: cs.outline, fontSize: 12)),
          const SizedBox(height: 4),
          ...entry.changes.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 4),
              child: Text('• $c'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperLink extends StatelessWidget {
  final String name;
  final String url;

  const _DeveloperLink({required this.name, required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        }
      },
      child: Text(name, style: TextStyle(color: cs.primary)),
    );
  }
}
