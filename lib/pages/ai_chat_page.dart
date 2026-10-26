import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/ai.dart';
import '../models/chat_session.dart';
import '../session/account.dart';
import '../session/chat_history_store.dart';
import '../setting/ai_setting.dart';
import '../ui/design_tokens.dart';
import '../ui/math_text.dart';
import '../ui/widgets.dart';
import '../utils/ai_response_formatter.dart';
import 'ai_setting_page.dart';
import 'character_cards_page.dart';
import 'widget/avatar.dart';

/// AI 对话页
///
/// 既可作为底部导航的主页面（[embedded] = true，无返回按钮），
/// 也可从其他位置 push 打开（[embedded] = false，带返回按钮）。
///
/// - 使用当前角色卡（角色设定 + 开场白）
/// - 上下文大小默认 4K，可在页面内调整
/// - 支持插入文件与拍照参与对话
class AiChatPage extends StatefulWidget {
  /// 是否嵌入主导航（嵌入时不显示返回按钮，顶部改为大标题）
  final bool embedded;

  const AiChatPage({super.key, this.embedded = false});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  final List<ChatAttachment> _pendingAttachments = [];

  bool _isSending = false;
  bool _isCapturing = false;
  bool _showContextPanel = false;

  @override
  void initState() {
    super.initState();
    _restoreHistory();
    _inputController.addListener(_onInputChanged);
  }

  /// 恢复上次的对话；没有历史时用角色卡开场白起头
  void _restoreHistory() {
    final saved = ChatHistoryStore.load();
    if (saved.isNotEmpty) {
      _messages.addAll(saved);
      // 恢复后滚动到底部，直接看到最新消息
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
      return;
    }
    _seedGreeting();
    _persist();
  }

  /// 把当前对话写入本地
  void _persist() {
    ChatHistoryStore.save(_messages);
  }

  /// 用角色卡的开场白作为对话起点
  void _seedGreeting() {
    final greeting = AiSetting.activeCard.randomGreeting().trim();
    if (greeting.isEmpty) return;
    _messages.add(ChatMessage(role: 'assistant', content: greeting));
  }

  void _onInputChanged() => setState(() {});

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: AppDuration.normal,
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _pickFiles() async {
    try {
      final picked = await FileExtractor.pickFiles();
      if (picked.isEmpty || !mounted) return;

      setState(() => _pendingAttachments.addAll(picked));
      _snack('已添加 ${picked.length} 个文件');
    } catch (e) {
      if (mounted) _snack('选择文件失败：$e');
    }
  }

  /// 拍照：调用系统相机，照片仅在内存中使用，不写入相册
  Future<void> _capturePhoto() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final photo = await FileExtractor.capturePhoto();
      if (photo == null || !mounted) return;

      if (photo.base64Data == null) {
        _snack('照片过大，请降低分辨率后重试');
        return;
      }
      setState(() => _pendingAttachments.add(photo));
    } catch (e) {
      if (mounted) _snack('拍照失败：$e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _removeAttachment(int index) {
    setState(() => _pendingAttachments.removeAt(index));
  }

  Future<void> _send() async {
    if (_isSending) return;

    final text = _inputController.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;

    final model = AiSetting.model;
    if (!AiSetting.isConfigured) {
      _snack('请先在 AI 调用设置中填写地址与 Token');
      return;
    }
    if (model.isEmpty) {
      _snack('请先选择模型');
      return;
    }

    // 组装用户消息：文本附件拼进正文，图片走多模态
    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    final images = attachments.where((a) => a.isImage).toList();
    final textAttachments = attachments.where((a) => !a.isImage).toList();

    final buffer = StringBuffer();
    for (final a in textAttachments) {
      buffer
        ..writeln(a.toPromptBlock())
        ..writeln();
    }
    if (text.isNotEmpty) buffer.write(text);
    // 只发图片时给一句默认提示，避免空正文
    if (buffer.toString().trim().isEmpty && images.isNotEmpty) {
      buffer.write('请分析这张图片。');
    }

    final userMessage = ChatMessage(
      role: 'user',
      content: buffer.toString().trim(),
      attachments: attachments.map((a) => a.name).toList(),
      images: images,
    );

    setState(() {
      _messages.add(userMessage);
      _pendingAttachments.clear();
      _inputController.clear();
      _isSending = true;
    });
    _persist();
    _scrollToBottom();

    // 占位消息，显示「正在输入」
    final placeholder = ChatMessage(role: 'assistant', content: '', pending: true);
    setState(() => _messages.add(placeholder));
    _scrollToBottom();

    try {
      final reply = await AiService.chatWithHistory(
        model: model,
        // 排除占位消息本身
        history: _messages.where((m) => !m.pending).toList(),
        contextLimit: AiSetting.contextLimit,
        // 深度思考开启时才发送推理等级
        reasoningEffort: AiSetting.effectiveReasoningEffort,
      );

      if (!mounted) return;
      setState(() {
        final index = _messages.indexOf(placeholder);
        if (index >= 0) {
          // 展示前先展开 JSON，避免把原始结构直接给用户看
          _messages[index] = placeholder.copyWith(
            content: AiResponseFormatter.toDisplayText(reply.content),
            reasoning: reply.reasoning,
            pending: false,
          );
        }
      });
      _persist();
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexOf(placeholder);
        if (index >= 0) {
          _messages[index] = placeholder.copyWith(
            content: '',
            pending: false,
            error: e.message,
          );
        }
      });
      _persist();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexOf(placeholder);
        if (index >= 0) {
          _messages[index] = placeholder.copyWith(
            content: '',
            pending: false,
            error: '$e',
          );
        }
      });
      _persist();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _retry(ChatMessage failed) async {
    final index = _messages.indexOf(failed);
    if (index < 0) return;
    // 移除失败消息与其之前的用户消息，重新发送
    setState(() {
      _messages.removeAt(index);
      if (index > 0 && _messages[index - 1].isUser) {
        final userMsg = _messages.removeAt(index - 1);
        _inputController.text = userMsg.content;
      }
    });
    _inputFocus.requestFocus();
  }

  void _clearConversation() {
    showConfirmDialog(
      context,
      title: '清空对话',
      message: '将删除当前会话的全部消息，角色卡与设置不受影响。',
      confirmText: '清空',
      destructive: true,
    ).then((ok) {
      if (!ok || !mounted) return;
      setState(() {
        _messages.clear();
        _pendingAttachments.clear();
        _seedGreeting();
      });
      // 用户主动清空后才真正删除本地记录
      ChatHistoryStore.clear().then((_) => _persist());
    });
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
        automaticallyImplyLeading: !widget.embedded,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.embedded ? '对话' : 'AI 对话',
              style: TextStyle(
                fontSize: widget.embedded ? 22 : 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: AiSetting.activeCardIdNotifier,
              builder: (context, _, child) => Text(
                '角色：${AiSetting.activeCard.name}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '切换角色卡',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CharacterCardsPage()),
            ),
            icon: const Icon(Icons.style_outlined),
          ),
          IconButton(
            tooltip: '上下文设置',
            onPressed: () => setState(() => _showContextPanel = !_showContextPanel),
            icon: Icon(
              _showContextPanel
                  ? Icons.tune_rounded
                  : Icons.tune_outlined,
            ),
          ),
          IconButton(
            tooltip: '清空对话',
            onPressed: _messages.isEmpty ? null : _clearConversation,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          AnimatedCrossFade(
            duration: AppDuration.normal,
            crossFadeState: _showContextPanel
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _ContextPanel(
              onChanged: () => setState(() {}),
              onOpenSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiSettingPage()),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
          Expanded(
            child: !AiSetting.isConfigured || AiSetting.model.isEmpty
                ? EmptyState(
                    icon: Icons.settings_suggest_outlined,
                    title: '还没有配置 AI',
                    description: !AiSetting.isConfigured
                        ? '请先填写 API 地址与 Token，然后拉取并选择模型'
                        : '请先拉取并选择要使用的模型',
                    actionLabel: '前往设置',
                    onAction: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AiSettingPage(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  )
                : _messages.isEmpty
                    ? EmptyState(
                        icon: Icons.forum_outlined,
                        title: '开始一段对话',
                        description: '当前角色卡没有开场白，直接输入问题即可',
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.page,
                          vertical: AppSpacing.md,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _MessageBubble(
                          message: _messages[index],
                          onRetry: _messages[index].error != null
                              ? () => _retry(_messages[index])
                              : null,
                          onCopy: _messages[index].content.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: _messages[index].content,
                                    ),
                                  );
                                  _snack('已复制');
                                },
                        ),
                      ),
          ),
          _buildInputBar(context),
        ],
      ),
    );
  }

  /// 能力开关栏：深度思考 / 联网搜索
  Widget _buildCapabilityBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<bool>(
      valueListenable: AiSetting.deepThinkingNotifier,
      builder: (context, deepThinking, _) => Row(
        children: [
          _CapabilityChip(
            icon: Icons.psychology_rounded,
            label: '深度思考',
            active: deepThinking,
            onTap: () async {
              await AiSetting.setDeepThinking(!deepThinking);
              if (mounted) setState(() {});
            },
            // 开启后可长按快速切换推理等级
            onLongPress: deepThinking
                ? () => _showReasoningPicker()
                : null,
            trailing: deepThinking
                ? AiSetting.reasoningEffort.label
                : null,
          ),
          const SizedBox(width: 6),
          _CapabilityChip(
            icon: Icons.travel_explore_rounded,
            label: '联网搜索',
            active: AiSetting.webSearch,
            onTap: () => _toggleWebSearch(),
          ),
          const Spacer(),
          if (deepThinking)
            ValueListenableBuilder<ReasoningEffort>(
              valueListenable: AiSetting.reasoningEffortNotifier,
              builder: (context, effort, _) => Text(
                '推理等级 ${effort.label}',
                style: TextStyle(fontSize: 10.5, color: cs.outline),
              ),
            ),
        ],
      ),
    );
  }

  /// 切换联网搜索
  ///
  /// 当前服务端未提供联网能力，开启时会明确告知用户，
  /// 避免开关看起来生效但实际无效。
  Future<void> _toggleWebSearch() async {
    final next = !AiSetting.webSearch;
    await AiSetting.setWebSearch(next);
    if (!mounted) return;
    setState(() {});

    if (next) {
      _snack('当前 AI 服务未提供联网搜索能力，该开关不会改变回复内容');
    }
  }

  /// 选择推理等级
  Future<void> _showReasoningPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Text('推理等级', style: Theme.of(ctx).textTheme.titleLarge),
                ],
              ),
            ),
            ValueListenableBuilder<ReasoningEffort>(
              valueListenable: AiSetting.reasoningEffortNotifier,
              builder: (ctx2, current, _) => RadioGroup<ReasoningEffort>(
                groupValue: current,
                onChanged: (value) async {
                  if (value == null) return;
                  await AiSetting.setReasoningEffort(value);
                  if (mounted) setState(() {});
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Column(
                  children: [
                    RadioListTile<ReasoningEffort>(
                      value: ReasoningEffort.low,
                      title: Text('低（Low）'),
                      subtitle: Text('响应最快，思考最少'),
                    ),
                    RadioListTile<ReasoningEffort>(
                      value: ReasoningEffort.medium,
                      title: Text('中（Medium）'),
                      subtitle: Text('平衡速度与深度'),
                    ),
                    RadioListTile<ReasoningEffort>(
                      value: ReasoningEffort.high,
                      title: Text('高（High）'),
                      subtitle: Text('深入推理，耗时最长'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSend = !_isSending &&
        (_inputController.text.trim().isNotEmpty ||
            _pendingAttachments.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 待发送附件
              if (_pendingAttachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SizedBox(
                    height: 52,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pendingAttachments.length,
                      itemBuilder: (context, index) {
                        final a = _pendingAttachments[index];
                        if (a.isImage) {
                          // 图片显示缩略图
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xs),
                                  child: Image.memory(
                                    base64Decode(a.base64Data!),
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: GestureDetector(
                                    onTap: () => _removeAttachment(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: cs.error,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: cs.surface,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 11,
                                        color: cs.onError,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            label: Text(
                              a.name,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            avatar: Icon(
                              Icons.description_outlined,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            labelPadding: const EdgeInsets.only(left: 2),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onDeleted: () => _removeAttachment(index),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              // 能力开关：深度思考 / 联网搜索
              _buildCapabilityBar(context),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _AttachmentButton(
                    enabled: !_isSending && !_isCapturing,
                    capturing: _isCapturing,
                    onPickFile: _pickFiles,
                    onCapture: _capturePhoto,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontSize: 14.5, height: 1.45),
                      decoration: InputDecoration(
                        hintText: '输入消息…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md + 2,
                          vertical: AppSpacing.md,
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: canSend ? _send : null,
                    tooltip: '发送',
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded, size: 20),
                  ),
                ],
              ),
              ValueListenableBuilder<int>(
                valueListenable: AiSetting.contextLimitNotifier,
                builder: (context, limit, _) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.memory_rounded, size: 11, color: cs.outline),
                      const SizedBox(width: 4),
                      Text(
                        '上下文 ${AiSetting.formatContextLimit(limit)} · '
                        '${AiSetting.model.isEmpty ? "未选择模型" : AiSetting.model}',
                        style: TextStyle(fontSize: 10.5, color: cs.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 附件按钮：弹出菜单选择「拍照」或「选择文件」
class _AttachmentButton extends StatelessWidget {
  final bool enabled;
  final bool capturing;
  final VoidCallback onPickFile;
  final VoidCallback onCapture;

  const _AttachmentButton({
    required this.enabled,
    required this.capturing,
    required this.onPickFile,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    if (capturing) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: '添加附件',
      icon: const Icon(Icons.add_circle_outline_rounded, size: 23),
      onSelected: (value) {
        if (value == 'camera') {
          onCapture();
        } else {
          onPickFile();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'camera',
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 19),
              SizedBox(width: 10),
              Text('拍照'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'file',
          child: Row(
            children: [
              Icon(Icons.attach_file_rounded, size: 19),
              SizedBox(width: 10),
              Text('选择文件'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 能力开关胶囊
class _CapabilityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? trailing;

  const _CapabilityChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: active
          ? cs.primaryContainer
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: AppDuration.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active ? cs.primary.withValues(alpha: 0.5) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    trailing!,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 思考过程面板
///
/// 与正文刻意区分：
/// - 默认折叠，只显示标题与字数
/// - 虚线边框 + 浅色底 + 等宽小字
/// - 展开后单独区域，不与正文混排
class _ReasoningPanel extends StatefulWidget {
  final String reasoning;

  const _ReasoningPanel({required this.reasoning});

  @override
  State<_ReasoningPanel> createState() => _ReasoningPanelState();
}

class _ReasoningPanelState extends State<_ReasoningPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chars = widget.reasoning.characters.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.7),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '· $chars 字',
                    style: TextStyle(fontSize: 10.5, color: cs.outline),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppDuration.fast,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 17,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: AppDuration.fast,
                crossFadeState: _expanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectionArea(
                    child: Text(
                      widget.reasoning,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.55,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 上下文大小设置面板
class _ContextPanel extends StatelessWidget {
  final VoidCallback onChanged;
  final VoidCallback onOpenSettings;

  const _ContextPanel({required this.onChanged, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '上下文大小',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onOpenSettings,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('AI 设置'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueListenableBuilder<int>(
            valueListenable: AiSetting.contextLimitNotifier,
            builder: (context, current, _) => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in AiSetting.contextLimitOptions)
                  ChoiceChip(
                    label: Text(
                      AiSetting.formatContextLimit(option),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: current == option,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) async {
                      if (!selected) return;
                      await AiSetting.setContextLimit(option);
                      onChanged();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '越大的上下文能记住更多历史，但会消耗更多 token。默认 4K。',
            style: TextStyle(fontSize: 11, height: 1.45, color: cs.outline),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;

  const _MessageBubble({
    required this.message,
    this.onRetry,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _Avatar(icon: Icons.auto_awesome, color: cs.tertiary),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 附件标签
                if (message.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final name in message.attachments)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: 0.7),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 11, color: cs.onSurfaceVariant),
                                const SizedBox(width: 3),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 140),
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                // 思考过程（与正文区分：折叠、虚线框、浅色、等宽字体）
                if (!isUser && message.hasReasoning && !message.pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ReasoningPanel(reasoning: message.reasoning),
                  ),

                // 气泡本体
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md + 2,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? cs.primaryContainer
                        : (message.error != null
                            ? cs.errorContainer
                            : cs.surfaceContainerHigh),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppRadius.md),
                      topRight: const Radius.circular(AppRadius.md),
                      bottomLeft: Radius.circular(isUser ? AppRadius.md : 4),
                      bottomRight: Radius.circular(isUser ? 4 : AppRadius.md),
                    ),
                  ),
                  child: message.pending
                      ? _TypingIndicator()
                      : message.error != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.error_outline_rounded,
                                        size: 15, color: cs.onErrorContainer),
                                    const SizedBox(width: 5),
                                    Text(
                                      '发送失败',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onErrorContainer,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  message.error!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: cs.onErrorContainer,
                                  ),
                                ),
                                if (onRetry != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: TextButton.icon(
                                      onPressed: onRetry,
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(0, 32),
                                        padding: EdgeInsets.zero,
                                        textStyle: const TextStyle(fontSize: 12),
                                      ),
                                      icon: const Icon(Icons.refresh_rounded,
                                          size: 14),
                                      label: const Text('重新编辑'),
                                    ),
                                  ),
                              ],
                            )
                          : (isUser
                              ? SelectableText(
                                  message.content,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.6,
                                    color: cs.onPrimaryContainer,
                                  ),
                                )
                              // AI 回复用 Markdown + 数学渲染
                              : AiMarkdown(
                                  message.content,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.65,
                                    color: cs.onSurface,
                                  ),
                                )),
                ),

                // 复制按钮
                if (onCopy != null && !message.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded,
                                size: 11, color: cs.outline),
                            const SizedBox(width: 3),
                            Text(
                              '复制',
                              style:
                                  TextStyle(fontSize: 10, color: cs.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AppSpacing.sm),
            _UserAvatar(),
          ],
        ],
      ),
    );
  }
}

/// 用户头像：优先显示当前登录账号的头像，无头像时回退首字
class _UserAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = AccountManager.currentUser;

    if (user == null) {
      return _Avatar(icon: Icons.person_rounded, color: cs.primary);
    }

    if (user.avatar.trim().isNotEmpty) {
      return AvatarWidget(
        imageUrl: user.avatar,
        size: 30,
        borderRadius: AppRadius.xs,
        iconSize: 16,
      );
    }

    final initial = user.name.trim().isEmpty ? '我' : user.name.trim().characters.first;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: AppGradients.tint(cs.primary),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Avatar({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: AppGradients.tint(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }
}

/// 「正在输入」三点动画
class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_controller.value + i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0, 1);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.toDouble(),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
