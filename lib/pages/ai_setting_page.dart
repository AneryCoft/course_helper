import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/ai.dart';
import '../setting/ai_setting.dart';
import '../ui/design_tokens.dart';
import '../ui/widgets.dart';
import 'character_cards_page.dart';
import 'prompt_editor_page.dart';

/// AI 调用设置：地址、Token、模型与提示词均由用户自行配置。
class AiSettingPage extends StatefulWidget {
  const AiSettingPage({super.key});

  @override
  State<AiSettingPage> createState() => _AiSettingPageState();
}

class _AiSettingPageState extends State<AiSettingPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;

  bool _obscureToken = true;
  bool _baseUrlFocused = false;
  bool _tokenFocused = false;

  List<AiModel> _models = [];
  bool _isLoadingModels = false;
  bool _isTesting = false;
  String? _errorMessage;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: AiSetting.baseUrl);
    _tokenController = TextEditingController(text: AiSetting.token);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveConnection() async {
    await AiSetting.setBaseUrl(_baseUrlController.text);
    await AiSetting.setToken(_tokenController.text);
    _baseUrlController.text = AiSetting.baseUrl;
  }

  Future<void> _fetchModels() async {
    if (_isLoadingModels) return;

    await _saveConnection();
    if (!AiSetting.isConfigured) {
      setState(() => _errorMessage = '请先填写 API 地址与 Token');
      return;
    }

    setState(() {
      _isLoadingModels = true;
      _errorMessage = null;
      _testResult = null;
    });

    try {
      final models = await AiService.fetchModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _isLoadingModels = false;
      });

      if (models.isEmpty) {
        setState(() => _errorMessage = '服务端未返回任何模型');
        return;
      }
      _showModelPicker();
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoadingModels = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '拉取模型失败：$e';
          _isLoadingModels = false;
        });
      }
    }
  }

  Future<void> _testModel() async {
    await _saveConnection();
    if (!AiSetting.isConfigured) {
      setState(() => _testResult = '请先填写 API 地址与 Token');
      return;
    }
    if (AiSetting.model.isEmpty) {
      setState(() => _testResult = '请先拉取并选择模型');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final reply = await AiService.testConnection(AiSetting.model);
      if (mounted) setState(() => _testResult = '连接正常：$reply');
    } on AiException catch (e) {
      if (mounted) setState(() => _testResult = '测试失败：${e.message}');
    } catch (e) {
      if (mounted) setState(() => _testResult = '测试失败：$e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showModelPicker() {
    if (_models.isEmpty) {
      _snack('请先拉取模型列表');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ModelPickerSheet(
        models: _models,
        selected: AiSetting.model,
        onSelected: (value) async {
          await AiSetting.setModel(value);
          if (mounted) setState(() {});
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _openPromptEditor({
    required bool isSystemPrompt,
  }) async {
    final isSystem = isSystemPrompt;
    final current = isSystem ? AiSetting.systemPrompt : AiSetting.prompt;
    final defaultText = isSystem
        ? AiService.defaultSystemPrompt
        : AiService.defaultPromptTemplate;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PromptEditorPage(
          title: isSystem ? '系统提示词' : '答题提示词',
          subtitle: isSystem
              ? '定义 AI 的角色与输出风格。留空则使用默认值。'
              : '定义如何向 AI 描述题目。用 {{questions}} 表示题目列表的位置，'
                  '不写则题目会自动追加在末尾。',
          initialText: current.trim().isEmpty ? defaultText : current,
          defaultText: defaultText,
          hint: isSystem ? '例如：你是严谨的学科老师…' : '例如：请逐步思考后作答…',
          supportsQuestionsPlaceholder: !isSystem,
        ),
      ),
    );

    if (result == null) return;
    // 与默认值完全一致时视为「使用默认」，存空串
    final normalized = result.trim() == defaultText.trim() ? '' : result;
    if (isSystem) {
      await AiSetting.setSystemPrompt(normalized);
    } else {
      await AiSetting.setPrompt(normalized);
    }
    if (mounted) setState(() {});
  }

  Future<void> _clearAll() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空连接配置',
      message: '将清除已填写的 API 地址、Token 与模型选择。提示词设置会保留。',
      confirmText: '清空',
      destructive: true,
    );
    if (!ok) return;

    await AiSetting.clearAll();
    _baseUrlController.clear();
    _tokenController.clear();
    if (mounted) {
      setState(() {
        _models = [];
        _testResult = null;
        _errorMessage = null;
      });
    }
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
        title: const Text(
          'AI 调用设置',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '清空配置',
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          // ---------- 总开关 ----------
          _Card(
            child: SwitchListTile(
              secondary: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.smart_toy_outlined, size: 21, color: cs.primary),
              ),
              title: const Text('启用 AI 答题'),
              subtitle: const Text('答题页显示「AI 一键生成答案」按钮'),
              value: AiSetting.enabled,
              onChanged: (v) async {
                await AiSetting.setEnabled(v);
                if (mounted) setState(() {});
              },
            ),
          ),

          // ---------- 接口配置 ----------
          const SectionLabel('接口配置'),
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
                  Focus(
                    onFocusChange: (v) => setState(() => _baseUrlFocused = v),
                    child: TextField(
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'API 地址',
                        hintText: 'https://api.example.com/v1',
                        prefixIcon: const Icon(Icons.link_rounded, size: 20),
                        suffixIcon: _baseUrlFocused &&
                                _baseUrlController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () =>
                                    setState(_baseUrlController.clear),
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _saveConnection(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Focus(
                    onFocusChange: (v) => setState(() => _tokenFocused = v),
                    child: TextField(
                      controller: _tokenController,
                      obscureText: _obscureToken,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Token',
                        hintText: 'sk-...',
                        prefixIcon: const Icon(Icons.key_rounded, size: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_tokenFocused && _tokenController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 17),
                                tooltip: '复制',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _tokenController.text),
                                  );
                                  _snack('Token 已复制');
                                },
                              ),
                            IconButton(
                              icon: Icon(
                                _obscureToken
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 19,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureToken = !_obscureToken),
                            ),
                          ],
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _saveConnection(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 12, color: cs.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '仅保存在本机，不会上传到任何服务器',
                          style: TextStyle(fontSize: 11.5, color: cs.outline),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ---------- 模型 ----------
          SectionLabel(
            '模型',
            trailing: _models.isEmpty
                ? null
                : MetaChip(label: '${_models.length} 个可用', color: cs.primary),
          ),
          _Card(
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: AiSetting.modelNotifier,
                  builder: (context, model, _) {
                    final selected = model.isNotEmpty;
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (selected ? cs.tertiary : cs.outline)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(
                          Icons.memory_rounded,
                          size: 21,
                          color: selected ? cs.tertiary : cs.outline,
                        ),
                      ),
                      title: const Text('当前模型'),
                      subtitle: Text(
                        selected ? model : '尚未选择，点击拉取模型列表',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.normal,
                          color: selected ? cs.tertiary : cs.error,
                        ),
                      ),
                      trailing: _isLoadingModels
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.chevron_right_rounded,
                              size: 20, color: cs.outline),
                      onTap: _isLoadingModels
                          ? null
                          : (_models.isEmpty ? _fetchModels : _showModelPicker),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 68,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(Icons.cloud_download_outlined,
                        size: 20, color: cs.primary),
                  ),
                  title: const Text('拉取模型列表'),
                  subtitle: Text(
                    _isLoadingModels ? '正在拉取…' : '从服务端获取可用模型',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: _isLoadingModels ? null : _fetchModels,
                ),
                Divider(
                  height: 1,
                  indent: 68,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: _isTesting
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.wifi_tethering_rounded,
                            size: 20, color: cs.secondary),
                  ),
                  title: const Text('测试连通性'),
                  subtitle: Text(
                    _testResult ?? '发送一条测试消息验证配置',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testResult == null
                          ? null
                          : (_testResult!.startsWith('连接正常')
                              ? cs.primary
                              : cs.error),
                    ),
                  ),
                  onTap: _isTesting ? null : _testModel,
                ),
              ],
            ),
          ),

          // ---------- 角色卡 ----------
          const SectionLabel('角色卡'),
          _Card(
            child: ValueListenableBuilder<String>(
              valueListenable: AiSetting.activeCardIdNotifier,
              builder: (context, _, child) {
                final card = AiSetting.activeCard;
                final isDefault = AiSetting.isDefaultCardActive;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
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
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        MetaChip(label: '默认', color: cs.outline),
                      ],
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${card.greetings.length} 条开场白 · 点击切换或编辑',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: cs.outline),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CharacterCardsPage(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: cs.onErrorContainer),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _errorMessage = null),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: cs.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ---------- 提示词 ----------
          const SectionLabel('提示词'),
          _Card(
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: AiSetting.systemPromptNotifier,
                  builder: (context, value, _) => _PromptTile(
                    icon: Icons.psychology_outlined,
                    title: '系统提示词',
                    preview: value.trim().isEmpty
                        ? AiService.defaultSystemPrompt
                        : value,
                    isDefault: value.trim().isEmpty,
                    onTap: () => _openPromptEditor(isSystemPrompt: true),
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 68,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: AiSetting.promptNotifier,
                  builder: (context, value, _) => _PromptTile(
                    icon: Icons.edit_note_rounded,
                    title: '答题提示词',
                    preview: value.trim().isEmpty
                        ? AiService.defaultPromptTemplate
                        : value,
                    isDefault: value.trim().isEmpty,
                    onTap: () => _openPromptEditor(isSystemPrompt: false),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              0,
            ),
            child: Text(
              '为保证答案能被正确填入答题卡，程序会始终在提示词末尾附加 JSON 格式要求。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: cs.outline),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: cs.outline),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '本应用不内置任何 AI 服务地址或密钥。AI 生成的内容仅供学习参考，提交前请自行核对。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: cs.outline,
                    ),
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

/// 统一的设置卡片容器
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

/// 提示词条目：标题 + 预览（最多两行）+ 默认标记
class _PromptTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String preview;
  final bool isDefault;
  final VoidCallback onTap;

  const _PromptTile({
    required this.icon,
    required this.title,
    required this.preview,
    required this.isDefault,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, size: 20, color: cs.primary),
      ),
      title: Row(
        children: [
          Text(title),
          if (isDefault) ...[
            const SizedBox(width: 6),
            MetaChip(label: '默认', color: cs.outline),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: cs.outline),
      onTap: onTap,
    );
  }
}

/// 模型选择底部弹层：搜索 + 列表
class _ModelPickerSheet extends StatefulWidget {
  final List<AiModel> models;
  final String selected;
  final Future<void> Function(String) onSelected;

  const _ModelPickerSheet({
    required this.models,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = widget.models
        .where((m) => m.id.toLowerCase().contains(_keyword.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  '选择模型',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: AppSpacing.sm),
                MetaChip(label: '${filtered.length}', color: cs.primary),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _keyword = v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索模型名称',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '没有匹配的模型',
                    description: '换个关键词试试',
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    itemCount: filtered.length,
                    itemBuilder: (_, index) {
                      final model = filtered[index];
                      final isSelected = model.id == widget.selected;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 2,
                        ),
                        child: Material(
                          color: isSelected
                              ? cs.primaryContainer.withValues(alpha: 0.6)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            title: Text(
                              model.id,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: model.ownedBy.isEmpty
                                ? null
                                : Text(
                                    model.ownedBy,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle_rounded,
                                    color: cs.primary, size: 21)
                                : null,
                            onTap: () => widget.onSelected(model.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
