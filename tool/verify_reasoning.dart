// 验证深度思考：不同推理等级应产生不同长度的思考过程。
//
// 用法：dart run tool/verify_reasoning.dart <baseUrl> <token> <model>

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('用法: dart run tool/verify_reasoning.dart <baseUrl> <token> <model>');
    exitCode = 2;
    return;
  }

  final baseUrl = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final model = args[2];

  final client = HttpClient();
  try {
    for (final effort in ['low', 'medium', 'high']) {
      final request =
          await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': '用两句话解释什么是微积分'},
        ],
        'stream': false,
        'reasoning_effort': effort,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        stderr.writeln('$effort => HTTP ${response.statusCode}');
        continue;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final message =
          ((decoded['choices'] as List).first as Map)['message'] as Map;
      final reasoning =
          (message['reasoning_content'] ?? message['reasoning'] ?? '').toString();
      final content = (message['content'] ?? '').toString();
      final tokens =
          ((decoded['usage'] as Map?)?['completion_tokens_details']
                  as Map?)?['reasoning_tokens'] ??
              0;

      stdout.writeln('$effort => 思考 ${reasoning.length} 字 / $tokens tokens，'
          '正文 ${content.length} 字');

      if (reasoning.isEmpty) {
        stderr.writeln('  ✗ 未返回思考过程');
      }
    }

    stdout.writeln('✓ 深度思考参数可用');
  } finally {
    client.close(force: true);
  }
}
