import 'package:flutter_test/flutter_test.dart';

import 'package:course_helper/utils/ai_response_formatter.dart';

void main() {
  group('JSON 提取', () {
    test('普通文本原样返回', () {
      const raw = '这是一段普通回答，没有 JSON。';
      expect(AiResponseFormatter.toDisplayText(raw), raw);
    });

    test('提取 text 字段', () {
      const raw = '{"text":"这是答案内容"}';
      expect(AiResponseFormatter.toDisplayText(raw), '这是答案内容');
    });

    test('提取 content 字段', () {
      const raw = '{"content":"回答正文"}';
      expect(AiResponseFormatter.toDisplayText(raw), '回答正文');
    });

    test('answers 数组按题目展开', () {
      const raw = '{"answers":['
          '{"index":0,"options":["B"],"explanation":"因为 1+1=2"},'
          '{"index":1,"blanks":["北京"],"explanation":"常识"}'
          ']}';
      final result = AiResponseFormatter.toDisplayText(raw);
      expect(result.contains('第 1 题'), isTrue);
      expect(result.contains('B'), isTrue);
      expect(result.contains('因为 1+1=2'), isTrue);
      expect(result.contains('第 2 题'), isTrue);
      expect(result.contains('北京'), isTrue);
    });

    test('answers 含 text 字段优先使用', () {
      const raw = '{"answers":[{"index":0,"text":"完整解答内容"}]}';
      final result = AiResponseFormatter.toDisplayText(raw);
      expect(result.contains('完整解答内容'), isTrue);
    });

    test('兼容 markdown 代码块', () {
      const raw = '```json\n{"text":"代码块内的答案"}\n```';
      expect(AiResponseFormatter.toDisplayText(raw), '代码块内的答案');
    });

    test('兼容前后多余文字', () {
      const raw = '好的，结果如下：{"text":"答案在这里"} 希望有帮助';
      expect(AiResponseFormatter.toDisplayText(raw), '答案在这里');
    });

    test('嵌套 data 字段', () {
      const raw = '{"data":{"text":"嵌套答案"}}';
      expect(AiResponseFormatter.toDisplayText(raw), '嵌套答案');
    });

    test('OpenAI choices 格式', () {
      const raw = '{"choices":[{"message":{"content":"来自 choices"}}]}';
      expect(AiResponseFormatter.toDisplayText(raw), '来自 choices');
    });

    test('无法识别的 JSON 兜底列出键值', () {
      const raw = '{"foo":"bar","num":42}';
      final result = AiResponseFormatter.toDisplayText(raw);
      expect(result.contains('foo'), isTrue);
      expect(result.contains('bar'), isTrue);
    });

    test('空字符串安全处理', () {
      expect(AiResponseFormatter.toDisplayText(''), '');
    });

    test('非法 JSON 原样返回', () {
      const raw = '{这不是合法 JSON';
      expect(AiResponseFormatter.toDisplayText(raw), raw);
    });

    test('数组格式', () {
      const raw = '["第一条","第二条"]';
      final result = AiResponseFormatter.toDisplayText(raw);
      expect(result.contains('第一条'), isTrue);
      expect(result.contains('第二条'), isTrue);
    });
  });
}
