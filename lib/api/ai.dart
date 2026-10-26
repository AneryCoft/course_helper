import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/chat_session.dart';
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

/// 单次对话的完整结果
class AiChatResult {
  /// 正文
  final String content;

  /// 思考过程（模型未返回时为空）
  final String reasoning;

  const AiChatResult({required this.content, this.reasoning = ''});

  bool get hasReasoning => reasoning.trim().isNotEmpty;
}

/// 单道题的 AI 解答结果
class AiAnswer {  /// 选择题选项名，如 ['A'] 或 ['A', 'C']
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
  ///
  /// [messages] 支持纯文本消息与 OpenAI 多模态数组格式（用于图片）。
  /// [reasoningEffort] 非空时请求模型进行深度思考（需服务端支持）。
  static Future<String> chat({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.3,
    bool jsonMode = true,
    ReasoningEffort? reasoningEffort,
  }) async {
    final result = await chatDetailed(
      model: model,
      messages: messages,
      temperature: temperature,
      jsonMode: jsonMode,
      reasoningEffort: reasoningEffort,
    );
    return result.content;
  }

  /// 发起对话并返回正文与思考过程
  static Future<AiChatResult> chatDetailed({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.3,
    bool jsonMode = true,
    ReasoningEffort? reasoningEffort,
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
    if (reasoningEffort != null) {
      body['reasoning_effort'] = reasoningEffort.apiValue;
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

    // 部分模型把思考过程放在 reasoning_content，部分放在 reasoning
    final reasoning = message is Map
        ? (message['reasoning_content'] ?? message['reasoning'] ?? '').toString()
        : '';

    return AiChatResult(
      content: content,
      reasoning: reasoning.trim(),
    );
  }

  /// 连通性测试：发送一条极短的消息（同时验证角色卡是否生效）
  static Future<String> testConnection(String model) async {
    final content = await chat(
      model: model,
      messages: buildTestMessages(),
      temperature: 0,
      jsonMode: false,
    );
    return content.trim();
  }

  /// 对话模式的补充提示词
  ///
  /// 与答题模式不同：对话不需要 JSON 输出，而是要自然语言 + 规范数学排版。
  static const String chatSupplement =
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

  /// 让 AI 讲解一张幻灯片
  ///
  /// 从网络下载幻灯片图片并转成 base64 传给视觉模型。
  /// 需要选择支持视觉的模型（如 GLM-4.1V、Qwen3-VL）。
  static Future<AiChatResult> explainSlide({
    required String model,
    required String imageUrl,
    required int slideIndex,
    required int totalSlides,
    String? courseName,
    Map<String, String>? imageHeaders,
  }) async {
    // 下载图片
    final Uint8List bytes;
    try {
      final response = await _client.get<List<int>>(
        imageUrl,
        options: Options(
          headers: imageHeaders,
          responseType: ResponseType.bytes,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw AiException('获取幻灯片失败（HTTP $status）');
      }
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const AiException('幻灯片内容为空');
      }
      bytes = Uint8List.fromList(data);
    } on AiException {
      rethrow;
    } on DioException catch (e) {
      throw AiException(_describeDioError(e));
    }

    // 控制体积，过大时直接提示
    if (bytes.length > 4 * 1024 * 1024) {
      throw const AiException('幻灯片图片过大，无法分析');
    }

    final mime = _guessImageMime(imageUrl);
    final base64Image = base64Encode(bytes);

    final contextLine = [
      if (courseName != null && courseName.trim().isNotEmpty)
        '课程：$courseName',
      '这是第 ${slideIndex + 1} 页，共 $totalSlides 页。',
    ].join('\n');

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是一位擅长课堂讲解的老师。请根据幻灯片内容，'
            '用中文清晰地讲解这一页的知识点。要求：\n'
            '1. 先概括这一页讲了什么（一句话）；\n'
            '2. 再逐点展开讲解，讲清概念、公式或逻辑关系；\n'
            '3. 如果有公式，用 \$...\$ 或 \$\$...\$\$ 规范书写；\n'
            '4. 如果页面信息不足，如实说明，不要编造；\n'
            '5. 最后用一句话总结重点。',
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': '$contextLine\n\n请讲解这一页的内容。',
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mime;base64,$base64Image'},
          },
        ],
      },
    ];

    return chatDetailed(
      model: model,
      messages: messages,
      temperature: 0.5,
      jsonMode: false,
    );
  }

  static String _guessImageMime(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return 'image/png';
    if (lower.contains('.webp')) return 'image/webp';
    if (lower.contains('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  /// 构建对话用的 system 消息（含角色卡设定）
  static List<Map<String, String>> buildChatSystemMessages() {
    final card = AiSetting.activeCard;
    final persona = card.persona.trim();
    // 对话模式不使用答题用的系统提示词（其中要求 JSON），改用对话专用补充
    final extra = AiSetting.chatSystemPrompt.trim().isEmpty
        ? chatSupplement
        : AiSetting.chatSystemPrompt;

    final messages = <Map<String, String>>[];
    if (persona.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': '$persona\n\n【对话要求】\n$extra',
      });
    } else {
      messages.add({'role': 'system', 'content': extra});
    }
    return messages;
  }

  /// 多轮对话
  ///
  /// 使用当前角色卡，并按 [contextLimit] 裁剪历史上下文。
  /// [reasoningEffort] 非空时启用深度思考并返回思考过程。
  static Future<AiChatResult> chatWithHistory({
    required String model,
    required List<ChatMessage> history,
    required int contextLimit,
    double temperature = 0.6,
    ReasoningEffort? reasoningEffort,
  }) async {
    final window = ContextWindow(contextLimit);
    final messages = window.build(
      systemMessages: buildChatSystemMessages(),
      history: history,
    );

    if (messages.length <= 1) {
      throw const AiException('没有可发送的消息');
    }

    return chatDetailed(
      model: model,
      messages: messages,
      temperature: temperature,
      jsonMode: false,
      reasoningEffort: reasoningEffort,
    );
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
  ///
  /// 调用时使用当前角色卡：
  /// - 角色设定 + 系统提示词共同构成 system 消息；
  /// - 随机取一条开场白作为 assistant 首条消息，稳定模型行为并减少每次输出漂移。
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

    final messages = <Map<String, String>>[];

    // 角色卡：设定作为 system 主体，系统提示词作为补充约束
    final card = AiSetting.activeCard;
    final persona = card.persona.trim();
    final systemContent = persona.isEmpty
        ? systemPrompt
        : '$persona\n\n【补充要求】\n$systemPrompt';
    messages.add({'role': 'system', 'content': systemContent});

    // 角色卡：开场白作为 assistant 首条消息（示例对话），稳定输出风格
    final greeting = card.randomGreeting().trim();
    if (greeting.isNotEmpty) {
      messages.add({'role': 'assistant', 'content': greeting});
    }

    messages.add({'role': 'user', 'content': '$prompt$_formatContract'});

    final content = await chat(
      model: model,
      messages: messages,
      temperature: 0.2,
    );

    return _parseAnswers(content);
  }

  /// 生成用于连通性测试的消息（同样带上角色卡设定）
  static List<Map<String, String>> buildTestMessages() {
    final card = AiSetting.activeCard;
    final persona = card.persona.trim();
    final systemPrompt = AiSetting.systemPrompt.trim().isEmpty
        ? defaultSystemPrompt
        : AiSetting.systemPrompt;

    final messages = <Map<String, String>>[];
    if (persona.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': '$persona\n\n【补充要求】\n$systemPrompt',
      });
      final greeting = card.randomGreeting().trim();
      if (greeting.isNotEmpty) {
        messages.add({'role': 'assistant', 'content': greeting});
      }
    }
    messages.add({'role': 'user', 'content': '请只回复两个字：正常'});
    return messages;
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
