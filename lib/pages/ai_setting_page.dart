import 'package:flutter/material.dart';

import '../api/ai.dart';
import '../setting/ai_setting.dart';

/// AI 调用设置：地址、Token、模型与提示词均由用户自行配置。
class AiSettingPage extends StatefulWidget {
  const AiSettingPage({super.key});

  @override
  State<AiSettingPage> createState() => _AiSettingPageState();
}

class _AiSettingPageState extends State<AiSettingPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _promptController;
  late final TextEditingController _systemPromptController;

  bool _obscureToken = true;
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
    _promptController = TextEditingController(text: AiSetting.prompt);
    _systemPromptController = TextEditingController(text: AiSetting.systemPrompt);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    _promptController.dispose();
    _systemPromptController.dispose();
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
    });

    try {
      final models = await AiService.fetchModels();
      if (!mounted) return;
      setState(() => _models = models);

      if (models.isEmpty) {
        setState(() => _errorMessage = '服务端未返回任何模型');
        return;
      }
      _showModelPicker();
    } on AiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '拉取模型失败：$e');
    } finally {
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  Future<void> _testModel() async {
    await _saveConnection();
    final model = AiSetting.model;
    if (!AiSetting.isConfigured) {
      setState(() => _testResult = '请先填写 API 地址与 Token');
      return;
    }
    if (model.isEmpty) {
      setState(() => _testResult = '请先拉取并选择模型');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final reply = await AiService.testConnection(model);
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

    String keyword = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _models
                .where((m) => m.id.toLowerCase().contains(keyword.toLowerCase()))
                .toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.95,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '搜索模型',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setSheetState(() => keyword = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            '共 ${filtered.length} 个模型',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: RadioGroup<String>(
                        groupValue: AiSetting.model,
                        onChanged: (value) async {
                          if (value == null) return;
                          await AiSetting.setModel(value);
                          if (mounted) setState(() {});
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (_, index) {
                            final model = filtered[index];
                            final selected = model.id == AiSetting.model;
                            return RadioListTile<String>(
                              value: model.id,
                              title: Text(model.id),
                              subtitle:
                                  model.ownedBy.isEmpty ? null : Text(model.ownedBy),
                              secondary: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(ctx).colorScheme.primary,
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _editPrompt({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            minLines: 6,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              controller.text = '';
              Navigator.of(ctx).pop('');
            },
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == null) return;
    await onSave(result);
    if (mounted) setState(() {});
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空 AI 配置'),
        content: const Text('将清除已填写的地址、Token 与模型选择，提示词设置保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;

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
      appBar: AppBar(
        title: const Text('AI 调用设置'),
        actions: [
          IconButton(
            tooltip: '清空配置',
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AiSetting.enabledNotifier,
            builder: (context, enabled, _) => SwitchListTile(
              secondary: const Icon(Icons.smart_toy_outlined),
              title: const Text('启用 AI 答题'),
              subtitle: const Text('在答题提交页面显示「AI 生成答案」按钮'),
              value: enabled,
              onChanged: (value) => AiSetting.setEnabled(value),
            ),
          ),
          const Divider(),

          // 接口配置
          _SectionTitle('接口配置', cs),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: '例如 https://api.example.com/v1',
                helperText: '需兼容 OpenAI 接口协议，末尾无需斜杠',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _saveConnection(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _tokenController,
              obscureText: _obscureToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Token',
                hintText: 'sk-...',
                helperText: '仅保存在本机，不会上传到任何服务器',
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureToken = !_obscureToken),
                ),
              ),
              onSubmitted: (_) => _saveConnection(),
            ),
          ),
          const Divider(),

          // 模型
          _SectionTitle(
            '模型',
            cs,
            trailing: _models.isEmpty ? '未加载' : '${_models.length} 个可用',
          ),
          ValueListenableBuilder<String>(
            valueListenable: AiSetting.modelNotifier,
            builder: (context, model, _) => ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('当前模型'),
              subtitle: Text(
                model.isEmpty ? '未选择，点击拉取并选择模型' : model,
                style: TextStyle(
                  color: model.isEmpty ? cs.error : cs.onSurface,
                  fontWeight: model.isEmpty ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _models.isEmpty ? _fetchModels : _showModelPicker,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('拉取模型列表'),
            subtitle: _isLoadingModels ? const Text('正在拉取...') : null,
            trailing: _isLoadingModels
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _isLoadingModels ? null : _fetchModels,
          ),
          ListTile(
            leading: _isTesting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            title: const Text('测试模型连通性'),
            subtitle: _testResult != null ? Text(_testResult!) : null,
            onTap: _isTesting ? null : _testModel,
          ),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: cs.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const Divider(),

          // 提示词
          _SectionTitle('提示词', cs),
          ValueListenableBuilder<String>(
            valueListenable: AiSetting.systemPromptNotifier,
            builder: (context, value, _) => ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('系统提示词'),
              subtitle: Text(
                value.trim().isEmpty ? '使用默认：${AiService.defaultSystemPrompt}' : value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editPrompt(
                title: '系统提示词',
                initial: value.trim().isEmpty ? AiService.defaultSystemPrompt : value,
                hint: '告诉 AI 它的角色与输出风格',
                onSave: AiSetting.setSystemPrompt,
              ),
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: AiSetting.promptNotifier,
            builder: (context, value, _) => ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('答题提示词'),
              subtitle: Text(
                value.trim().isEmpty ? '使用默认模板' : value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editPrompt(
                title: '答题提示词',
                initial: value.trim().isEmpty ? AiService.defaultPromptTemplate : value,
                hint: '用 {{questions}} 表示题目列表的位置',
                onSave: AiSetting.setPrompt,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              '提示词中可用 {{questions}} 占位符插入题目；若不写，题目会自动追加在末尾。'
              '为保证答案能被正确填入，程序会始终在末尾附加 JSON 格式要求。',
              style: TextStyle(fontSize: 12, color: cs.outline, height: 1.5),
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '说明：本应用不内置任何 AI 服务地址或密钥，需自行填写。'
              'AI 生成的内容仅供学习参考，提交前请自行核对。',
              style: TextStyle(fontSize: 12, color: cs.outline, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final ColorScheme cs;
  final String? trailing;

  const _SectionTitle(this.title, this.cs, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
        ],
      ),
    );
  }
}
