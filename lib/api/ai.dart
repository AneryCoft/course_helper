import 'dart:convert';

import 'package:dio/dio.dart';

import '../setting/ai_setting.dart';
import '../utils/logger.dart';

/// AI 服务返回的模型信息
class AiModel {
  final String id;
  final String ownedBy;

  const AiModel({required this.id, this.ownedBy = ''});

  @override
  String toString() => id;
}

/// AI 请求异常，携带可读的错误信息
class AiException implements Exception {
  final String message;

  const AiException(this.message);

  @override
  String toString() => message;
}

/// 单道题的 AI 解答结果
class AiAnswer {
  /// 选择题选项名，如 ['A'] 或 ['A', 'C']
  final List<String> options;

  /// 填空题每空的答案（按空顺序）
  final List<String> blanks;

  /// 简答题/论述题等主观题答案
  final String text;

  /// 解析
  final String explanation;

  const AiAnswer({
    this.options = const [],
    this.blanks = const [],
    this.text = '',
    this.explanation = '',
  });

  bool get isEmpty =>
      options.isEmpty && blanks.isEmpty && text.trim().isEmpty && explanation.trim().isEmpty;

  AiAnswer copyWith({
    List<String>? options,
    List<String>? blanks,
    String? text,
    String? explanation,
  }) {
    return AiAnswer(
      options: options ?? this.options,
      blanks: blanks ?? this.blanks,
      text: text ?? this.text,
      explanation: explanation ?? this.explanation,
    );
  }
}

/// AI 调用入口
///
/// 服务地址、Token 与提示词均不内置，全部由用户在「设置 - AI 调用设置」中自行填写，
/// 程序只负责按 OpenAI 兼容协议调用。
class AiService {
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _requestTimeout = Duration(seconds: 90);

  static Dio? _dio;
  static String? _dioBaseUrl;

  /// 当前是否已填写地址与 Token
  static bool get isConfigured =>
      AiSetting.baseUrl.trim().isNotEmpty && AiSetting.token.trim().isNotEmpty;

  /// 规范化用户输入的地址：去掉首尾空白与结尾斜杠
  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer ${AiSetting.token.trim()}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// 地址改变时重建 Dio，避免沿用旧的 baseUrl
  static Dio get _client {
    final baseUrl = _normalizeBaseUrl(AiSetting.baseUrl);
    if (baseUrl.isEmpty) {
      throw const AiException('尚未配置 API 地址，请前往「设置 - AI 调用设置」填写');
    }
    if (AiSetting.token.trim().isEmpty) {
      throw const AiException('尚未配置 Token，请前往「设置 - AI 调用设置」填写');
    }
    if (_dio == null || _dioBaseUrl != baseUrl) {
      _dio?.close(force: true);
      _dioBaseUrl = baseUrl;
      _dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: _requestTimeout,
        sendTimeout: _requestTimeout,
        responseType: ResponseType.plain,
        // 自行处理状态码，便于读取服务端错误信息
        validateStatus: (_) => true,
      ));
    }
    return _dio!;
  }

  /// 拉取可用模型列表
  static Future<List<AiModel>> fetchModels() async {
    final Response<String> response;
    try {
      response = await _client.get<String>('/models', options: Options(headers: _headers));
    } on AiException {
      rethrow;
    } on DioException catch (e) {
      logger.e('AI 拉取模型失败: $e');
      throw AiException(_describeDioError(e));
    }

    _ensureSuccess(response, '拉取模型列表');

    dynamic data;
    try {
      data = jsonDecode(response.data ?? '');
    } catch (e) {
      throw const AiException('模型列表解析失败：返回内容不是合法 JSON');
    }

    final list = (data is Map ? data['data'] : data) as List?;
    if (list == null) {
      throw const AiException('模型列表解析失败：未找到 data 字段');
    }

    final models = list
        .whereType<Map>()
        .map((e) => AiModel(
              id: (e['id'] ?? '').toString(),
              ownedBy: (e['owned_by'] ?? '').toString(),
            ))
        .where((m) => m.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));

    return models;
  }

  /// 发起一次对话补全，返回模型输出的文本
  static Future<String> chat({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.3,
    bool jsonMode = true,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': temperature,
    };
    if (jsonMode) {
      body['response_format'] = {'type': 'json_object'};
    }

    final Response<String> response;
    try {
      response = await _client.post<String>(
        '/chat/completions',
        data: jsonEncode(body),
        options: Options(headers: _headers),
      );
    } on AiException {
      rethrow;
    } on DioException catch (e) {
      logger.e('AI 请求失败: $e');
      throw AiException(_describeDioError(e));
    }

    _ensureSuccess(response, '请求 AI');

    dynamic data;
    try {
      data = jsonDecode(response.data ?? '');
    } catch (e) {
      throw const AiException('AI 返回内容解析失败：不是合法 JSON');
    }

    if (data is! Map) {
      throw const AiException('AI 返回内容格式异常');
    }
    if (data['error'] != null) {
      throw AiException(_extractErrorMessage(data['error']) ?? 'AI 服务返回错误');
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiException('AI 未返回任何结果，请更换模型后重试');
    }

    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AiException('AI 返回内容为空，请更换模型后重试');
    }
    return content;
  }

  /// 连通性测试：发送一条极短的消息
  static Future<String> testConnection(String model) async {
    final content = await chat(
      model: model,
      messages: const [
        {'role': 'user', 'content': '请只回复两个字：正常'},
      ],
      temperature: 0,
      jsonMode: false,
    );
    return content.trim();
  }

  /// 默认提示词模板
  ///
  /// 占位符 `{{questions}}` 会被替换为题目列表；用户可在设置中自定义。
  /// 无论用户如何改写，JSON 结构约束都会在调用时强制追加，保证解析可用。
  static const String defaultPromptTemplate =
      '你是一名严谨的阅卷老师，请完整解答下面每一道题。\n\n'
      '题目如下：\n'
      '{{questions}}';

  /// 默认系统提示词
  static const String defaultSystemPrompt =
      '你是学识渊博的答题助手，擅长各学科题目解答。你只输出严格合法的 JSON。';

  /// 解析所需的结构约束：始终追加在用户提示词之后，保证输出可被程序解析
  static const String _formatContract =
      '\n\n输出要求（必须严格遵守）：\n'
      '1. 只输出一个 JSON 对象，不要输出 markdown 代码块、解释或其他任何文字。\n'
      '2. JSON 结构为：\n'
      '{"answers":[{"index":0,"options":["A"],"blanks":[],"text":"","explanation":"解析"}]}\n'
      '3. index 必须与题目编号一致，且每个题目都要有结果。\n'
      '4. 选择题：options 填写正确选项的字母（多选按字母顺序，如 ["A","C"]），其他字段留空字符串或空数组。\n'
      '5. 填空题：按顺序在 blanks 中填写每一空的答案，只写答案本身，不要带"第1空"等前缀。\n'
      '6. 判断/选择/填空等题目也要在 explanation 中写明理由。\n'
      '7. 简答、论述、名词解释、计算等主观题：text 填写可直接提交的完整答案，简洁准确。\n'
      '8. explanation 为该题的解析，条理清晰；若无必要可写简短理由。';

  /// 批量解答题目
  ///
  /// [questions] 为按题目顺序排列的题目描述文本，返回的 Map 以题目下标为键。
  static Future<Map<int, AiAnswer>> solveQuestions({
    required String model,
    required List<String> questions,
  }) async {
    if (questions.isEmpty) return {};

    final questionBlock = questions.join('\n\n');
    final template = AiSetting.prompt.trim().isEmpty
        ? defaultPromptTemplate
        : AiSetting.prompt;

    // 支持 {{questions}} 占位符；用户没写占位符时自动追加在末尾
    final prompt = template.contains('{{questions}}')
        ? template.replaceAll('{{questions}}', questionBlock)
        : '$template\n\n$questionBlock';

    final systemPrompt = AiSetting.systemPrompt.trim().isEmpty
        ? defaultSystemPrompt
        : AiSetting.systemPrompt;

    final content = await chat(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '$prompt$_formatContract'},
      ],
      temperature: 0.2,
    );

    return _parseAnswers(content);
  }

  /// 解析 AI 返回的 JSON 答案（公开以便测试与复用）
  static Map<int, AiAnswer> parseAnswers(String raw) => _parseAnswers(raw);

  /// 解析 AI 返回的 JSON 答案
  static Map<int, AiAnswer> _parseAnswers(String raw) {
    final decoded = _decodeJsonObject(raw);
    if (decoded == null) {
      throw const AiException('AI 返回的答案无法解析，请重试或更换模型');
    }

    final list = decoded['answers'];
    if (list is! List) {
      throw const AiException('AI 返回的答案缺少 answers 字段，请重试或更换模型');
    }

    final result = <int, AiAnswer>{};
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;

      final indexRaw = item['index'] ?? i;
      final index = indexRaw is int ? indexRaw : int.tryParse(indexRaw.toString());
      if (index == null) continue;

      final options = _toStringList(item['options'])
          .map((e) => e.trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList();
      // 兼容 "AB" 这类合并写法
      final expandedOptions = <String>[];
      for (final opt in options) {
        if (opt.length > 1 && RegExp(r'^[A-Z]+$').hasMatch(opt)) {
          expandedOptions.addAll(opt.split(''));
        } else {
          expandedOptions.add(opt);
        }
      }

      result[index] = AiAnswer(
        options: expandedOptions,
        blanks: _toStringList(item['blanks']).map((e) => e.trim()).toList(),
        text: (item['text'] ?? '').toString().trim(),
        explanation: (item['explanation'] ?? '').toString().trim(),
      );
    }

    if (result.isEmpty) {
      throw const AiException('AI 未返回有效的答案内容，请重试或更换模型');
    }
    return result;
  }

  /// 容错解析 JSON 对象：兼容 ```json 代码块、前后多余文字
  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
      text = text.trim();
    }

    dynamic decoded = _tryDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      decoded = _tryDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return null;
  }

  static dynamic _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e?.toString() ?? '').toList();
    return [value.toString()];
  }

  static void _ensureSuccess(Response response, String action) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;

    String? serverMessage;
    final body = response.data;
    if (body is String && body.isNotEmpty) {
      final decoded = _tryDecode(body);
      if (decoded is Map) serverMessage = _extractErrorMessage(decoded['error'] ?? decoded);
    }
    serverMessage ??= _statusMessage(status);
    throw AiException('$action失败：$serverMessage');
  }

  static String? _extractErrorMessage(dynamic error) {
    if (error == null) return null;
    if (error is String) return error;
    if (error is Map) {
      final message = error['message'] ?? error['msg'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return null;
  }

  static String _statusMessage(int status) {
    switch (status) {
      case 0:
        return '网络连接失败，请检查网络后重试';
      case 401:
      case 403:
        return 'Token 无效或已失效（$status）';
      case 404:
        return '接口地址不存在（404）';
      case 429:
        return '请求过于频繁，请稍后重试（429）';
      case 503:
        return '模型暂不可用，请更换模型后重试（503）';
      default:
        return '服务异常（$status）';
    }
  }

  static String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return '连接 AI 服务超时，请检查网络';
      case DioExceptionType.receiveTimeout:
        return 'AI 响应超时，请稍后重试或更换模型';
      case DioExceptionType.connectionError:
        return '无法连接 AI 服务，请检查网络';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return e.message ?? '网络请求失败';
    }
  }

  /// 当前配置的模型（未选择时返回 null）
  static String? get currentModel {
    final model = AiSetting.model;
    return model.isEmpty ? null : model;
  }

  /// 是否可直接使用 AI（已启用、已填地址与 Token、且已选模型）
  static bool get isReady =>
      AiSetting.enabled && isConfigured && (currentModel != null);
}
