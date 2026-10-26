import 'dart:convert';

/// 把 AI 返回的原始文本整理为可直接展示的内容
///
/// 有些模型（尤其是被系统提示词要求「只输出 JSON」时）会把答案包成 JSON。
/// 这里在展示前做一层提取：能解析出可读文本就展开，否则原样返回。
class AiResponseFormatter {
  AiResponseFormatter._();

  /// 主入口：把原始回复转换为人类可读文本
  static String toDisplayText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;

    final decoded = _tryDecodeJson(trimmed);
    if (decoded == null) return raw;

    final extracted = _extractFromJson(decoded);
    return extracted == null || extracted.trim().isEmpty ? raw : extracted.trim();
  }

  /// 尝试解析 JSON（兼容 ```json 代码块与前后多余文字）
  static dynamic _tryDecodeJson(String text) {
    var body = text;

    if (body.startsWith('```')) {
      body = body.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      body = body.replaceFirst(RegExp(r'\s*```$'), '');
      body = body.trim();
    }

    final direct = _decode(body);
    if (direct != null) return direct;

    // 截取首个 { 或 [ 到末尾对应符号
    for (final pair in [('{', '}'), ('[', ']')]) {
      final start = body.indexOf(pair.$1);
      final end = body.lastIndexOf(pair.$2);
      if (start >= 0 && end > start) {
        final sliced = _decode(body.substring(start, end + 1));
        if (sliced != null) return sliced;
      }
    }
    return null;
  }

  static dynamic _decode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// 从 JSON 结构中提取可读文本
  static String? _extractFromJson(dynamic data) {
    if (data is String) return data;
    if (data is List) return _extractFromList(data);
    if (data is! Map) return null;

    final map = data.map((k, v) => MapEntry(k.toString(), v));

    // 1. 常见单字段答案
    for (final key in ['text', 'content', 'answer', 'response', 'output', 'message']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }

    // 2. answers 数组（答题场景）
    final answers = map['answers'];
    if (answers is List && answers.isNotEmpty) {
      final buffer = StringBuffer();
      for (var i = 0; i < answers.length; i++) {
        final item = answers[i];
        final label = _labelOf(item, i);
        final text = _textOf(item);
        if (text == null || text.isEmpty) continue;
        buffer.writeln('$label$text');
        final explanation = _explanationOf(item);
        if (explanation != null && explanation.isNotEmpty) {
          buffer.writeln('解析：$explanation');
        }
        if (i < answers.length - 1) buffer.writeln();
      }
      if (buffer.toString().trim().isNotEmpty) return buffer.toString();
    }

    // 3. choices 数组（OpenAI 风格）
    final choices = map['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final msg = first['message'];
        if (msg is Map && msg['content'] is String) {
          return msg['content'] as String;
        }
        if (first['text'] is String) return first['text'] as String;
      }
    }

    // 4. 嵌套 data/result
    for (final key in ['data', 'result']) {
      final nested = map[key];
      if (nested != null) {
        final extracted = _extractFromJson(nested);
        if (extracted != null && extracted.trim().isNotEmpty) return extracted;
      }
    }

    // 5. 兜底：把所有字符串值按 key: value 列出
    final buffer = StringBuffer();
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        buffer.writeln('${entry.key}：${value.trim()}');
      } else if (value is num) {
        buffer.writeln('${entry.key}：$value');
      }
    }
    return buffer.toString().trim().isEmpty ? null : buffer.toString();
  }

  static String? _extractFromList(List list) {
    final buffer = StringBuffer();
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is String) {
        buffer.writeln(item);
      } else if (item is Map) {
        final text = _textOf(item);
        if (text != null && text.isNotEmpty) {
          buffer.writeln('${_labelOf(item, i)}$text');
        }
      }
    }
    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  /// 取条目标签，如「第 1 题」「(1)」
  static String _labelOf(dynamic item, int index) {
    if (item is Map) {
      final label = item['label'] ?? item['index'] ?? item['question'];
      if (label != null) {
        final text = label.toString().trim();
        if (text.isNotEmpty) {
          // 纯数字下标转成「第 N 题」
          final asInt = int.tryParse(text);
          if (asInt != null) return '第 ${asInt + 1} 题\n';
          return '$text\n';
        }
      }
    }
    return '第 ${index + 1} 题\n';
  }

  static String? _textOf(dynamic item) {
    if (item is String) return item;
    if (item is! Map) return null;
    for (final key in ['text', 'content', 'answer']) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    // 选择题：options 数组
    final options = item['options'];
    if (options is List && options.isNotEmpty) {
      return options.map((e) => e.toString()).join('、');
    }
    final blanks = item['blanks'];
    if (blanks is List && blanks.isNotEmpty) {
      return blanks.map((e) => e.toString()).join('；');
    }
    return null;
  }

  static String? _explanationOf(dynamic item) {
    if (item is! Map) return null;
    final value = item['explanation'] ?? item['analysis'] ?? item['reason'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
}
