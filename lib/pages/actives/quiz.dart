import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/api_service.dart';
import '../../../api/ai.dart';
import '../../../api/quiz.dart';
import '../../../api/image.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../setting/ai_setting.dart';
import '../../../ui/design_tokens.dart';
import '../../../ui/widgets.dart';
import '../../../utils/logger.dart';
import '../../../utils/problem_type.dart';
import '../ai_setting_page.dart';
import '../widget/accounts_selector.dart';

class QuizPage extends StatefulWidget {
  final Active active;
  final String courseId;
  final String classId;
  
  const QuizPage({
    super.key, 
    required this.active,
    required this.courseId,
    required this.classId
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class CountdownDisplay extends StatelessWidget {
  final ValueNotifier<String> timeNotifier;
  final bool isManualEnd;
  
  const CountdownDisplay({
    super.key, 
    required this.timeNotifier, 
    required this.isManualEnd
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: timeNotifier,
      builder: (context, time, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: isManualEnd 
              ? Colors.orange.shade100 
              : Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(
                isManualEnd ? Icons.access_time : Icons.timer,
                color: isManualEnd 
                    ? Colors.orange 
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isManualEnd ? '手动结束' : '剩余：$time',
                style: TextStyle(
                  color: isManualEnd 
                      ? Colors.orange 
                      : Theme.of(context).colorScheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuizPageState extends State<QuizPage> {
  // 页面状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  
  // 批量提交状态
  int _totalCount = 0;
  final List<String> _failedAccounts = [];
  
  // 测验数据
  List<dynamic> _quizList = [];
  Map<String, dynamic>? _activeData;
  
  // 倒计时相关
  Timer? _countdownTimer;
  final ValueNotifier<String> _remainingTimeNotifier = ValueNotifier('');
  bool _isManualEnd = false; // 手动结束标记
  
  // 输入控制器缓存
  final Map<String, TextEditingController> _controllers = {};
  
  // 账号选择
  List<User> _selectedAccounts = [];

  // AI 生成状态
  bool _isGeneratingAi = false;
  final Map<int, AiAnswer> _aiAnswers = {};
  
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    // 先请求HTML并检查活动状态
    try {
      final response = await ApiService.sendRequest(widget.active.url, responseType: ResponseType.plain);
      if (response == null) {
        setState(() {
          _errorMessage = '获取数据失败';
          _isLoading = false;
        });
        return;
      }
      String htmlContent = response.data.toString();
      
      // 使用正则表达式匹配activeStatus
      RegExp activeStatusRegex = RegExp(r'activeStatus: (.+?),');
      Match? statusMatch = activeStatusRegex.firstMatch(htmlContent);
      
      if (statusMatch != null) {
        String status = statusMatch.group(1)!;

        if (status == 'undefined') {
          await _loadQuizDataFromHtml(htmlContent);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = '您已提交过本次测验';
          });
        }
      } else {
        // 没有找到activeStatus，正常加载
        await _loadQuizDataFromHtml(htmlContent);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '检查活动状态失败: $e';
        _isLoading = false;
      });
    }
  }

  void _startCountdown() {
    // 解析活动结束时间
    final endTime = _activeData?['endTime'];
    final isManualEnd = _activeData?['endTime'] == null;
    
    setState(() {
      _isManualEnd = isManualEnd;
    });
    
    if (isManualEnd) {
      // 手动结束情况
      _remainingTimeNotifier.value = '手动结束';
      return;
    }
    
    if (endTime != null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final remaining = endTime - now;
        
        if (remaining <= 0) {
          _remainingTimeNotifier.value = '0分钟';
          timer.cancel();
          return;
        }
        
        final minutes = (remaining / 60000).floor();
        final seconds = ((remaining % 60000) / 1000).floor();
        
        // 构造新时间字符串
        String newTime;
        if (minutes > 0) {
          newTime = '$minutes分$seconds秒';
        } else {
          newTime = '$seconds秒';
        }
        
        // 只在时间真正改变时更新ValueNotifier
        if (_remainingTimeNotifier.value != newTime) {
          _remainingTimeNotifier.value = newTime;
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _remainingTimeNotifier.dispose();
    // 清理所有输入控制器
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  Future<void> _loadQuizDataFromHtml(String htmlContent) async {
    try {
      RegExp quizListRegex = RegExp(r'quizList = (\[.*\]);');
      RegExp activeRegex = RegExp(r'active = (\{.*\});');
        
      Match? quizListMatch = quizListRegex.firstMatch(htmlContent);
      Match? activeMatch = activeRegex.firstMatch(htmlContent);
        
      if (quizListMatch != null && activeMatch != null) {
        String quizListJson = quizListMatch.group(1)!;
        String activeJson = activeMatch.group(1)!;
        
        // 解析JSON数据
        List<dynamic> quizList = json.decode(quizListJson);
        Map<String, dynamic> activeData = json.decode(activeJson);
        
        setState(() {
          _quizList = quizList;
          _activeData = activeData;
          _isLoading = false;
          
          // 初始化每个题目的答题数据
          for (var quiz in _quizList) {
            if (quiz['personAnswer'] == null) {
              quiz['personAnswer'] = {};
            }
            
            // 根据题目类型初始化答题数据
            switch (quiz['type']) {
              case 0: // 单选题
              case 1: // 多选题
              case 3: // 判断题
              case 16: // 判断题
                quiz['personAnswer']['myoption'] = '';
                break;
              case 2: // 填空题
              case 9: // 分录题
              case 10: // 资料题
                if (quiz['personAnswer']['blankAnswer'] == null) {
                  quiz['personAnswer']['blankAnswer'] = [];
                  // 初始化填空题的空格
                  if (quiz['answer'] != null) {
                    for (int i = 0; i < quiz['answer'].length; i++) {
                      quiz['personAnswer']['blankAnswer'].add({'content': ''});
                    }
                  }
                }
                break;
              case 4: // 简答题
              case 5: // 名词解释
              case 6: // 论述题
              case 7: // 计算题
              case 18: // 口语题
                quiz['personAnswer']['content'] = '';
                if (quiz['personAnswer']['recs'] == null) {
                  quiz['personAnswer']['recs'] = [];
                }
                if (quiz['personAnswer']['imgs'] == null) {
                  quiz['personAnswer']['imgs'] = [];
                }
                break;
            }
          }
          
          // 启动倒计时
          if (_activeData != null) {
            _startCountdown();
          }
        });
      } else {
        setState(() {
          _errorMessage = '解析测验数据失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '加载数据出错: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadQuizData() async {
    try {
      final response = await ApiService.sendRequest(widget.active.url, responseType: ResponseType.plain);
      if (response == null) {
        setState(() {
          _errorMessage = '获取数据失败';
          _isLoading = false;
        });
        return;
      }
      
      // 解析HTML中的JavaScript数据
      String htmlContent = response.data.toString();
        
        // 提取 quizList 数据
        RegExp quizListRegex = RegExp(r'quizList\s*=\s*(\[.*?\]);', multiLine: true, dotAll: true);
        RegExp activeRegex = RegExp(r'active\s*=\s*(\{.*?\});', multiLine: true, dotAll: true);
        
        Match? quizListMatch = quizListRegex.firstMatch(htmlContent);
        Match? activeMatch = activeRegex.firstMatch(htmlContent);
        
        if (quizListMatch != null && activeMatch != null) {
          String quizListJson = quizListMatch.group(1)!;
          String activeJson = activeMatch.group(1)!;
          
          // 解析JSON数据
          List<dynamic> quizList = json.decode(quizListJson);
          Map<String, dynamic> activeData = json.decode(activeJson);
          
          setState(() {
            _quizList = quizList;
            _activeData = activeData;
            _isLoading = false;
            
            // 初始化每个题目的答题数据
            for (var quiz in _quizList) {
              if (quiz['personAnswer'] == null) {
                quiz['personAnswer'] = {};
              }
              
              // 根据题目类型初始化答题数据
              switch (quiz['type']) {
                case 0: // 单选题
                case 1: // 多选题
                case 3: // 判断题
                case 16: // 判断题
                  quiz['personAnswer']['myoption'] = '';
                  break;
                case 2: // 填空题
                case 9: // 分录题
                case 10: // 资料题
                  if (quiz['personAnswer']['blankAnswer'] == null) {
                    quiz['personAnswer']['blankAnswer'] = [];
                    // 初始化填空题的空格
                    if (quiz['answer'] != null) {
                      for (int i = 0; i < quiz['answer'].length; i++) {
                        quiz['personAnswer']['blankAnswer'].add({'content': ''});
                      }
                    }
                  }
                  break;
                case 4: // 简答题
                case 5: // 名词解释
                case 6: // 论述题
                case 7: // 计算题
                case 18: // 口语题
                  quiz['personAnswer']['content'] = '';
                  if (quiz['personAnswer']['recs'] == null) {
                    quiz['personAnswer']['recs'] = [];
                  }
                  if (quiz['personAnswer']['imgs'] == null) {
                    quiz['personAnswer']['imgs'] = [];
                  }
                  break;
              }
            }
            
            // 启动倒计时
            if (_activeData != null) {
              _startCountdown();
            }
          });
        } else {
          setState(() {
            _errorMessage = '解析测验数据失败';
            _isLoading = false;
          });
        }
    } catch (e) {
      setState(() {
        _errorMessage = '加载数据出错: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAnswersForAllAccounts() async {
    if (_selectedAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择至少一个账号')),
        );
      }
      return;
    }
    
    // 先检查活动状态
    final status = await QuizApi.checkStatus(widget.classId, widget.active.id);
    if (status != null && !status){
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('活动已结束')),
        );
        return;
      }
    }
    
    setState(() {
      _isSubmitting = true;
      _totalCount = _selectedAccounts.length;
      _failedAccounts.clear();
    });

    final submitData = jsonEncode(_constructSubmitData());

    try {
      final results = await ApiService.sendForEachUser<Map<String, dynamic>>(
        _selectedAccounts,
        (user) async {
          final api = QuizApi(user);
          return await api.submitAnswer(
            widget.classId, widget.courseId, widget.active.id, submitData
          );
        },
      );

      // 处理结果
      for (int i = 0; i < _selectedAccounts.length; i++) {
        final account = _selectedAccounts[i];
        final result = results[i];
        
        if (result == null || result['result'] != 1) {
          _failedAccounts.add('${account.name}: ${result?['errorMsg'] ?? '提交失败'}');
        }
      }
      
      _showSubmitResult();
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<dynamic> _constructSubmitData() {
    // 构造要提交的数据格式
    return _quizList.map((quiz) {
      final quizData = Map<String, dynamic>.from(quiz);
      
      // 检查并自动填充未作答的题目
      _autoFillAnswers(quizData);

      return quizData;
    }).toList();
  }
  
  void _autoFillAnswers(Map<String, dynamic> quizData) {
    final quizType = quizData['type'];
    final answers = quizData['answer'] as List?;
    
    if (answers == null || answers.isEmpty) return;
    
    switch (quizType) {
      case 0: // 单选题
      case 3: // 判断题
      case 16: // 判断题
        if (quizData['personAnswer']['myoption'] == null || 
            quizData['personAnswer']['myoption'] == '') {
          // 寻找正确答案
          final correctOption = answers.firstWhere(
            (option) => option['isanswer'] == true,
            orElse: () => answers.first, // 如果找不到正确答案，选择第一个
          );
          quizData['personAnswer']['myoption'] = correctOption['name'];
        }
        break;
        
      case 1: // 多选题
        if (quizData['personAnswer']['myoption'] == null || 
            quizData['personAnswer']['myoption'] == '') {
          // 寻找所有正确答案
          final correctOptions = answers
              .where((option) => option['isanswer'] == true)
              .map((option) => option['name'] as String)
              .toList();

          quizData['personAnswer']['myoption'] = correctOptions.join('');
        }
        break;
        
      case 2: // 填空题
        final blankAnswers = quizData['personAnswer']['blankAnswer'] as List?;
        if (blankAnswers != null) {
          for (int i = 0; i < blankAnswers.length; i++) {
            final blank = blankAnswers[i];
            if (blank['content'] == null || blank['content'] == '') {
              // 使用对应位置的正确答案（提取纯文本，分号分隔取第一个）
              if (i < answers.length) {
                final correctAnswer = answers[i];
                final htmlContent = correctAnswer['content'] ?? '';
                final textContent = _extractTextFromHtml(htmlContent);
                blank['content'] = textContent.split(';').first.trim();
              }
            }
          }
        }
        break;
        
      case 4: // 简答题
        if (quizData['personAnswer']['content'] == null || 
            quizData['personAnswer']['content'] == '') {
          if (answers.isNotEmpty) {
            // 使用第一个答案
            final correctAnswer = answers[0];
            final htmlAnswer = correctAnswer['answer'] ?? '';
            // 如果有多个答案用分号分隔，只取第一个
            // 不分割其实也算分
            final textAnswer = _extractTextFromHtml(htmlAnswer);
            final firstAnswer = textAnswer.split(';').first.trim();
            quizData['personAnswer']['content'] = firstAnswer;
          }
        }
        break;
    }
  }

  // ==================== AI 生成答案与解析 ====================

  /// 一键调用 AI 生成所有题目的答案与解析，并填入答题界面
  Future<void> _generateAiAnswers() async {
    if (_isGeneratingAi) return;

    final model = AiService.currentModel;
    if (model == null || model.isEmpty) {
      await _showAiNotConfiguredDialog();
      return;
    }

    if (_quizList.isEmpty) {
      _snack('暂无可作答的题目');
      return;
    }

    setState(() => _isGeneratingAi = true);
    try {
      final prompts = <String>[];
      for (var i = 0; i < _quizList.length; i++) {
        prompts.add(_buildAiPrompt(_quizList[i], i));
      }

      final answers = await AiService.solveQuestions(
        model: model,
        questions: prompts,
      );

      if (!mounted) return;

      var filled = 0;
      setState(() {
        _aiAnswers.clear();
        for (var i = 0; i < _quizList.length; i++) {
          final answer = answers[i];
          if (answer == null || answer.isEmpty) continue;
          _aiAnswers[i] = answer;
          _applyAiAnswer(_quizList[i], i, answer);
          filled++;
        }
      });

      if (filled == 0) {
        _snack('AI 未返回可用答案，请重试或更换模型');
      } else {
        _snack('AI 已生成 $filled/${_quizList.length} 道题的答案，提交前可手动修改');
      }
    } on AiException catch (e) {
      _snack('AI 生成失败：${e.message}');
    } catch (e) {
      logger.e('AI 生成答案失败: $e');
      _snack('AI 生成失败：$e');
    } finally {
      if (mounted) setState(() => _isGeneratingAi = false);
    }
  }

  /// 构造单题的 AI 提示文本
  String _buildAiPrompt(dynamic quiz, int index) {
    final type = quiz['type'] as int? ?? -1;
    final buffer = StringBuffer()
      ..writeln('[$index] 题型：${problemTypeName(type)}')
      ..writeln('题干：${_extractTextFromHtml(quiz['content']?.toString() ?? '')}');

    final answers = quiz['answer'];
    if (type == 2 && answers is List && answers.isNotEmpty) {
      buffer.writeln('要求填写 ${answers.length} 个空。');
    }

    if (answers is List && answers.isNotEmpty) {
      // 去掉 isanswer 字段，避免把标准答案泄露给 AI
      final options = answers
          .map((option) => '${option['name']}. ${_extractTextFromHtml(option['content']?.toString() ?? '')}')
          .join('\n');
      if (options.trim().isNotEmpty) buffer.writeln('选项：\n$options');
    }

    return buffer.toString().trim();
  }

  /// 把 AI 答案写入答题数据
  void _applyAiAnswer(dynamic quiz, int index, AiAnswer answer) {
    final type = quiz['type'] as int? ?? -1;
    final answers = quiz['answer'] as List?;
    final options = answers ?? [];

    switch (type) {
      case 0: // 单选题
      case 1: // 多选题
      case 3: // 判断题
      case 16: // 判断题
        if (answer.options.isNotEmpty && options.isNotEmpty) {
          final valid = answer.options.where((name) {
            return options.any((option) => option['name']?.toString() == name);
          }).toList();
          if (valid.isNotEmpty) {
            quiz['personAnswer']['myoption'] =
                (type == 0 || type == 3 || type == 16)
                    ? valid.first
                    : (valid..sort()).join();
          }
        }
        break;

      case 2: // 填空题
      case 9: // 分录题
      case 10: // 资料题
        final blanks = quiz['personAnswer']['blankAnswer'] as List?;
        if (blanks != null) {
          for (var i = 0; i < blanks.length; i++) {
            final value = i < answer.blanks.length ? answer.blanks[i] : '';
            if (value.isEmpty) continue;
            blanks[i]['content'] = value;
            _controllers['blank_${index}_$i']?.text = value;
          }
        }
        break;

      case 4: // 简答题
      case 5: // 名词解释
      case 6: // 论述题
      case 7: // 计算题
      case 18: // 口语题
        if (answer.text.isNotEmpty) {
          quiz['personAnswer']['content'] = answer.text;
          _controllers['short_$index']?.text = answer.text;
        }
        break;
    }
  }

  /// 展示某道题的解析
  void _showExplanation(int index) {
    final answer = _aiAnswers[index];
    if (answer == null) {
      _snack('该题暂无 AI 解析');
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final details = <String>[];
    if (answer.options.isNotEmpty) details.add('答案：${answer.options.join('')}');
    if (answer.blanks.isNotEmpty) details.add('填空：${answer.blanks.join(' / ')}');
    if (answer.text.isNotEmpty) details.add('答案：${answer.text}');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '第 ${index + 1} 题 · AI 解析',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...details.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText(
                  line,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            if (answer.explanation.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              SelectableText(
                answer.explanation,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAiNotConfiguredDialog() async {
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未选择 AI 模型'),
        content: const Text('请先在「设置 - AI 调用设置」中拉取并选择模型，然后再生成答案。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );

    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiSettingPage()),
      );
      if (mounted) setState(() {});
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSubmitResult() {    if (!mounted) return;

    final successCount = _totalCount - _failedAccounts.length;
    String message = '答案提交完成！\n成功: $successCount/$_totalCount';
    if (_failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${_failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == _totalCount ? '全部提交成功' : '部分失败',
          style: TextStyle(
            color: successCount == _totalCount 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).colorScheme.error,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
  // ==================== 渲染层 ====================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.active.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_quizList.isNotEmpty)
              Text(
                '共 ${_quizList.length} 题 · ${problemTypeSummary()}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          if (_aiAnswers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: MetaChip(
                label: 'AI 已解 ${_aiAnswers.length}',
                icon: Icons.auto_awesome,
                color: cs.primary,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const ListSkeleton(count: 3, itemHeight: 180)
          : _errorMessage != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: '加载失败',
                  description: _errorMessage,
                  actionLabel: '重新加载',
                  onAction: _loadQuizData,
                )
              : _quizList.isEmpty
                  ? const EmptyState(
                      icon: Icons.quiz_outlined,
                      title: '暂无题目',
                      description: '老师尚未发布题目',
                    )
                  : Column(
                      children: [
                        if (_activeData != null)
                          CountdownDisplay(
                            timeNotifier: _remainingTimeNotifier,
                            isManualEnd: _isManualEnd,
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.sm,
                              bottom: AppSpacing.sm,
                            ),
                            itemCount: _quizList.length,
                            itemBuilder: (context, index) =>
                                _buildQuizItem(_quizList[index], index),
                          ),
                        ),
                        _buildBottomBar(context),
                      ],
                    ),
    );
  }

  /// 题型概览，如「3 选择题 · 2 填空题」
  String problemTypeSummary() {
    final counts = <String, int>{};
    for (final quiz in _quizList) {
      final name = problemTypeName(quiz['type'] as int? ?? -1);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.value} ${e.key}').join(' · ');
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AccountsSelector(
                  onSelectionChanged: (selected) {
                    setState(() => _selectedAccounts = selected);
                  },
                  initiallyExpanded: false,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ValueListenableBuilder<bool>(
                valueListenable: AiSetting.enabledNotifier,
                builder: (context, aiEnabled, _) {
                  if (!aiEnabled) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: FilledButton.tonalIcon(
                      onPressed: _isGeneratingAi || _isSubmitting
                          ? null
                          : _generateAiAnswers,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: _isGeneratingAi
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 20),
                      label: Text(
                        _isGeneratingAi ? 'AI 正在解题…' : 'AI 一键生成答案与解析',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  );
                },
              ),
              FilledButton(
                onPressed: _isSubmitting ? null : _submitAnswersForAllAccounts,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _selectedAccounts.isEmpty
                            ? '提交'
                            : '提交（${_selectedAccounts.length} 个账号）',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuizItem(dynamic quiz, int index) {
    final quizType = quiz['type'] as int? ?? -1;
    final isMust = quiz['ismust'] == 1;
    final aiAnswer = _aiAnswers[index];
    final hasAi = aiAnswer != null;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm - 2,
      ),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- 题头 ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuestionBadge(index: index + 1, highlighted: hasAi),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MetaChip(
                          label: problemTypeName(quizType),
                          color: cs.primary,
                        ),
                        if (isMust) MetaChip(label: '必答', color: cs.error),
                        if (hasAi)
                          MetaChip(
                            label: 'AI 已解',
                            icon: Icons.auto_awesome,
                            color: cs.tertiary,
                          ),
                      ],
                    ),
                  ),
                  if (hasAi)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.lightbulb_outline_rounded,
                          color: cs.tertiary, size: 22),
                      tooltip: '查看解析',
                      onPressed: () => _showExplanation(index),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- 题干 ----
              SelectionArea(
                child: Html(
                  data: quiz['content'] ?? '',
                  style: {
                    'body': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      fontSize: FontSize(15.5),
                      lineHeight: const LineHeight(1.55),
                      color: cs.onSurface,
                    ),
                  },
                  extensions: [
                    ImageExtension(
                      builder: (context) {
                        final imageUrl = CXImageApi.toNewImageUrl(
                          context.attributes['src'] ?? '',
                        );
                        return Image.network(
                          imageUrl,
                          headers: HeadersManager.chaoxingHeaders,
                          width: 80,
                          alignment: Alignment.bottomCenter,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- 作答区 ----
              _buildQuizContent(quiz, index),

              // ---- AI 解析 ----
              if (hasAi && aiAnswer.explanation.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  onTap: () => _showExplanation(index),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 15,
                          color: cs.onTertiaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            aiAnswer.explanation,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildQuizContent(dynamic quiz, int index) {
    final quizType = quiz['type'];

    switch (quizType) {
      case 0: // 单选题
      case 3: // 判断题
      case 16: // 判断题
        return _buildSingleChoiceOptions(quiz, index);
      case 1: // 多选题
        return _buildMultipleChoiceOptions(quiz, index);
      case 2: // 填空题
        return _buildBlankAnswerInputs(quiz, index);
      case 4: // 简答题
        return _buildShortAnswerInput(quiz, index);
      default:
        return Text(
          '暂不支持此题型',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        );
    }
  }

  /// 选项行（单选/多选共用外观）
  Widget _optionTile({
    required String label,
    required Widget content,
    required bool selected,
    required bool isAnswer,
    required VoidCallback onTap,
    Widget? control,
  }) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final Color border;
    if (selected) {
      bg = cs.primaryContainer.withValues(alpha: 0.7);
      border = cs.primary;
    } else {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.4);
      border = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md - 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: border, width: selected ? 1.6 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.xs - 2),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: content),
                if (control != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  control,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleChoiceOptions(dynamic quiz, int quizIndex) {
    final answers = quiz['answer'] as List?;
    if (answers == null || answers.isEmpty) {
      return Text(
        '无选项',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final current = quiz['personAnswer']['myoption'] as String?;

    return Column(
      children: answers.map((option) {
        final optionLabel = _getOptionLabel(option, quiz['type']);
        final isAnswer = option['isanswer'] == true;
        final isSelected = current == option['name'];

        return _optionTile(
          label: optionLabel,
          selected: isSelected,
          isAnswer: isAnswer,
          onTap: () {
            setState(() {
              // 再次点击已选项可取消
              quiz['personAnswer']['myoption'] =
                  isSelected ? '' : (option['name'] ?? '');
            });
          },
          content: Html(
            data: option['content'] ?? '',
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(15),
                color: cs.onSurface,
              ),
            },
            extensions: [
              ImageExtension(
                builder: (context) {
                  final imageUrl =
                      CXImageApi.toNewImageUrl(context.attributes['src'] ?? '');
                  return Image.network(
                    imageUrl,
                    headers: HeadersManager.chaoxingHeaders,
                    width: 60,
                    alignment: Alignment.bottomCenter,
                  );
                },
              ),
            ],
          ),
          control: AnimatedContainer(
            duration: AppDuration.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? cs.primary : Colors.transparent,
              border: Border.all(
                color: isSelected ? cs.primary : cs.outline,
                width: 2,
              ),
            ),
            child: isSelected
                ? Icon(Icons.circle, size: 8, color: cs.onPrimary)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultipleChoiceOptions(dynamic quiz, int quizIndex) {
    final answers = quiz['answer'] as List?;
    if (answers == null || answers.isEmpty) {
      return Text(
        '无选项',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final selectedOptions =
        (quiz['personAnswer']['myoption'] as String?)?.split('') ?? [];

    return Column(
      children: answers.map((option) {
        final optionLabel = _getOptionLabel(option, quiz['type']);
        final isAnswer = option['isanswer'] == true;
        final isSelected = selectedOptions.contains(option['name']);

        return _optionTile(
          label: optionLabel,
          selected: isSelected,
          isAnswer: isAnswer,
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedOptions.remove(option['name']);
              } else {
                if (!selectedOptions.contains(option['name'])) {
                  selectedOptions.add(option['name']);
                }
              }
              selectedOptions.sort();
              quiz['personAnswer']['myoption'] = selectedOptions.join();
            });
          },
          content: Html(
            data: option['content'] ?? '',
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(15),
                color: cs.onSurface,
              ),
            },
            extensions: [
              ImageExtension(
                builder: (context) {
                  final imageUrl =
                      CXImageApi.toNewImageUrl(context.attributes['src'] ?? '');
                  return Image.network(
                    imageUrl,
                    headers: HeadersManager.chaoxingHeaders,
                    width: 60,
                    alignment: Alignment.bottomCenter,
                  );
                },
              ),
            ],
          ),
          control: AnimatedContainer(
            duration: AppDuration.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: isSelected ? cs.primary : Colors.transparent,
              border: Border.all(
                color: isSelected ? cs.primary : cs.outline,
                width: 2,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                : null,
          ),
        );
      }).toList(),
    );
  }

  /// 从HTML中提取纯文本
  String _extractTextFromHtml(String html) {
    try {
      String text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return text;
    } catch (e) {
      return html;
    }
  }

  /// 从HTML中提取图片URL列表
  List<String> _extractImageUrls(String html) {
    final urls = <String>[];
    try {
      final regex = RegExp("<img[^>]+src=[\"']([^\"']+)[\"']");
      for (final match in regex.allMatches(html)) {
        final url = match.group(1);
        if (url != null && url.isNotEmpty) {
          urls.add(CXImageApi.toNewImageUrl(url));
        }
      }
    } catch (e) {
      logger.e('提取图片URL失败: $e');
    }
    return urls;
  }

  /// 放大图片对话框
  void _showImageDialog(String url, String heroTag) {
    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black26,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Hero(
                tag: heroTag,
                child: Image.network(
                  url,
                  headers: HeadersManager.chaoxingHeaders,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 为简答题选择并上传图片
  Future<void> _pickImages(dynamic quiz, int quizIndex) async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 80);

      if (images.isEmpty) return;

      final uploadFutures = images.map((image) async {
        try {
          final file = File(image.path);
          final api = CXImageApi();
          // FIXME 所有的图片都是当前账号上传的（学习通目前没有对于图片的权鉴）
          final objectId = await api.uploadImage(file);
          if (objectId != null) {
            return {'image': image, 'objectId': objectId};
          }
          return null;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('图片上传失败：${image.path}')),
            );
          }
          return null;
        }
      }).toList();

      final results = await Future.wait(uploadFutures);

      if (!mounted) return;
      setState(() {
        for (final result in results) {
          if (result != null && result['objectId'] != null) {
            final xfile = result['image'] as XFile;
            final objectId = result['objectId'] as String;
            quiz['personAnswer']['recs'].add({
              'name': xfile.name,
              'objectid': objectId,
              'suffix': xfile.path.split('.').last,
              'type': '1',
              'preview': '',
              'thumbnail': '',
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
  }

  /// 删除简答题的图片
  void _removeShortAnswerImage(dynamic quiz, int index) {
    setState(() {
      quiz['personAnswer']['recs'].removeAt(index);
    });
  }

  Widget _buildBlankAnswerInputs(dynamic quiz, int quizIndex) {
    final blankAnswers = quiz['personAnswer']['blankAnswer'] as List?;
    final correctAnswers = quiz['answer'] as List?;
    if (blankAnswers == null || blankAnswers.isEmpty) {
      return Text(
        '无填空',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Column(
      children: blankAnswers.asMap().entries.map((entry) {
        final index = entry.key;
        final blank = entry.value;
        final correctAnswer = correctAnswers != null && index < correctAnswers.length
            ? correctAnswers[index]['content'] ?? ''
            : '';

        final hintText = correctAnswer.isNotEmpty
            ? _extractTextFromHtml(correctAnswer).split(';').first.trim()
            : '请输入答案';
        final imageUrls =
            correctAnswer.isNotEmpty ? _extractImageUrls(correctAnswer) : <String>[];

        final controllerKey = 'blank_${quizIndex}_$index';
        final controller = _controllers.putIfAbsent(
          controllerKey,
          () => TextEditingController(text: blank['content'] ?? ''),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '第 ${index + 1} 空',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                children: [
                  TextField(
                    key: ValueKey(controllerKey),
                    maxLines: imageUrls.isNotEmpty ? 2 : 1,
                    decoration: InputDecoration(
                      hintText: hintText,
                      contentPadding: imageUrls.isNotEmpty
                          ? const EdgeInsets.fromLTRB(14, 14, 14, 60)
                          : const EdgeInsets.all(14),
                    ),
                    controller: controller,
                    onChanged: (value) {
                      setState(() => blank['content'] = value);
                    },
                  ),
                  if (imageUrls.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(maxHeight: 50),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: imageUrls.asMap().entries.map((imgEntry) {
                              final imgIndex = imgEntry.key;
                              final url = imgEntry.value;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () => _showImageDialog(
                                    url,
                                    'blank_image_${quizIndex}_${index}_$imgIndex',
                                  ),
                                  child: Hero(
                                    tag: 'blank_image_${quizIndex}_${index}_$imgIndex',
                                    child: Image.network(
                                      url,
                                      headers: HeadersManager.chaoxingHeaders,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildShortAnswerInput(dynamic quiz, int quizIndex) {
    final correctAnswers = quiz['answer'] as List?;
    final correctAnswer = correctAnswers != null && correctAnswers.isNotEmpty
        ? correctAnswers[0]['answer'] ?? ''
        : '';

    final controllerKey = 'short_$quizIndex';
    final controller = _controllers.putIfAbsent(
      controllerKey,
      () => TextEditingController(text: quiz['personAnswer']['content'] ?? ''),
    );

    final hintText =
        correctAnswer.isNotEmpty ? _extractTextFromHtml(correctAnswer) : '请输入答案';
    final imageUrls =
        correctAnswer.isNotEmpty ? _extractImageUrls(correctAnswer) : <String>[];
    final uploadedImages = quiz['personAnswer']['recs'] as List? ?? [];
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 160,
                child: Stack(
                  children: [
                    TextField(
                      key: ValueKey(controllerKey),
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: hintText,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      controller: controller,
                      onChanged: (value) {
                        setState(() => quiz['personAnswer']['content'] = value);
                      },
                    ),
                    if (imageUrls.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(maxHeight: 60),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: imageUrls.asMap().entries.map((entry) {
                                final index = entry.key;
                                final url = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () => _showImageDialog(
                                      url,
                                      'quiz_image_${quizIndex}_$index',
                                    ),
                                    child: Hero(
                                      tag: 'quiz_image_${quizIndex}_$index',
                                      child: Image.network(
                                        url,
                                        headers: HeadersManager.chaoxingHeaders,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                onTap: () => _pickImages(quiz, quizIndex),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    color: cs.onSurfaceVariant,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (uploadedImages.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: uploadedImages.length,
              itemBuilder: (context, index) {
                final imageInfo = uploadedImages[index];
                final objectId = imageInfo['objectid'] as String?;
                if (objectId == null || objectId.isEmpty) {
                  return const SizedBox.shrink();
                }
                final imageUrl = CXImageApi.getImageUrl(objectId);
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _showImageDialog(
                          imageUrl,
                          'short_answer_image_${quizIndex}_$index',
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Hero(
                            tag: 'short_answer_image_${quizIndex}_$index',
                            child: Image.network(
                              imageUrl,
                              headers: HeadersManager.chaoxingHeaders,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: GestureDetector(
                          onTap: () => _removeShortAnswerImage(quiz, index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: cs.error,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: cs.onError,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  String _getOptionLabel(dynamic option, int quizType) {
    if (quizType == 16) {
      final optionName = option['name'] ?? '';
      return optionName == '1' ? '对' : '错';
    }
    return option['name'] ?? '';
  }
}

/// 题号徽章
class _QuestionBadge extends StatelessWidget {
  final int index;
  final bool highlighted;

  const _QuestionBadge({required this.index, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlighted
              ? [cs.tertiary, Color.lerp(cs.tertiary, cs.primary, 0.5)!]
              : [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.5)!],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs + 2),
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: highlighted ? cs.onTertiary : cs.onPrimary,
        ),
      ),
    );
  }
}
