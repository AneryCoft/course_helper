import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final AppLogOutput appLogOutput = AppLogOutput();

final Logger logger = Logger(
  filter: ProductionFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: false,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.dateAndTime
  ),
  output: appLogOutput
);

Future<void> initLogger() => appLogOutput.init();


Future<bool?> exportLog() async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${_logFileName()}');
    await file.writeAsString(appLogOutput.content);

    final shareResult = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'CourseHelper log',
        text: 'CourseHelper log'
      ),
    );

    if (shareResult.status == ShareResultStatus.dismissed) {
      return null;
    } // 取消分享
    return true;
  } catch (e) {
    logger.e('导出日志失败: $e');
    return false;
  }
}

String _logFileName() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'course_helper_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.log';
}

class AppLogOutput extends LogOutput {
  static const int maxLines = 3000;

  final List<String> _buffer = [];
  File? _file;

  @override
  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}logs${Platform.pathSeparator}app.log');
    try {
      await _file!.parent.create(recursive: true);
    } catch (_) {}
  }

  String get content => _buffer.join('\n');

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      debugPrint(line);
    }
    _buffer.addAll(event.lines);
    if (_buffer.length > maxLines) {
      _buffer.removeRange(0, _buffer.length - maxLines);
    }
    _appendToFile(event.lines);
  }

  Future<void> _appendToFile(List<String> lines) async {
    final file = _file;
    if (file == null) return;
    try {
      final sink = file.openWrite(mode: FileMode.append);
      sink.writeAll(lines, '\n');
      sink.write('\n');
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }
}
