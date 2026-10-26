import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_helper/models/chat_session.dart';
import 'package:course_helper/session/chat_history_store.dart';
import 'package:course_helper/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageManager.initialize();
  });

  setUp(() async {
    await ChatHistoryStore.clear();
  });

  group('对话持久化', () {
    test('保存后能完整读回', () async {
      final messages = [
        ChatMessage(role: 'assistant', content: '开场白'),
        ChatMessage(role: 'user', content: '我的问题'),
        ChatMessage(role: 'assistant', content: 'AI 的回答'),
      ];

      await ChatHistoryStore.save(messages);
      final loaded = ChatHistoryStore.load();

      expect(loaded.length, 3);
      expect(loaded[0].role, 'assistant');
      expect(loaded[0].content, '开场白');
      expect(loaded[1].content, '我的问题');
      expect(loaded[2].content, 'AI 的回答');
    });

    test('保留附件名称', () async {
      final messages = [
        ChatMessage(
          role: 'user',
          content: '看看这个文件',
          attachments: ['note.txt', 'data.csv'],
        ),
      ];

      await ChatHistoryStore.save(messages);
      final loaded = ChatHistoryStore.load();

      expect(loaded.first.attachments, ['note.txt', 'data.csv']);
    });

    test('跳过 pending 与错误消息', () async {
      final messages = [
        ChatMessage(role: 'user', content: '正常'),
        ChatMessage(role: 'assistant', content: '', pending: true),
        ChatMessage(role: 'assistant', content: '失败', error: '出错了'),
      ];

      await ChatHistoryStore.save(messages);
      final loaded = ChatHistoryStore.load();

      expect(loaded.length, 1);
      expect(loaded.first.content, '正常');
    });

    test('跳过空内容消息', () async {
      final messages = [
        ChatMessage(role: 'user', content: '   '),
        ChatMessage(role: 'user', content: '有内容'),
      ];

      await ChatHistoryStore.save(messages);
      final loaded = ChatHistoryStore.load();

      expect(loaded.length, 1);
      expect(loaded.first.content, '有内容');
    });

    test('清空后读取为空', () async {
      await ChatHistoryStore.save([
        ChatMessage(role: 'user', content: '消息'),
      ]);
      expect(ChatHistoryStore.load(), isNotEmpty);

      await ChatHistoryStore.clear();
      expect(ChatHistoryStore.load(), isEmpty);
    });

    test('超过上限时保留最近的消息', () async {
      final messages = List.generate(
        ChatHistoryStore.maxMessages + 20,
        (i) => ChatMessage(role: 'user', content: '消息 $i'),
      );

      await ChatHistoryStore.save(messages);
      final loaded = ChatHistoryStore.load();

      expect(loaded.length, ChatHistoryStore.maxMessages);
      // 保留的是最新的一批
      expect(loaded.last.content, '消息 ${ChatHistoryStore.maxMessages + 19}');
    });

    test('空列表保存后读取为空', () async {
      await ChatHistoryStore.save([]);
      expect(ChatHistoryStore.load(), isEmpty);
    });

    test('损坏数据不会崩溃', () async {
      SharedPreferences.setMockInitialValues({
        'ai_chat_messages': '这不是 JSON',
      });
      await StorageManager.initialize();

      expect(ChatHistoryStore.load(), isEmpty);
    });

    test('时间戳可正确往返', () async {
      final time = DateTime(2026, 10, 25, 22, 30, 15);
      await ChatHistoryStore.save([
        ChatMessage(role: 'user', content: '带时间', createdAt: time),
      ]);

      final loaded = ChatHistoryStore.load();
      expect(loaded.first.createdAt, time);
    });

    test('角色卡记录可保存与读取', () async {
      await ChatHistoryStore.saveRoleCard('builtin_mingjing');
      expect(ChatHistoryStore.loadRoleCard(), 'builtin_mingjing');
    });
  });
}
