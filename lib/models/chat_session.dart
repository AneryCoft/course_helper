import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

/// 推理强度
enum ReasoningEffort {
  /// 快速响应，思考最少
  low,

  /// 平衡
  medium,

  /// 深入推理，耗时最长
  high;

  String get label {
    switch (this) {
      case ReasoningEffort.low:
        return '低';
      case ReasoningEffort.medium:
        return '中';
      case ReasoningEffort.high:
        return '高';
    }
  }

  /// 发送给接口的取值
  String get apiValue => name;

  static ReasoningEffort fromName(String? value) {
    switch (value) {
      case 'medium':
        return ReasoningEffort.medium;
      case 'high':
        return ReasoningEffort.high;
      default:
        return ReasoningEffort.low;
    }
  }
}

/// 对话中的一条消息
class ChatMessage {
  /// 'system' / 'user' / 'assistant'
  final String role;
  final String content;

  /// 附件名称列表（仅用于界面展示，实际内容已拼进 content）
  final List<String> attachments;

  /// 本条消息附带的图片（base64 + mime），会以多模态格式发送
  final List<ChatAttachment> images;

  /// 深度思考过程（仅 assistant 消息，模型支持时才有）
  final String reasoning;

  final DateTime createdAt;

  /// 是否正在等待回复（用于显示打字动画）
  final bool pending;

  /// 请求失败时的错误信息
  final String? error;

  ChatMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
    this.images = const [],
    this.reasoning = '',
    DateTime? createdAt,
    this.pending = false,
    this.error,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';

  /// 是否有可展示的思考过程
  bool get hasReasoning => reasoning.trim().isNotEmpty;

  ChatMessage copyWith({
    String? role,
    String? content,
    List<String>? attachments,
    List<ChatAttachment>? images,
    String? reasoning,
    bool? pending,
    String? error,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      attachments: attachments ?? this.attachments,
      images: images ?? this.images,
      reasoning: reasoning ?? this.reasoning,
      createdAt: createdAt,
      pending: pending ?? this.pending,
      error: error ?? this.error,
    );
  }

  /// 转为接口消息体
  ///
  /// 含图片时使用 OpenAI 兼容的多模态数组格式：
  /// `content: [{type: text}, {type: image_url, image_url: {url}}]`
  dynamic toApiMessage() {
    if (images.isEmpty) {
      return {'role': role, 'content': content};
    }

    final parts = <Map<String, dynamic>>[];

    // 文本块始终放在最前（即使为空也要补一句），部分服务端要求首块为 text
    if (content.trim().isNotEmpty) {
      parts.add({'type': 'text', 'text': content});
    } else {
      parts.add({'type': 'text', 'text': '请分析这张图片。'});
    }

    for (final img in images) {
      if (!img.isImage) continue;
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${img.mimeType ?? "image/jpeg"};base64,${img.base64Data}'},
      });
    }

    return {'role': role, 'content': parts};
  }
}

/// 上下文窗口管理
///
/// 以「估算 token」为单位控制历史消息长度。中文约 1 字 ≈ 1 token，
/// 英文约 4 字符 ≈ 1 token，这里采用保守估算避免超出模型限制。
class ContextWindow {
  /// 用户设置的上下文大小（token）
  final int limit;

  /// 预留给模型回复的 token
  static const int reservedForReply = 512;

  const ContextWindow(this.limit);

  /// 估算一段文本的 token 数
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        cjk++;
      } else if (rune >= 0x3000 && rune <= 0x303F) {
        cjk++;
      } else {
        other++;
      }
    }
    // 中文 1 字 ≈ 1 token，其他字符 4 个 ≈ 1 token
    return cjk + (other / 4).ceil();
  }

  static int estimateMessages(Iterable<Map<String, dynamic>> messages) {
    var total = 0;
    for (final m in messages) {
      // 每条消息有约 4 token 的结构开销
      total += estimateMessageContent(m['content']) + 4;
    }
    return total;
  }

  /// 估算消息 content 的 token 数（兼容纯文本与多模态数组）
  static int estimateMessageContent(dynamic content) {
    if (content == null) return 0;
    if (content is String) return estimateTokens(content);
    if (content is List) {
      var total = 0;
      for (final part in content) {
        if (part is! Map) continue;
        if (part['type'] == 'text') {
          total += estimateTokens((part['text'] ?? '').toString());
        } else if (part['type'] == 'image_url') {
          // 图片按视觉 token 粗略估算，常见 85~1600，取 800
          total += 800;
        }
      }
      return total;
    }
    return 0;
  }

  /// 按上下文上限裁剪历史消息
  ///
  /// [systemMessages] 始终保留在最前；[history] 从新到旧累积，超出上限即停止。
  List<Map<String, dynamic>> build({
    required List<Map<String, dynamic>> systemMessages,
    required List<ChatMessage> history,
  }) {
    final budget = (limit - reservedForReply).clamp(256, limit);
    var used = estimateMessages(systemMessages);

    final selected = <Map<String, dynamic>>[];
    // 从最新消息往前累积
    for (var i = history.length - 1; i >= 0; i--) {
      final msg = history[i];
      if (msg.pending || msg.error != null) continue;
      if (msg.content.trim().isEmpty && msg.images.isEmpty) continue;

      final api = msg.toApiMessage() as Map<String, dynamic>;
      final cost = estimateMessageContent(api['content']) + 4;
      if (used + cost > budget) break;
      used += cost;
      selected.insert(0, api);
    }

    return [...systemMessages, ...selected];
  }

  /// 已使用的 token 估算
  int usedTokens({
    required List<Map<String, dynamic>> systemMessages,
    required List<ChatMessage> history,
  }) {
    final messages = build(systemMessages: systemMessages, history: history);
    return estimateMessages(messages);
  }
}

/// 附件类型
enum AttachmentKind {
  /// 文本文件（内容已提取到 [ChatAttachment.content]）
  text,

  /// 图片（拍照或选图，以 base64 发送给视觉模型）
  image,

  /// 其他二进制文件（仅展示大小）
  binary,
}

/// 可插入对话的文件
class ChatAttachment {
  final String name;

  /// 已提取的文本内容（图片类型时为空）
  final String content;

  /// 原始字节大小
  final int size;

  /// 是否因过大而被截断
  final bool truncated;

  /// 附件类型
  final AttachmentKind kind;

  /// 图片的 base64 数据（不含 data: 前缀），仅 [AttachmentKind.image] 有效
  final String? base64Data;

  /// 图片的 MIME 类型，如 image/jpeg
  final String? mimeType;

  const ChatAttachment({
    required this.name,
    required this.content,
    required this.size,
    this.truncated = false,
    this.kind = AttachmentKind.text,
    this.base64Data,
    this.mimeType,
  });

  /// 是否为图片附件
  bool get isImage => kind == AttachmentKind.image && base64Data != null;

  /// 拼接到消息中的文本块
  String toPromptBlock() {
    final buffer = StringBuffer()
      ..writeln('【附件：$name】')
      ..write(content);
    if (truncated) {
      buffer.writeln('\n（注：文件较大，以上内容已截断）');
    }
    return buffer.toString();
  }
}

/// 文件读取与文本提取
class FileExtractor {
  FileExtractor._();

  /// 单个文件最多读取的字符数（约 8K token）
  static const int maxChars = 32000;

  /// 支持直接读取文本的扩展名
  static const Set<String> textExtensions = {
    '.txt', '.md', '.markdown', '.json', '.csv', '.log', '.xml', '.yaml',
    '.yml', '.ini', '.conf', '.html', '.htm', '.css', '.js', '.ts', '.dart',
    '.py', '.java', '.kt', '.c', '.h', '.cpp', '.hpp', '.cs', '.go', '.rs',
    '.php', '.rb', '.swift', '.sql', '.sh', '.bat', '.ps1', '.toml',
  };

  /// 二进制文件，仅提示大小不做解析
  static const Set<String> binaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico',
    '.mp3', '.mp4', '.wav', '.avi', '.mov', '.mkv', '.flac',
    '.zip', '.rar', '.7z', '.tar', '.gz',
    '.apk', '.exe', '.dll', '.so', '.jar', '.class',
    '.ttf', '.otf', '.woff', '.pdf', '.doc', '.docx', '.xls', '.xlsx',
    '.ppt', '.pptx',
  };

  /// 图片扩展名（选择文件时按图片处理）
  static const Set<String> imageExtensions = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp',
  };

  /// 单张图片最大字节数（约 4MB，超过则压缩）
  static const int maxImageBytes = 4 * 1024 * 1024;

  /// 拍照：调用系统相机，拍完直接读入内存，不保存到相册
  ///
  /// image_picker 的相机结果会放在应用缓存目录，这里读取后立即删除临时文件，
  /// 因此照片不会留在设备相册或长期占用存储。
  static Future<ChatAttachment?> capturePhoto() async {
    final picker = ImagePicker();
    final XFile? shot = await picker.pickImage(
      source: ImageSource.camera,
      // 限制尺寸与质量，控制 base64 体积与 token 消耗
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (shot == null) return null;

    try {
      final bytes = await shot.readAsBytes();
      final mime = _mimeFromPath(shot.path);

      // 若压缩后仍过大，直接拒绝，避免请求体爆掉
      if (bytes.length > maxImageBytes) {
        throw Exception(
          '图片过大（${_formatSize(bytes.length)}），请降低相机分辨率后重试',
        );
      }

      return ChatAttachment(
        name: '拍照_${DateTime.now().millisecondsSinceEpoch}.jpg',
        content: '',
        size: bytes.length,
        kind: AttachmentKind.image,
        base64Data: base64Encode(bytes),
        mimeType: mime,
      );
    } finally {
      // 删除 image_picker 产生的临时文件，确保照片不落地
      try {
        final f = File(shot.path);
        if (await f.exists() && shot.path.contains('cache')) {
          await f.delete();
        }
      } catch (_) {
        // 删除失败不影响使用
      }
    }
  }

  static String _mimeFromPath(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }

  /// 选择文件并提取文本
  static Future<List<ChatAttachment>> pickFiles() async {
    // file_picker 13.x：pickFiles 为静态方法，直接返回 List<PlatformFile>
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择要插入的文件',
      type: FileType.any,
    );
    if (files.isEmpty) return const [];

    final attachments = <ChatAttachment>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      try {
        final attachment = await readFile(path, displayName: file.name);
        if (attachment != null) attachments.add(attachment);
      } catch (e) {
        logger.e('读取文件失败: $path $e');
      }
    }
    return attachments;
  }

  /// 读取单个文件
  static Future<ChatAttachment?> readFile(
    String path, {
    String? displayName,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final size = await file.length();
    final name = displayName ?? p.basename(path);
    final ext = p.extension(path).toLowerCase();

    // 图片：读取为 base64，交给视觉模型
    if (imageExtensions.contains(ext)) {
      if (size > maxImageBytes) {
        return ChatAttachment(
          name: name,
          content: '',
          size: size,
          kind: AttachmentKind.image,
          base64Data: null,
          mimeType: _mimeFromPath(path),
        );
      }
      try {
        final bytes = await file.readAsBytes();
        return ChatAttachment(
          name: name,
          content: '',
          size: size,
          kind: AttachmentKind.image,
          base64Data: base64Encode(bytes),
          mimeType: _mimeFromPath(path),
        );
      } catch (e) {
        logger.e('读取图片失败: $path $e');
        return null;
      }
    }

    // 其他二进制：只给出提示
    if (binaryExtensions.contains(ext)) {
      return ChatAttachment(
        name: name,
        content: '（该文件为二进制格式，无法直接解析内容，大小 ${_formatSize(size)}）',
        size: size,
        kind: AttachmentKind.binary,
      );
    }

    // 文本：尝试 UTF-8 解码，失败时回退 latin1
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      return null;
    }

    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = latin1.decode(bytes, allowInvalid: true);
    }

    final truncated = text.length > maxChars;
    final content = truncated ? text.substring(0, maxChars) : text;

    return ChatAttachment(
      name: name,
      content: content,
      size: size,
      truncated: truncated,
      kind: AttachmentKind.text,
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
