import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_helper/models/chat_session.dart';
import 'package:course_helper/session/chat_history_store.dart';
import 'package:course_helper/setting/ai_setting.dart';
import 'package:course_helper/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageManager.initialize();
    await AiSetting.init();
  });

  setUp(() async {
    await ChatHistoryStore.clear();
  });

  group('推理等级', () {
    test('默认等级为 Low', () {
      expect(AiSetting.reasoningEffort, ReasoningEffort.low);
      expect(AiSetting.reasoningEffort.label, '低');
    });

    test('默认不启用深度思考', () {
      expect(AiSetting.deepThinking, isFalse);
      expect(AiSetting.effectiveReasoningEffort, isNull);
    });

    test('开启深度思考后才会下发推理参数', () async {
      await AiSetting.setDeepThinking(true);
      expect(AiSetting.effectiveReasoningEffort, ReasoningEffort.low);

      await AiSetting.setReasoningEffort(ReasoningEffort.high);
      expect(AiSetting.effectiveReasoningEffort, ReasoningEffort.high);

      await AiSetting.setDeepThinking(false);
      expect(AiSetting.effectiveReasoningEffort, isNull);
    });

    test('等级可持久化并恢复', () async {
      await AiSetting.setDeepThinking(true);
      await AiSetting.setReasoningEffort(ReasoningEffort.medium);

      await AiSetting.init();
      expect(AiSetting.deepThinking, isTrue);
      expect(AiSetting.reasoningEffort, ReasoningEffort.medium);

      // 还原
      await AiSetting.setDeepThinking(false);
      await AiSetting.setReasoningEffort(ReasoningEffort.low);
    });

    test('apiValue 与枚举名一致', () {
      expect(ReasoningEffort.low.apiValue, 'low');
      expect(ReasoningEffort.medium.apiValue, 'medium');
      expect(ReasoningEffort.high.apiValue, 'high');
    });

    test('fromName 容错', () {
      expect(ReasoningEffort.fromName('high'), ReasoningEffort.high);
      expect(ReasoningEffort.fromName('medium'), ReasoningEffort.medium);
      expect(ReasoningEffort.fromName('low'), ReasoningEffort.low);
      expect(ReasoningEffort.fromName('unknown'), ReasoningEffort.low);
      expect(ReasoningEffort.fromName(null), ReasoningEffort.low);
    });
  });

  group('联网搜索开关', () {
    test('默认关闭', () {
      expect(AiSetting.webSearch, isFalse);
    });

    test('可切换并持久化', () async {
      await AiSetting.setWebSearch(true);
      expect(AiSetting.webSearch, isTrue);

      await AiSetting.init();
      expect(AiSetting.webSearch, isTrue);

      await AiSetting.setWebSearch(false);
    });
  });

  group('思考过程', () {
    test('消息可携带思考过程', () {
      final msg = ChatMessage(
        role: 'assistant',
        content: '答案正文',
        reasoning: '先分析题意…',
      );
      expect(msg.hasReasoning, isTrue);
      expect(msg.reasoning, '先分析题意…');
    });

    test('无思考过程时 hasReasoning 为 false', () {
      expect(ChatMessage(role: 'assistant', content: 'x').hasReasoning, isFalse);
      expect(
        ChatMessage(role: 'assistant', content: 'x', reasoning: '  ').hasReasoning,
        isFalse,
      );
    });

    test('思考过程随对话一起持久化', () async {
      await ChatHistoryStore.save([
        ChatMessage(
          role: 'assistant',
          content: '正文',
          reasoning: '思考细节',
        ),
      ]);

      final loaded = ChatHistoryStore.load();
      expect(loaded.length, 1);
      expect(loaded.first.content, '正文');
      expect(loaded.first.reasoning, '思考细节');
      expect(loaded.first.hasReasoning, isTrue);
    });

    test('copyWith 可更新思考过程', () {
      final msg = ChatMessage(role: 'assistant', content: 'x');
      final updated = msg.copyWith(reasoning: '新思考');
      expect(updated.reasoning, '新思考');
      expect(updated.createdAt, msg.createdAt);
    });
  });
}
