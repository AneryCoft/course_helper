import 'package:flutter_test/flutter_test.dart';

import 'package:course_helper/models/chat_session.dart';

void main() {
  group('token 估算', () {
    test('中文按字数估算', () {
      expect(ContextWindow.estimateTokens('你好世界'), 4);
    });

    test('英文按 4 字符估算', () {
      expect(ContextWindow.estimateTokens('abcd'), 1);
      expect(ContextWindow.estimateTokens('abcdefgh'), 2);
    });

    test('中英混合', () {
      // 4 个中文 + 8 个英文字符 = 4 + 2
      expect(ContextWindow.estimateTokens('你好世界abcdefgh'), 6);
    });

    test('空串为 0', () {
      expect(ContextWindow.estimateTokens(''), 0);
    });

    test('消息列表含结构开销', () {
      final messages = [
        {'role': 'user', 'content': '你好'},
      ];
      expect(ContextWindow.estimateMessages(messages), 2 + 4);
    });
  });

  group('上下文裁剪', () {
    const system = [
      {'role': 'system', 'content': '你是助手'},
    ];

    List<ChatMessage> makeHistory(int count, {int charsPerMsg = 100}) {
      return List.generate(
        count,
        (i) => ChatMessage(
          role: i.isEven ? 'user' : 'assistant',
          content: '字' * charsPerMsg,
        ),
      );
    }

    test('小上下文只保留最近的消息', () {
      final window = ContextWindow(1024);
      final history = makeHistory(20, charsPerMsg: 100);
      final built = window.build(
        systemMessages: system,
        history: history,
      );

      // system 始终在首位
      expect(built.first['role'], 'system');
      // 未超出预算
      expect(ContextWindow.estimateMessages(built), lessThanOrEqualTo(1024));
      // 保留了尾部消息，丢弃了早期消息
      expect(built.length, lessThan(history.length + 1));
      expect(built.length, greaterThan(1));
    });

    test('大上下文可容纳全部消息', () {
      final window = ContextWindow(65536);
      final history = makeHistory(5, charsPerMsg: 20);
      final built = window.build(
        systemMessages: system,
        history: history,
      );
      expect(built.length, history.length + 1);
    });

    test('跳过 pending 与错误消息', () {
      final window = ContextWindow(65536);
      final history = [
        ChatMessage(role: 'user', content: '正常消息'),
        ChatMessage(role: 'assistant', content: '', pending: true),
        ChatMessage(role: 'assistant', content: '失败', error: '出错了'),
        ChatMessage(role: 'user', content: '另一条'),
      ];
      final built = window.build(systemMessages: system, history: history);

      expect(built.length, 3); // system + 2 条正常消息
      expect(built.any((m) => m['content'] == ''), isFalse);
      expect(built.any((m) => m['content'] == '失败'), isFalse);
    });

    test('跳过空内容消息', () {
      final window = ContextWindow(65536);
      final history = [
        ChatMessage(role: 'user', content: '   '),
        ChatMessage(role: 'user', content: '有内容'),
      ];
      final built = window.build(systemMessages: system, history: history);
      expect(built.length, 2);
    });

    test('单条超长消息不会导致崩溃', () {
      final window = ContextWindow(1024);
      final history = [
        ChatMessage(role: 'user', content: '字' * 5000),
      ];
      final built = window.build(systemMessages: system, history: history);
      // 超长消息被排除，只剩 system
      expect(built.length, 1);
    });

    test('裁剪结果保持时间顺序', () {
      final window = ContextWindow(2048);
      final history = [
        ChatMessage(role: 'user', content: '第一条'),
        ChatMessage(role: 'assistant', content: '第二条'),
        ChatMessage(role: 'user', content: '第三条'),
      ];
      final built = window.build(systemMessages: system, history: history);
      final contents = built.skip(1).map((m) => m['content']).toList();
      expect(contents, ['第一条', '第二条', '第三条']);
    });
  });

  group('ChatMessage', () {
    test('toApiMessage 只保留 role 与 content', () {
      final msg = ChatMessage(
        role: 'user',
        content: '内容',
        attachments: ['a.txt'],
      );
      expect(msg.toApiMessage(), {'role': 'user', 'content': '内容'});
    });

    test('copyWith 保留创建时间', () {
      final msg = ChatMessage(role: 'assistant', content: 'x');
      final copy = msg.copyWith(content: 'y', pending: false);
      expect(copy.createdAt, msg.createdAt);
      expect(copy.content, 'y');
    });

    test('角色判断', () {
      expect(ChatMessage(role: 'user', content: '').isUser, isTrue);
      expect(ChatMessage(role: 'assistant', content: '').isAssistant, isTrue);
      expect(ChatMessage(role: 'system', content: '').isSystem, isTrue);
    });
  });

  group('ChatAttachment', () {
    test('拼接到提示词', () {
      const a = ChatAttachment(name: 'note.txt', content: '文件内容', size: 10);
      final block = a.toPromptBlock();
      expect(block.contains('note.txt'), isTrue);
      expect(block.contains('文件内容'), isTrue);
      expect(block.contains('已截断'), isFalse);
    });

    test('截断时附加说明', () {
      const a = ChatAttachment(
        name: 'big.txt',
        content: 'x',
        size: 999999,
        truncated: true,
      );
      expect(a.toPromptBlock().contains('已截断'), isTrue);
    });

    test('默认类型为文本', () {
      const a = ChatAttachment(name: 'a.txt', content: 'x', size: 1);
      expect(a.kind, AttachmentKind.text);
      expect(a.isImage, isFalse);
    });

    test('图片附件识别', () {
      const a = ChatAttachment(
        name: 'photo.jpg',
        content: '',
        size: 100,
        kind: AttachmentKind.image,
        base64Data: 'AAAA',
        mimeType: 'image/jpeg',
      );
      expect(a.isImage, isTrue);
    });

    test('图片缺少 base64 时不视为有效图片', () {
      const a = ChatAttachment(
        name: 'big.jpg',
        content: '',
        size: 99999999,
        kind: AttachmentKind.image,
      );
      expect(a.isImage, isFalse);
    });
  });

  group('多模态消息', () {
    test('纯文本消息保持字符串 content', () {
      final msg = ChatMessage(role: 'user', content: '你好');
      final api = msg.toApiMessage() as Map<String, dynamic>;
      expect(api['content'], '你好');
    });

    test('含图片时生成多模态数组', () {
      final msg = ChatMessage(
        role: 'user',
        content: '这是什么？',
        images: const [
          ChatAttachment(
            name: 'p.jpg',
            content: '',
            size: 10,
            kind: AttachmentKind.image,
            base64Data: 'QUJD',
            mimeType: 'image/jpeg',
          ),
        ],
      );
      final api = msg.toApiMessage() as Map<String, dynamic>;
      final content = api['content'] as List;
      expect(content.length, 2);
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], '这是什么？');
      expect(content[1]['type'], 'image_url');
      expect(
        content[1]['image_url']['url'],
        'data:image/jpeg;base64,QUJD',
      );
    });

    test('只有图片时补充默认提示文本', () {
      final msg = ChatMessage(
        role: 'user',
        content: '',
        images: const [
          ChatAttachment(
            name: 'p.jpg',
            content: '',
            size: 10,
            kind: AttachmentKind.image,
            base64Data: 'QUJD',
            mimeType: 'image/png',
          ),
        ],
      );
      final api = msg.toApiMessage() as Map<String, dynamic>;
      final content = api['content'] as List;
      expect(content.first['type'], 'text');
      expect(content.first['text'].toString().isNotEmpty, isTrue);
    });

    test('多模态消息 token 估算包含图片开销', () {
      final textOnly = ChatMessage(role: 'user', content: '看图');
      final withImage = ChatMessage(
        role: 'user',
        content: '看图',
        images: const [
          ChatAttachment(
            name: 'p.jpg',
            content: '',
            size: 10,
            kind: AttachmentKind.image,
            base64Data: 'QUJD',
            mimeType: 'image/jpeg',
          ),
        ],
      );
      final a = ContextWindow.estimateMessageContent(textOnly.toApiMessage()['content']);
      final b = ContextWindow.estimateMessageContent(withImage.toApiMessage()['content']);
      expect(b, greaterThan(a));
      expect(b, greaterThanOrEqualTo(800));
    });

    test('只有图片的消息不会被上下文裁剪丢弃', () {
      final window = ContextWindow(65536);
      final history = [
        ChatMessage(
          role: 'user',
          content: '',
          images: const [
            ChatAttachment(
              name: 'p.jpg',
              content: '',
              size: 10,
              kind: AttachmentKind.image,
              base64Data: 'QUJD',
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      ];
      final built = window.build(
        systemMessages: const [
          {'role': 'system', 'content': '你是助手'},
        ],
        history: history,
      );
      expect(built.length, 2);
    });
  });
}
