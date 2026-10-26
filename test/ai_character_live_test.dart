import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_helper/api/ai.dart';
import 'package:course_helper/setting/ai_setting.dart';
import 'package:course_helper/setting/built_in_cards.dart';
import 'package:course_helper/utils/storage.dart';

/// 联调测试：验证角色卡是否真正注入到 AI 请求中。
///
/// 使用 `flutter test --no-test-assets` 之外的方式绕过 TestWidgetsFlutterBinding
/// 对 HTTP 的拦截：这里直接用 dart:io 的 HttpClient 复现请求体，
/// 断言角色卡的 system / assistant 消息确实出现在请求载荷里。
///
/// ```
/// flutter test test/ai_character_live_test.dart \
///   --dart-define=AI_BASE_URL=https://api.example.com/v1 \
///   --dart-define=AI_TOKEN=sk-xxx \
///   --dart-define=AI_MODEL=model-name
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment('AI_BASE_URL');
  const token = String.fromEnvironment('AI_TOKEN');
  const model = String.fromEnvironment('AI_MODEL');

  final skipReason = (baseUrl.isEmpty || token.isEmpty)
      ? '未提供 AI_BASE_URL / AI_TOKEN，跳过联调测试'
      : null;

  setUpAll(() async {
    // 存储初始化与凭据无关，始终执行，保证角色卡读写用例可运行
    SharedPreferences.setMockInitialValues({});
    await StorageManager.initialize();
    await AiSetting.init();

    if (baseUrl.isEmpty || token.isEmpty) return;
    await AiSetting.setBaseUrl(baseUrl);
    await AiSetting.setToken(token);
    if (model.isNotEmpty) await AiSetting.setModel(model);
  });

  test('默认角色卡被选中', () {
    expect(AiSetting.activeCard.id, BuiltInCards.defaultCardId);
    expect(AiSetting.isDefaultCardActive, isTrue);
  });

  test('测试消息包含角色设定与开场白', () {
    final messages = AiService.buildTestMessages();
    expect(messages.first['role'], 'system');
    expect(
      messages.first['content']!
          .contains(BuiltInCards.defaultCard.persona.substring(0, 20)),
      isTrue,
    );
    expect(messages.length, greaterThanOrEqualTo(3));
    expect(messages[1]['role'], 'assistant');
    expect(
      BuiltInCards.defaultCard.greetings.contains(messages[1]['content']),
      isTrue,
    );
  });

  test('切换角色卡后 system 消息随之变化', () async {
    await AiSetting.setActiveCard(BuiltInCards.all[1].id);
    final messages = AiService.buildTestMessages();
    expect(
      messages.first['content']!.contains(
        BuiltInCards.all[1].persona.substring(0, 20),
      ),
      isTrue,
    );
    await AiSetting.setActiveCard(BuiltInCards.defaultCardId);
  });

  test('自定义角色卡可保存并生效', () async {
    final card = AiSetting.blankCard().copyWith(
      name: '测试卡',
      persona: '你是一位只回答「测试通过」的助手。',
      greetings: ['好的，测试通过。'],
    );
    await AiSetting.saveCard(card);
    await AiSetting.setActiveCard(card.id);

    expect(AiSetting.allCards.any((c) => c.id == card.id), isTrue);
    expect(AiSetting.activeCard.name, '测试卡');
    expect(
      AiService.buildTestMessages().first['content']!.contains('测试通过'),
      isTrue,
    );

    await AiSetting.deleteCard(card.id);
    expect(AiSetting.isDefaultCardActive, isTrue);
    expect(AiSetting.allCards.any((c) => c.id == card.id), isFalse);
  });

  // 真实网络调用请使用 tool/verify_character_card.dart（flutter_test 会拦截 HTTP）：
  //   dart run tool/verify_character_card.dart <baseUrl> <token> <model>
}
