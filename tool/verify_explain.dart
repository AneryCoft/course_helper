// 验证 AI 讲解：下载一张幻灯片图片并让视觉模型讲解。
//
// 用法：dart run tool/verify_explain.dart <baseUrl> <token> <model> [imageUrl]

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 生成一张 64x64 的测试幻灯片（白底 + 红色方块 + 一条横线）
Uint8List makeSlidePng({int size = 64}) {
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 2)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());

  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0);
    for (var x = 0; x < size; x++) {
      final inBox = x > 12 && x < size - 12 && y > 12 && y < size ~/ 2;
      if (inBox) {
        raw.add([220, 40, 40]);
      } else {
        raw.add([255, 255, 255]);
      }
    }
  }
  _chunk(out, 'IDAT', _zlib(raw.toBytes()));
  _chunk(out, 'IEND', const []);
  return out.toBytes();
}

Uint8List _zlib(Uint8List raw) {
  final out = BytesBuilder();
  out.addByte(0x78);
  out.addByte(0x01);
  const maxBlock = 65535;
  var offset = 0;
  while (offset < raw.length) {
    final len = (raw.length - offset).clamp(0, maxBlock);
    final isLast = offset + len >= raw.length;
    out.addByte(isLast ? 1 : 0);
    out.addByte(len & 0xFF);
    out.addByte((len >> 8) & 0xFF);
    out.addByte((~len) & 0xFF);
    out.addByte(((~len) >> 8) & 0xFF);
    out.add(raw.sublist(offset, offset + len));
    offset += len;
  }
  var a = 1, b = 0;
  for (final byte in raw) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final adler = ((b << 16) | a) & 0xFFFFFFFF;
  out.addByte((adler >> 24) & 0xFF);
  out.addByte((adler >> 16) & 0xFF);
  out.addByte((adler >> 8) & 0xFF);
  out.addByte(adler & 0xFF);
  return out.toBytes();
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final payload = <int>[...ascii.encode(type), ...data];
  out.add(payload);
  final crc = ByteData(4)..setUint32(0, _crc32(payload));
  out.add(crc.buffer.asUint8List());
}

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
        '用法: dart run tool/verify_explain.dart <baseUrl> <token> <model> [imageUrl]');
    exitCode = 2;
    return;
  }

  final baseUrl = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final model = args[2];
  final imageUrl = args.length > 3 ? args[3] : null;

  Uint8List bytes;
  if (imageUrl != null) {
    stdout.writeln('→ 下载幻灯片：$imageUrl');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(imageUrl));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        stderr.writeln('✗ 下载失败 HTTP ${resp.statusCode}');
        exitCode = 1;
        return;
      }
      final chunks = await resp.toList();
      bytes = Uint8List.fromList(chunks.expand((c) => c).toList());
    } finally {
      client.close(force: true);
    }
  } else {
    bytes = makeSlidePng();
    stdout.writeln('→ 使用内置测试幻灯片：64x64，${bytes.length} 字节');
  }

  const systemPrompt = '你是一位擅长课堂讲解的老师。请根据幻灯片内容，'
      '用中文清晰地讲解这一页的知识点。要求：\n'
      '1. 先概括这一页讲了什么（一句话）；\n'
      '2. 再逐点展开讲解；\n'
      '3. 如果有公式，用 \$...\$ 规范书写；\n'
      '4. 如果页面信息不足，如实说明，不要编造；\n'
      '5. 最后用一句话总结重点。';

  final messages = [
    {'role': 'system', 'content': systemPrompt},
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': '课程：测试课程\n这是第 1 页，共 10 页。\n\n请讲解这一页的内容。'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,${base64Encode(bytes)}'},
        },
      ],
    },
  ];

  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': 0.5,
    }));

    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();

    if (resp.statusCode != 200) {
      stderr.writeln('✗ HTTP ${resp.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final message = ((decoded['choices'] as List).first as Map)['message'] as Map;
    final content = (message['content'] ?? '').toString();
    final reasoning =
        (message['reasoning_content'] ?? message['reasoning'] ?? '').toString();

    stdout.writeln('← 讲解内容：\n$content\n');
    if (reasoning.isNotEmpty) {
      stdout.writeln('（思考过程 ${reasoning.length} 字）');
    }

    if (content.trim().isEmpty) {
      stderr.writeln('✗ 讲解内容为空');
      exitCode = 1;
      return;
    }
    stdout.writeln('✓ AI 讲解链路可用');
  } finally {
    client.close(force: true);
  }
}
