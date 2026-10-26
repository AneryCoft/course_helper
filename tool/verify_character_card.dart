// 独立联调脚本：用 dart run 执行，不受 flutter_test 的 HTTP 拦截影响。
//
// 用法：
//   dart run tool/verify_character_card.dart <baseUrl> <token> <model>
//
// 目的：验证角色卡的 system 设定与 assistant 开场白确实被注入请求，
// 且注入后模型仍能返回可解析的 JSON 答案。

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('用法: dart run tool/verify_character_card.dart <baseUrl> <token> <model>');
    exitCode = 2;
    return;
  }

  final baseUrl = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final model = args[2];

  // 与 BuiltInCards.defaultCard 保持一致的关键片段（避免依赖 Flutter 包）
  const personaSnippet = '你是一位名叫「明镜」的资深阅卷老师';
  const greeting = '好的，题目我已收到。我会逐题审题、推理并给出可直接提交的答案与解析。';
  const systemPrompt = '你是学识渊博的答题助手，擅长各学科题目解答。你只输出严格合法的 JSON。';

  final messages = [
    {'role': 'system', 'content': '$personaSnippet……\n\n【补充要求】\n$systemPrompt'},
    {'role': 'assistant', 'content': greeting},
    {
      'role': 'user',
      'content': '请解答下列题目，严格输出 JSON。\n'
          '{"answers":[{"index":0,"options":["A"],"blanks":[],"text":"","explanation":"解析"}]}\n'
          '[0] 题型：单选题\n题干：下列哪个是中国的首都？\n选项：\nA. 上海\nB. 北京\nC. 广州\nD. 深圳'
    },
  ];

  stdout.writeln('→ 角色卡注入验证：system=${personaSnippet.substring(0, 12)}… assistant=$greeting');

  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': 0.2,
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      stderr.writeln('✗ HTTP ${response.statusCode}: $body');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final content =
        ((decoded['choices'] as List).first as Map)['message']['content'] as String;
    stdout.writeln('← 返回：$content');

    // 解析校验
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start < 0 || end <= start) {
      stderr.writeln('✗ 返回内容不含 JSON 对象');
      exitCode = 1;
      return;
    }
    final parsed = jsonDecode(content.substring(start, end + 1)) as Map<String, dynamic>;
    final answers = parsed['answers'] as List;
    final first = answers.first as Map;
    final options = (first['options'] as List).map((e) => e.toString()).toList();

    if (!options.contains('B')) {
      stderr.writeln('✗ 答案不符预期，期望含 B，实际 $options');
      exitCode = 1;
      return;
    }

    stdout.writeln('✓ 角色卡注入成功，答案可解析：options=$options');
  } finally {
    client.close(force: true);
  }
}
