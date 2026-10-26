import 'dart:convert';

import '../models/chat_session.dart';
import '../utils/storage.dart';

/// 对话记录的本地持久化
///
/// 让对话在切换页面、甚至重启 App 后依然保留，只有用户主动清空才删除。
/// 只保存文本与附件名称，不保存图片 base64（体积过大且无复用价值）。
class ChatHistoryStore {
  ChatHistoryStore._();

  static const String _messagesKey = 'ai_chat_messages';
  static const String _roleCardKey = 'ai_chat_role_card';

  /// 最多保存的消息条数，避免无限增长
  static const int maxMessages = 200;

  /// 保存对话
  static Future<void> save(List<ChatMessage> messages) async {
    try {
      // 只保留有效消息，且限制总量
      final valid = messages
          .where((m) => !m.pending && m.error == null && m.content.trim().isNotEmpty)
          .toList();
      final sliced = valid.length > maxMessages
          ? valid.sublist(valid.length - maxMessages)
          : valid;

      final payload = sliced
          .map((m) => {
                'role': m.role,
                'content': m.content,
                'attachments': m.attachments,
                'reasoning': m.reasoning,
                'createdAt': m.createdAt.toIso8601String(),
              })
          .toList();

      await StorageManager.prefs.setString(_messagesKey, jsonEncode(payload));
    } catch (_) {
      // 保存失败不影响使用
    }
  }

  /// 读取对话
  static List<ChatMessage> load() {
    try {
      final raw = StorageManager.prefs.getString(_messagesKey);
      if (raw == null || raw.trim().isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final messages = <ChatMessage>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final role = item['role']?.toString() ?? '';
        final content = item['content']?.toString() ?? '';
        if (role.isEmpty || content.trim().isEmpty) continue;

        final attachments = <String>[];
        final rawAttachments = item['attachments'];
        if (rawAttachments is List) {
          for (final a in rawAttachments) {
            final text = a?.toString().trim() ?? '';
            if (text.isNotEmpty) attachments.add(text);
          }
        }

        DateTime createdAt;
        try {
          createdAt =
              DateTime.parse(item['createdAt']?.toString() ?? '') ;
        } catch (_) {
          createdAt = DateTime.now();
        }

        messages.add(ChatMessage(
          role: role,
          content: content,
          attachments: attachments,
          reasoning: item['reasoning']?.toString() ?? '',
          createdAt: createdAt,
        ));
      }
      return messages;
    } catch (_) {
      return const [];
    }
  }

  /// 清空对话
  static Future<void> clear() async {
    await StorageManager.prefs.remove(_messagesKey);
  }

  /// 记录对话使用的角色卡，重启后若角色卡仍存在则沿用
  static Future<void> saveRoleCard(String cardId) async {
    await StorageManager.prefs.setString(_roleCardKey, cardId);
  }

  static String? loadRoleCard() =>
      StorageManager.prefs.getString(_roleCardKey);
}
