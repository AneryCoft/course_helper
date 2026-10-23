class ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

/// 更新日志数据，最新版本放在最前。
const List<ChangelogEntry> changelogEntries = [
  ChangelogEntry(
    version: '1.2.2',
    date: '2026-10-23',
    changes: [
      '关于与更新日志改为独立页面（不再以弹窗展示）',
      '账号页「更多选项」中移除多余的分隔线',
      '修复雨课堂 PPT 全屏时从第一张开始的问题：全屏会停留在老师当前讲解的页码，仅在老师切换幻灯片时跳转',
      '整体采用 Material Design 3 视觉风格',
      '新增「设置」导航页与主题模式切换（跟随系统 / 浅色 / 深色）',
      '开发者列表新增 GanPeng',
    ],
  ),
  ChangelogEntry(
    version: '1.2.1',
    date: '2026-09-01',
    changes: [
      '支持学习通与雨课堂多账号管理',
      '课程查看、各类签到、活动答题、消息推送等基础功能',
    ],
  ),
];
