import 'package:flutter_test/flutter_test.dart';

import 'package:course_helper/api/ai.dart';
import 'package:course_helper/setting/ai_setting.dart';
import 'package:course_helper/utils/storage.dart';

/// 联调测试：走真实 AI 接口，验证拉取模型、对话与答题解析全链路。
///
/// 地址与 Token 需在运行前通过环境变量提供，避免把密钥写进仓库：
/// ```
/// flutter test test/ai_live_test.dart \
///   --dart-define=AI_BASE_URL=https://api.example.com/v1 \
///   --dart-define=AI_TOKEN=sk-xxx \
///   --dart-define=AI_MODEL=model-name
/// ```
void main() {
  const baseUrl = String.fromEnvironment('AI_BASE_URL');
  const token = String.fromEnvironment('AI_TOKEN');
  const model = String.fromEnvironment('AI_MODEL');

  setUpAll(() async {
    if (baseUrl.isEmpty || token.isEmpty) return;
    await StorageManager.initialize();
    await AiSetting.init();
    await AiSetting.setBaseUrl(baseUrl);
    await AiSetting.setToken(token);
    if (model.isNotEmpty) await AiSetting.setModel(model);
  });

  final skipReason = (baseUrl.isEmpty || token.isEmpty)
      ? '未提供 AI_BASE_URL / AI_TOKEN，跳过联调测试'
      : null;

  test('拉取模型列表', () async {
    final models = await AiService.fetchModels();
    expect(models, isNotEmpty);
    // ignore: avoid_print
    print('模型数量: ${models.length}, 前五个: ${models.take(5).map((e) => e.id).join(', ')}');
  }, skip: skipReason, timeout: const Timeout(Duration(minutes: 2)));

  test('连通性测试', () async {
    final selected = AiSetting.model;
    if (selected.isEmpty) return;
    final reply = await AiService.testConnection(selected);
    expect(reply, isNotEmpty);
    // ignore: avoid_print
    print('连通性回复: $reply');
  }, skip: skipReason, timeout: const Timeout(Duration(minutes: 2)));

  test('批量答题并解析', () async {
    final selected = AiSetting.model;
    if (selected.isEmpty) return;
    final answers = await AiService.solveQuestions(
      model: selected,
      questions: const [
        '[0] 题型：单选题\n题干：下列哪个是中国的首都？\n选项：\nA. 上海\nB. 北京\nC. 广州\nD. 深圳',
        '[1] 题型：填空题\n题干：水的化学式是____。\n要求填写 1 个空。',
        '[2] 题型：简答题\n题干：简述光合作用的意义。',
      ],
    );
    expect(answers.length, 3);
    expect(answers[0]!.options, contains('B'));
    expect(answers[1]!.blanks, isNotEmpty);
    expect(answers[2]!.text, isNotEmpty);
  }, skip: skipReason, timeout: const Timeout(Duration(minutes: 3)));
}
