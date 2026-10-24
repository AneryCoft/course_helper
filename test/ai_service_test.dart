import 'package:flutter_test/flutter_test.dart';

import 'package:course_helper/api/ai.dart';

void main() {
  group('AiService.parseAnswers', () {
    test('解析标准 JSON 答案', () {
      const raw = '{"answers":['
          '{"index":0,"options":["B"],"blanks":[],"text":"","explanation":"因为 1+1=2"},'
          '{"index":1,"options":[],"blanks":["北京","上海"],"text":"","explanation":"常识"},'
          '{"index":2,"options":[],"blanks":[],"text":"牛顿第一定律……","explanation":"惯性"}'
          ']}';
      final result = AiService.parseAnswers(raw);

      expect(result.length, 3);
      expect(result[0]!.options, ['B']);
      expect(result[0]!.explanation, '因为 1+1=2');
      expect(result[1]!.blanks, ['北京', '上海']);
      expect(result[2]!.text, startsWith('牛顿第一定律'));
    });

    test('兼容 markdown 代码块与前后多余文字', () {
      const raw = '好的，结果如下：\n```json\n{"answers":[{"index":0,"options":["A","C"]}]}\n```\n希望有帮助';
      final result = AiService.parseAnswers(raw);

      expect(result[0]!.options, ['A', 'C']);
    });

    test('展开合并写法的多选答案', () {
      const raw = '{"answers":[{"index":0,"options":["abd"]}]}';
      final result = AiService.parseAnswers(raw);

      expect(result[0]!.options, ['A', 'B', 'D']);
    });

    test('非法内容抛出 AiException', () {
      expect(() => AiService.parseAnswers('抱歉，我无法回答'), throwsA(isA<AiException>()));
      expect(() => AiService.parseAnswers('{"foo":1}'), throwsA(isA<AiException>()));
    });

    test('index 缺失时按顺序回退', () {
      const raw = '{"answers":[{"options":["A"]},{"options":["B"]}]}';
      final result = AiService.parseAnswers(raw);

      expect(result[0]!.options, ['A']);
      expect(result[1]!.options, ['B']);
    });
  });

  group('配置不应内置敏感信息', () {
    test('源码不含固定服务地址与 Token', () {
      // 默认提示词与系统提示词均不含任何地址、密钥
      for (final text in [
        AiService.defaultPromptTemplate,
        AiService.defaultSystemPrompt,
      ]) {
        expect(RegExp(r'https?://').hasMatch(text), isFalse);
        expect(text.contains('sk-'), isFalse);
      }
    });

    test('未配置时不会误判为可用', () {
      // 测试环境未初始化 SharedPreferences，默认值为空
      expect(AiService.isConfigured, isFalse);
    });

    test('提示词模板包含题目占位符', () {
      expect(AiService.defaultPromptTemplate.contains('{{questions}}'), isTrue);
    });
  });
}
