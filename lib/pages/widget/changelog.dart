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
    version: '1.2.4',
    date: '2026-10-25',
    changes: [
      '界面全面重构：统一到 Material You 设计语言，圆角、间距与动效全局规范化',
      '课程页改用大标题折叠头部 + 卡片式列表，无封面的课程自动生成首字渐变图标',
      '账号页改为卡片布局：长按多选、底部弹窗选择登录方式，平台与服务器切换更直观',
      '设置页重组为分组卡片，新增动态取色说明与本机版本信息',
      '答题页重新设计题卡：题号徽章、题型标签、AI 解析折叠条，选项改用圆形/方形指示器',
      '登录页、签到、投票、问卷、讨论等页面统一采用沉浸式 AppBar',
      '新增骨架屏加载态、统一空状态与确认对话框组件',
    ],
  ),
  ChangelogEntry(
    version: '1.2.3',
    date: '2026-10-24',
    changes: [
      '新增「AI 调用设置」：自行填写 API 地址与 Token，拉取并选择可用模型',
      '新增 AI 测试连通性、AI 答题开关与设置页 AI 入口',
      '支持自定义系统提示词与答题提示词（{{questions}} 为题目占位符）',
      '雨课堂随堂测验支持「AI 一键生成答案与解析」：自动填入选中的选项、填空与简答题答案，并在每题下方展示解析',
      '更新检查渠道切换至 GanPengZx/course_helper，下载时优先匹配设备架构的 APK',
      '出于安全考虑，程序不内置任何 AI 服务地址与密钥，配置仅保存在本机',
    ],
  ),
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
