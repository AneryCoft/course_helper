import 'dart:convert';

/// AI 角色卡
///
/// 一张角色卡由「角色名称 + 角色设定 + 多条开场白」组成：
/// - 角色设定作为 system 消息注入，决定 AI 的身份与答题风格；
/// - 开场白作为 assistant 首条消息注入，起到示范回答、稳定输出的作用。
class CharacterCard {
  /// 稳定 ID，内置卡固定，用户新建卡使用时间戳生成
  final String id;

  /// 角色名称
  final String name;

  /// 一句话简介，用于列表展示
  final String description;

  /// 角色设定（system prompt 主体）
  final String persona;

  /// 开场白列表，至少一条；调用时随机取一条作为 assistant 首条消息
  final List<String> greetings;

  /// 是否为内置卡（内置卡不可删除，可编辑副本）
  final bool builtIn;

  const CharacterCard({
    required this.id,
    required this.name,
    this.description = '',
    required this.persona,
    required this.greetings,
    this.builtIn = false,
  });

  /// 随机取一条开场白
  String randomGreeting([int? seed]) {
    if (greetings.isEmpty) return '';
    if (greetings.length == 1) return greetings.first;
    final index = seed == null
        ? DateTime.now().microsecondsSinceEpoch % greetings.length
        : seed % greetings.length;
    return greetings[index];
  }

  CharacterCard copyWith({
    String? id,
    String? name,
    String? description,
    String? persona,
    List<String>? greetings,
    bool? builtIn,
  }) {
    return CharacterCard(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      persona: persona ?? this.persona,
      greetings: greetings ?? this.greetings,
      builtIn: builtIn ?? this.builtIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'persona': persona,
        'greetings': greetings,
        'builtIn': builtIn,
      };

  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    final rawGreetings = json['greetings'];
    final greetings = <String>[];
    if (rawGreetings is List) {
      for (final g in rawGreetings) {
        final text = g?.toString().trim() ?? '';
        if (text.isNotEmpty) greetings.add(text);
      }
    }
    return CharacterCard(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      persona: (json['persona'] ?? '').toString(),
      greetings: greetings,
      builtIn: json['builtIn'] == true,
    );
  }

  String encode() => jsonEncode(toJson());

  static CharacterCard? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final card = CharacterCard.fromJson(decoded);
      if (card.id.isEmpty || card.name.isEmpty) return null;
      return card;
    } catch (_) {
      return null;
    }
  }

  /// 校验：名称与设定必填，开场白至少一条
  String? validate() {
    if (name.trim().isEmpty) return '请填写角色名称';
    if (persona.trim().isEmpty) return '请填写角色设定';
    final valid = greetings.where((g) => g.trim().isNotEmpty).toList();
    if (valid.isEmpty) return '至少需要一条开场白';
    return null;
  }

  /// 供列表展示的首条开场白
  String get previewGreeting =>
      greetings.isEmpty ? '' : greetings.first;
}
