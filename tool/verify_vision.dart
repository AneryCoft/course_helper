// 生成一张 64x64 的真实 PNG（红底 + 白色方块），用于视觉接口联调。
// 不依赖任何图像库，直接手写 PNG 结构（IHDR + IDAT + IEND，zlib 存储块）。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 构造未压缩的 zlib 流（deflate stored blocks），避免引入 archive 依赖
Uint8List _zlibStore(Uint8List raw) {
  final out = BytesBuilder();
  out.addByte(0x78); // zlib header
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

  // adler32
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

void _writeChunk(BytesBuilder out, String type, List<int> data) {
  final length = ByteData(4)..setUint32(0, data.length);
  out.add(length.buffer.asUint8List());

  final typeBytes = ascii.encode(type);
  final payload = <int>[...typeBytes, ...data];
  out.add(payload);

  final crc = ByteData(4)..setUint32(0, _crc32(payload));
  out.add(crc.buffer.asUint8List());
}

/// 生成 size x size 的红色图片，中央有白色方块
Uint8List makeRedPng({int size = 64}) {
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // PNG signature

  // IHDR: width, height, bitDepth=8, colorType=2 (RGB)
  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 2)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _writeChunk(out, 'IHDR', ihdr.buffer.asUint8List());

  // 原始像素：每行前面加 filter byte 0
  final raw = BytesBuilder();
  final quarter = size ~/ 4;
  for (var y = 0; y < size; y++) {
    raw.addByte(0);
    for (var x = 0; x < size; x++) {
      final inCenter =
          x >= quarter && x < size - quarter && y >= quarter && y < size - quarter;
      if (inCenter) {
        raw.add([255, 255, 255]);
      } else {
        raw.add([220, 40, 40]);
      }
    }
  }

  _writeChunk(out, 'IDAT', _zlibStore(raw.toBytes()));
  _writeChunk(out, 'IEND', const []);
  return out.toBytes();
}

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('用法: dart run tool/verify_vision.dart <baseUrl> <token> <model>');
    exitCode = 2;
    return;
  }

  final baseUrl = args[0].replaceAll(RegExp(r'/+$'), '');
  final token = args[1];
  final model = args[2];

  final png = makeRedPng(size: 64);
  stdout.writeln('→ 生成测试图片：64x64，${png.length} 字节');

  final messages = [
    {'role': 'system', 'content': '你是一位善于观察的助手，回答简洁。'},
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': '这张图片主要是什么颜色？只回答颜色名。'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'},
        },
      ],
    },
  ];

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
      stderr.writeln('✗ HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 400))}');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final content =
        ((decoded['choices'] as List).first as Map)['message']['content'] as String;
    stdout.writeln('← 回复：$content');
    stdout.writeln('✓ 多模态请求已被服务端接受并正确解析');
  } finally {
    client.close(force: true);
  }
}
