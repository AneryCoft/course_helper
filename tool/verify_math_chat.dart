// 验证对话模式：不返回 JSON，且数学内容使用 LaTeX 规范排版。
//
// 用法：dart run tool/verify_math_chat.dart <baseUrl> <token> <model>

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('用法: dart run tool/verify_math_chat.dart <baseUrl> <token> <model>');
    exitCode = 2;
    return;
  }

  final baseUrl = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final model = args[2];

  // 与 AiService.chatSupplement 保持一致
  const supplement =
      '你正在进行日常对话，请用自然语言直接回答，不要输出 JSON、代码块或字段名。\n'
      '\n【数学排版要求】\n'
      '1. 不要使用计算机写法，改用标准数学表达：\n'
      '   - 分式写成 \\frac{分子}{分母}，例如 \\frac{x+1}{x-2}\n'
      '   - 乘方写成 x^{2}，不要写 x^2 或 x*x\n'
      '   - 根号写成 \\sqrt{x}\n'
      '   - 乘号用 \\times 或 \\cdot，不要用 *\n'
      '   - 小于等于、大于等于写成 \\leq、\\geq\n'
      '2. 行内公式用 \$...\$ 包裹，独立成行的公式用 \$\$...\$\$ 包裹。\n'
      '3. 方程组或分段函数必须使用大括号：\n'
      r'   $$\begin{cases} x + y = 5 \\ 2x - y = 1 \end{cases}$$' '\n'
      '4. 所有 LaTeX 反斜杠必须正确转义，确保能正常渲染。';

  const persona = '你是一位名叫「明镜」的资深阅卷老师，回答简洁、条理清晰。';

  final messages = [
    {'role': 'system', 'content': '$persona\n\n【对话要求】\n$supplement'},
    {'role': 'user', 'content': '请用规范数学格式写出：1) 分式 (x+1)/(x-2) 2) x 的平方 3) 方程组 x+y=5, 2x-y=1'},
  ];

  stdout.writeln('→ 验证对话模式（不应输出 JSON，数学应为 LaTeX）');

  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': 0.4,
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      stderr.writeln('✗ HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final content =
        ((decoded['choices'] as List).first as Map)['message']['content'] as String;
    stdout.writeln('← 回复：\n$content\n');

    var ok = true;

    // 1. 不应是 JSON
    final trimmed = content.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      stderr.writeln('✗ 仍返回 JSON');
      ok = false;
    }

    // 2. 应包含 \frac
    if (!content.contains(r'\frac')) {
      stderr.writeln('✗ 缺少 \\frac 分式');
      ok = false;
    }

    // 3. 应包含 cases 大括号
    if (!content.contains(r'\begin{cases}')) {
      stderr.writeln('✗ 方程组缺少 cases 大括号');
      ok = false;
    }

    // 4. 不应出现计算机写法
    if (RegExp(r'x\^2').hasMatch(content)) {
      stderr.writeln('✗ 仍使用 x^2 写法');
      ok = false;
    }

    if (ok) {
      stdout.writeln('✓ 对话模式与数学排版均符合要求');
    } else {
      exitCode = 1;
    }
  } finally {
    client.close(force: true);
  }
}
