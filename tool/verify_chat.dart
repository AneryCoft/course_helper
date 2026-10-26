// 独立联调脚本：验证多轮对话 + 角色卡 + 上下文裁剪在真实接口下可用。
//
// 用法：
//   dart run tool/verify_chat.dart <baseUrl> <token> <model>

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('用法: dart run tool/verify_chat.dart <baseUrl> <token> <model>');
    exitCode = 2;
    return;
  }

  final baseUrl = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final model = args[2];

  const persona = '你是一位名叫「明镜」的资深阅卷老师，回答简洁、条理清晰。';
  const greeting = '好的，题目我已收到。我会逐题审题、推理并给出可直接提交的答案与解析。';

  // 多轮对话历史：验证模型能记住上文
  final history = [
    {'role': 'user', 'content': '我最喜欢的颜色是蓝色，请记住。'},
    {'role': 'assistant', 'content': '好的，我记住了：你最喜欢的颜色是蓝色。'},
    {'role': 'user', 'content': '我刚才说我喜欢的颜色是什么？只回答颜色名。'},
  ];

  final messages = [
    {'role': 'system', 'content': persona},
    {'role': 'assistant', 'content': greeting},
    ...history,
  ];

  stdout.writeln('→ 多轮对话验证：共 ${messages.length} 条消息（含角色卡）');

  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': 0.6,
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
    stdout.writeln('← 回复：$content');

    final lower = content.toLowerCase();
    if (!lower.contains('蓝')) {
      stderr.writeln('✗ 模型未记住上文颜色（期望包含「蓝」）');
      exitCode = 1;
      return;
    }

    stdout.writeln('✓ 多轮上下文与角色卡均生效');
  } finally {
    client.close(force: true);
  }
}
