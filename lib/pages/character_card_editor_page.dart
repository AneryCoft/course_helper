import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/character_card.dart';
import '../ui/design_tokens.dart';
import '../ui/widgets.dart';

/// 角色卡编辑页：角色名称、角色设定、开场白（可增删）。
class CharacterCardEditorPage extends StatefulWidget {
  final CharacterCard card;

  const CharacterCardEditorPage({super.key, required this.card});

  @override
  State<CharacterCardEditorPage> createState() =>
      _CharacterCardEditorPageState();
}

class _CharacterCardEditorPageState extends State<CharacterCardEditorPage> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.card.name);
  late final TextEditingController _descController =
      TextEditingController(text: widget.card.description);
  late final TextEditingController _personaController =
      TextEditingController(text: widget.card.persona);

  late List<TextEditingController> _greetingControllers;

  @override
  void initState() {
    super.initState();
    final greetings = widget.card.greetings.isEmpty
        ? <String>['']
        : List<String>.from(widget.card.greetings);
    _greetingControllers = greetings
        .map((g) => TextEditingController(text: g))
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _personaController.dispose();
    for (final c in _greetingControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addGreeting() {
    setState(() => _greetingControllers.add(TextEditingController()));
    HapticFeedback.lightImpact();
  }

  void _removeGreeting(int index) {
    if (_greetingControllers.length <= 1) {
      _snack('至少保留一条开场白');
      return;
    }
    setState(() {
      _greetingControllers.removeAt(index).dispose();
    });
  }

  void _save() {
    final greetings = _greetingControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final card = widget.card.copyWith(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      persona: _personaController.text.trim(),
      greetings: greetings,
      builtIn: false,
    );

    final error = card.validate();
    if (error != null) {
      _snack(error);
      return;
    }

    Navigator.of(context).pop(card);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          widget.card.name.isEmpty ? '新建角色卡' : '编辑角色卡',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const SectionLabel('基本信息'),
          _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      labelText: '角色名称',
                      hintText: '例如：明镜老师',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _descController,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: '简介（可选）',
                      hintText: '一句话说明这个角色的特点',
                      prefixIcon: Icon(Icons.notes_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SectionLabel('角色设定'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xs,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Text(
              '作为系统指令发送给 AI，决定它的身份、答题思路与输出风格。',
              style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _personaController,
                maxLines: null,
                minLines: 10,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 14, height: 1.6),
                decoration: const InputDecoration(
                  hintText: '例如：你是一位经验丰富的阅卷老师……\n\n'
                      '可以写清楚答题步骤要求、语言风格、注意事项等。',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),

          SectionLabel(
            '开场白',
            trailing: MetaChip(
              label: '${_greetingControllers.length} 条',
              color: cs.primary,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xs,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Text(
              '每次调用会随机取一条作为 AI 的首条回复，用于稳定答题风格。建议写 3 条以上。',
              style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
          for (var i = 0; i < _greetingControllers.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.xs,
                AppSpacing.page,
                AppSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _greetingControllers[i],
                      maxLines: null,
                      minLines: 2,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontSize: 13.5, height: 1.5),
                      decoration: InputDecoration(
                        hintText: '开场白 ${i + 1}',
                        isDense: true,
                        contentPadding: const EdgeInsets.all(AppSpacing.md),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => _removeGreeting(i),
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 20,
                      color: _greetingControllers.length <= 1
                          ? cs.outlineVariant
                          : cs.error,
                    ),
                    tooltip: '删除这条开场白',
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              0,
            ),
            child: OutlinedButton.icon(
              onPressed: _addGreeting,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                textStyle: const TextStyle(fontSize: 14),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加开场白'),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 13, color: cs.outline),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '开场白留空的行会在保存时自动忽略。角色名称与角色设定为必填项。',
                    style: TextStyle(fontSize: 11.5, height: 1.5, color: cs.outline),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
