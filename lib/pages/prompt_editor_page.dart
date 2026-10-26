import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/design_tokens.dart';

/// 提示词编辑页：全屏编辑 + 实时字数 + 恢复默认 + 占位符快捷插入。
class PromptEditorPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String initialText;
  final String defaultText;
  final String hint;
  final bool supportsQuestionsPlaceholder;

  const PromptEditorPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.initialText,
    required this.defaultText,
    required this.hint,
    this.supportsQuestionsPlaceholder = false,
  });

  @override
  State<PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends State<PromptEditorPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isUsingDefault =>
      _controller.text.trim() == widget.defaultText.trim();

  void _restoreDefault() {
    setState(() => _controller.text = widget.defaultText);
    HapticFeedback.lightImpact();
  }

  void _insertPlaceholder() {
    final text = _controller.text;
    final selection = _controller.selection;
    final insert = '{{questions}}';

    if (selection.isValid) {
      final newText = text.replaceRange(selection.start, selection.end, insert);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + insert.length,
        ),
      );
    } else {
      _controller.text = '$text$insert';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasChanges = _controller.text != widget.initialText;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton(
              onPressed: hasChanges
                  ? () => Navigator.of(context).pop(_controller.text)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 说明区
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (_isUsingDefault) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 13, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          '当前为默认提示词',
                          style: TextStyle(fontSize: 11.5, color: cs.primary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // 编辑区
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ),

            // 底部工具条
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.md,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  if (widget.supportsQuestionsPlaceholder)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _insertPlaceholder,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text(
                          '插入题目占位符',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (widget.supportsQuestionsPlaceholder)
                    const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUsingDefault ? null : _restoreDefault,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: const Text(
                        '恢复默认',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 字数统计
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Center(
                child: Text(
                  '${_controller.text.characters.length} 字',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
