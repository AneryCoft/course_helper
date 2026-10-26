import 'package:flutter/material.dart';

import '../models/character_card.dart';
import '../setting/ai_setting.dart';
import '../setting/built_in_cards.dart';
import '../ui/design_tokens.dart';
import '../ui/widgets.dart';
import 'character_card_editor_page.dart';

/// 角色卡列表：切换当前使用的角色卡，管理自定义卡。
class CharacterCardsPage extends StatefulWidget {
  const CharacterCardsPage({super.key});

  @override
  State<CharacterCardsPage> createState() => _CharacterCardsPageState();
}

class _CharacterCardsPageState extends State<CharacterCardsPage> {
  Future<void> _openEditor(CharacterCard card) async {
    final result = await Navigator.of(context).push<CharacterCard>(
      MaterialPageRoute(builder: (_) => CharacterCardEditorPage(card: card)),
    );
    if (result == null) return;
    await AiSetting.saveCard(result);
    if (mounted) setState(() {});
  }

  Future<void> _createBlank() async {
    await _openEditor(AiSetting.blankCard());
  }

  Future<void> _duplicate(CharacterCard source) async {
    final copy = await AiSetting.duplicateCard(source);
    if (!mounted) return;
    setState(() {});
    _snack('已创建「${copy.name}」，可继续编辑');
  }

  Future<void> _delete(CharacterCard card) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除角色卡',
      message: '确定删除「${card.name}」？该操作不可撤销。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok) return;
    await AiSetting.deleteCard(card.id);
    if (mounted) setState(() {});
  }

  Future<void> _select(CharacterCard card) async {
    await AiSetting.setActiveCard(card.id);
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final builtIn = BuiltInCards.all;
    final custom = AiSetting.customCardsNotifier.value;
    final activeId = AiSetting.activeCardIdNotifier.value;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text(
          '角色卡',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBlank,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建角色卡'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.bottomInset),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.md,
            ),
            child: Text(
              '角色卡决定 AI 的身份、答题风格与开场方式。切换后会立即用于下一次答题。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          const SectionLabel('内置角色卡'),
          for (final card in builtIn)
            _CardTile(
              card: card,
              active: card.id == activeId,
              onTap: () => _select(card),
              onEdit: () => _duplicate(card),
              editLabel: '复制并编辑',
            ),

          SectionLabel(
            '我的角色卡',
            trailing: custom.isEmpty
                ? null
                : MetaChip(label: '${custom.length}', color: cs.primary),
          ),
          if (custom.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.page,
                vertical: AppSpacing.lg,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    Icon(Icons.style_outlined, size: 20, color: cs.outline),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        '还没有自定义角色卡。可以新建，也可以复制内置卡后修改。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: cs.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final card in custom)
              _CardTile(
                card: card,
                active: card.id == activeId,
                onTap: () => _select(card),
                onEdit: () => _openEditor(card),
                editLabel: '编辑',
                onDelete: () => _delete(card),
              ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final CharacterCard card;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final String editLabel;
  final VoidCallback? onDelete;

  const _CardTile({
    required this.card,
    required this.active,
    required this.onTap,
    required this.onEdit,
    required this.editLabel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm - 3,
      ),
      child: Material(
        color: active
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: active
                  ? Border.all(color: cs.primary, width: 1.6)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary(cs),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        card.name.trim().isEmpty
                            ? '?'
                            : card.name.trim().characters.first,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  card.name,
                                  style: tt.titleMedium?.copyWith(fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (active) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(
                                    '使用中',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (card.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              card.description,
                              style: tt.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (card.previewGreeting.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm + 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.format_quote_rounded,
                            size: 14, color: cs.outline),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            card.previewGreeting,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    MetaChip(
                      label: '${card.greetings.length} 条开场白',
                      icon: Icons.chat_bubble_outline_rounded,
                      color: cs.outline,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 12.5),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: Text(editLabel),
                    ),
                    if (onDelete != null)
                      IconButton(
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 19, color: cs.error),
                        tooltip: '删除',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
