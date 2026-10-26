import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/character_card.dart';
import '../models/chat_session.dart';
import '../utils/storage.dart';
import 'built_in_cards.dart';

/// AI 调用设置
///
/// 出于安全考虑，API 地址与 Token 不再内置到程序中，均由用户自行填写并保存在本机。
class AiSetting {
  static const String _enabledKey = 'ai_enabled';
  static const String _baseUrlKey = 'ai_base_url';
  static const String _tokenKey = 'ai_token';
  static const String _modelKey = 'ai_model';
  static const String _promptKey = 'ai_prompt';
  static const String _systemPromptKey = 'ai_system_prompt';
  static const String _cardsKey = 'ai_character_cards';
  static const String _activeCardKey = 'ai_active_card_id';
  static const String _contextLimitKey = 'ai_context_limit';
  static const String _chatPromptKey = 'ai_chat_prompt';
  static const String _deepThinkingKey = 'ai_deep_thinking';
  static const String _reasoningEffortKey = 'ai_reasoning_effort';
  static const String _webSearchKey = 'ai_web_search';

  static const bool _defaultEnabled = true;

  /// 默认上下文大小（token）
  static const int defaultContextLimit = 4096;

  /// 上下文大小可选档位
  static const List<int> contextLimitOptions = [
    2048,
    4096,
    8192,
    16384,
    32768,
    65536,
  ];

  /// 启用状态通知（设置页与答题页共享）
  static final ValueNotifier<bool> enabledNotifier =
      ValueNotifier<bool>(_defaultEnabled);

  /// API 地址通知
  static final ValueNotifier<String> baseUrlNotifier = ValueNotifier<String>('');

  /// Token 通知
  static final ValueNotifier<String> tokenNotifier = ValueNotifier<String>('');

  /// 当前选中模型通知
  static final ValueNotifier<String> modelNotifier = ValueNotifier<String>('');

  /// 用户提示词通知（空字符串表示使用默认模板）
  static final ValueNotifier<String> promptNotifier = ValueNotifier<String>('');

  /// 系统提示词通知（空字符串表示使用默认）
  static final ValueNotifier<String> systemPromptNotifier = ValueNotifier<String>('');

  /// 自定义角色卡通知
  static final ValueNotifier<List<CharacterCard>> customCardsNotifier =
      ValueNotifier<List<CharacterCard>>(const []);

  /// 当前选中的角色卡 ID 通知
  static final ValueNotifier<String> activeCardIdNotifier =
      ValueNotifier<String>(BuiltInCards.defaultCardId);

  /// 上下文大小通知（token）
  static final ValueNotifier<int> contextLimitNotifier =
      ValueNotifier<int>(defaultContextLimit);

  /// 对话模式补充提示词通知（空字符串表示使用默认）
  static final ValueNotifier<String> chatSystemPromptNotifier =
      ValueNotifier<String>('');

  /// 深度思考开关
  static final ValueNotifier<bool> deepThinkingNotifier =
      ValueNotifier<bool>(false);

  /// 推理等级（默认 Low）
  static final ValueNotifier<ReasoningEffort> reasoningEffortNotifier =
      ValueNotifier<ReasoningEffort>(ReasoningEffort.low);

  /// 联网搜索开关
  static final ValueNotifier<bool> webSearchNotifier =
      ValueNotifier<bool>(false);

  /// 启动时从本地恢复
  static Future<void> init() async {
    final prefs = StorageManager.prefs;
    enabledNotifier.value = prefs.getBool(_enabledKey) ?? _defaultEnabled;
    baseUrlNotifier.value = prefs.getString(_baseUrlKey) ?? '';
    tokenNotifier.value = prefs.getString(_tokenKey) ?? '';
    modelNotifier.value = prefs.getString(_modelKey) ?? '';
    promptNotifier.value = prefs.getString(_promptKey) ?? '';
    systemPromptNotifier.value = prefs.getString(_systemPromptKey) ?? '';
    customCardsNotifier.value = _loadCustomCards();
    final savedCardId = prefs.getString(_activeCardKey);
    activeCardIdNotifier.value =
        (savedCardId != null && savedCardId.isNotEmpty)
            ? savedCardId
            : BuiltInCards.defaultCardId;
    contextLimitNotifier.value =
        prefs.getInt(_contextLimitKey) ?? defaultContextLimit;
    chatSystemPromptNotifier.value = prefs.getString(_chatPromptKey) ?? '';
    deepThinkingNotifier.value = prefs.getBool(_deepThinkingKey) ?? false;
    reasoningEffortNotifier.value = ReasoningEffort.fromName(
      prefs.getString(_reasoningEffortKey),
    );
    webSearchNotifier.value = prefs.getBool(_webSearchKey) ?? false;
  }

  static List<CharacterCard> _loadCustomCards() {
    final raw = StorageManager.prefs.getString(_cardsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final cards = <CharacterCard>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final card = CharacterCard.fromJson(item);
          if (card.id.isNotEmpty && card.name.isNotEmpty) cards.add(card);
        }
      }
      return cards;
    } catch (_) {
      return const [];
    }
  }

  static bool get enabled => enabledNotifier.value;

  static String get baseUrl => baseUrlNotifier.value;

  static String get token => tokenNotifier.value;

  static String get model => modelNotifier.value;

  static String get prompt => promptNotifier.value;

  static String get systemPrompt => systemPromptNotifier.value;

  /// 是否已填写地址与 Token
  static bool get isConfigured =>
      baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  static Future<void> setEnabled(bool value) async {
    enabledNotifier.value = value;
    await StorageManager.prefs.setBool(_enabledKey, value);
  }

  static Future<void> setBaseUrl(String value) async {
    final normalized = value.trim();
    baseUrlNotifier.value = normalized;
    await StorageManager.prefs.setString(_baseUrlKey, normalized);
  }

  static Future<void> setToken(String value) async {
    final normalized = value.trim();
    tokenNotifier.value = normalized;
    await StorageManager.prefs.setString(_tokenKey, normalized);
  }

  static Future<void> setModel(String model) async {
    modelNotifier.value = model;
    await StorageManager.prefs.setString(_modelKey, model);
  }

  static Future<void> clearModel() async {
    modelNotifier.value = '';
    await StorageManager.prefs.remove(_modelKey);
  }

  static Future<void> setPrompt(String value) async {
    promptNotifier.value = value;
    if (value.trim().isEmpty) {
      await StorageManager.prefs.remove(_promptKey);
    } else {
      await StorageManager.prefs.setString(_promptKey, value);
    }
  }

  static Future<void> setSystemPrompt(String value) async {
    systemPromptNotifier.value = value;
    if (value.trim().isEmpty) {
      await StorageManager.prefs.remove(_systemPromptKey);
    } else {
      await StorageManager.prefs.setString(_systemPromptKey, value);
    }
  }

  /// 清空全部 AI 配置（切换自己的服务时使用）
  static Future<void> clearAll() async {
    await setBaseUrl('');
    await setToken('');
    await clearModel();
  }

  // ==================== 角色卡 ====================

  /// 全部可用角色卡：内置卡在前，自定义卡在后
  static List<CharacterCard> get allCards =>
      [...BuiltInCards.all, ...customCardsNotifier.value];

  /// 当前生效的角色卡（找不到时回落到默认卡）
  static CharacterCard get activeCard {
    final id = activeCardIdNotifier.value;
    for (final card in allCards) {
      if (card.id == id) return card;
    }
    return BuiltInCards.defaultCard;
  }

  /// 是否正在使用默认角色卡
  static bool get isDefaultCardActive =>
      activeCardIdNotifier.value == BuiltInCards.defaultCardId;

  static Future<void> setActiveCard(String id) async {
    activeCardIdNotifier.value = id;
    await StorageManager.prefs.setString(_activeCardKey, id);
  }

  static Future<void> _persistCustomCards(List<CharacterCard> cards) async {
    customCardsNotifier.value = List.unmodifiable(cards);
    await StorageManager.prefs.setString(
      _cardsKey,
      jsonEncode(cards.map((c) => c.toJson()).toList()),
    );
  }

  /// 新增或更新自定义角色卡
  static Future<void> saveCard(CharacterCard card) async {
    final cards = [...customCardsNotifier.value];
    final index = cards.indexWhere((c) => c.id == card.id);
    if (index >= 0) {
      cards[index] = card;
    } else {
      cards.add(card);
    }
    await _persistCustomCards(cards);
  }

  /// 删除自定义角色卡（内置卡不可删除）
  static Future<void> deleteCard(String id) async {
    final cards =
        customCardsNotifier.value.where((c) => c.id != id).toList();
    await _persistCustomCards(cards);

    // 若删除的是当前卡，回落到默认卡
    if (activeCardIdNotifier.value == id) {
      await setActiveCard(BuiltInCards.defaultCardId);
    }
  }

  /// 基于内置卡创建可编辑副本
  static Future<CharacterCard> duplicateCard(CharacterCard source) async {
    final now = DateTime.now();
    final copy = source.copyWith(
      id: 'custom_${now.microsecondsSinceEpoch}',
      name: '${source.name}（副本）',
      builtIn: false,
    );
    await saveCard(copy);
    return copy;
  }

  /// 生成一个空的自定义角色卡
  static CharacterCard blankCard() {
    return CharacterCard(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: '',
      persona: '',
      greetings: const [''],
      builtIn: false,
    );
  }

  /// 已保存的模型是否仍在最新拉取的列表中
  static bool isModelAvailable(List<String> models) =>
      modelNotifier.value.isNotEmpty && models.contains(modelNotifier.value);

  // ==================== 上下文大小 ====================

  static int get contextLimit => contextLimitNotifier.value;

  static Future<void> setContextLimit(int value) async {
    final normalized = value.clamp(512, 128000);
    contextLimitNotifier.value = normalized;
    await StorageManager.prefs.setInt(_contextLimitKey, normalized);
  }

  /// 把 token 数格式化为易读文本
  static String formatContextLimit(int tokens) {
    if (tokens >= 1024) {
      final k = tokens / 1024;
      return k == k.roundToDouble()
          ? '${k.toInt()}K'
          : '${k.toStringAsFixed(1)}K';
    }
    return '$tokens';
  }

  // ==================== 对话提示词 ====================

  static String get chatSystemPrompt => chatSystemPromptNotifier.value;

  static Future<void> setChatSystemPrompt(String value) async {
    chatSystemPromptNotifier.value = value;
    if (value.trim().isEmpty) {
      await StorageManager.prefs.remove(_chatPromptKey);
    } else {
      await StorageManager.prefs.setString(_chatPromptKey, value);
    }
  }

  // ==================== 深度思考与联网 ====================

  static bool get deepThinking => deepThinkingNotifier.value;

  static ReasoningEffort get reasoningEffort => reasoningEffortNotifier.value;

  static bool get webSearch => webSearchNotifier.value;

  static Future<void> setDeepThinking(bool value) async {
    deepThinkingNotifier.value = value;
    await StorageManager.prefs.setBool(_deepThinkingKey, value);
  }

  static Future<void> setReasoningEffort(ReasoningEffort effort) async {
    reasoningEffortNotifier.value = effort;
    await StorageManager.prefs.setString(_reasoningEffortKey, effort.apiValue);
  }

  static Future<void> setWebSearch(bool value) async {
    webSearchNotifier.value = value;
    await StorageManager.prefs.setBool(_webSearchKey, value);
  }

  /// 当前是否应把推理参数发给服务端
  static ReasoningEffort? get effectiveReasoningEffort =>
      deepThinking ? reasoningEffort : null;
}
