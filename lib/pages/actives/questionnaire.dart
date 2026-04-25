import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../../api/api_service.dart';
import '../../../api/quiz.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../widget/accounts_selector.dart';

class QuestionnairePage extends StatefulWidget {
  final Active active;
  final String courseId;
  final String classId;
  
  const QuestionnairePage({
    super.key, 
    required this.active,
    required this.courseId,
    required this.classId
  });

  @override
  State<QuestionnairePage> createState() => _QuestionnairePageState();
}

class _QuestionnairePageState extends State<QuestionnairePage> {
  // 页面状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  
  // 批量提交状态
  int _totalCount = 0;
  final List<String> _failedAccounts = [];
  
  // 问卷数据
  List<dynamic> _questionList = [];
  Map<String, dynamic>? _questionnaireData;
  
  // 输入控制器缓存
  final Map<String, TextEditingController> _controllers = {};
  
  // 答案：questionId -> answer
  final Map<String, dynamic> _answers = {};
  
  // 账号选择
  List<User> _selectedAccounts = [];
  User? _currentUser;
  List<User>? _initialSelectedAccounts;
  
  @override
  void initState() {
    super.initState();
    final currentUserId = AccountManager.currentSessionId;
    if (currentUserId != null) {
      _currentUser = AccountManager.getAccountById(currentUserId);
    }
    _loadQuestionnaireData();
  }
  
  @override
  void dispose() {
    // 清理所有输入控制器
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  Future<void> _loadQuestionnaireData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      final data = await QuizApi.getQuizDetail(widget.active.id, true);
      
      if (data != null && data['questionlist'] != null) {
        setState(() {
          _questionList = data['questionlist'] as List;
          _questionnaireData = data;
          _isLoading = false;
          
          // 检查当前用户是否已参与问卷
          if (_questionnaireData!['pptUserAttend'] != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('当前用户已参与问卷')),
              );
            }
            // 从初始选中列表中移除当前用户
            if (_currentUser != null) {
              _initialSelectedAccounts = AccountManager.getAllAccounts()
                  .where((user) => user.uid != _currentUser!.uid)
                  .toList();
            }
          }
          
          // 初始化答案存储
          for (var question in _questionList) {
            final questionId = question['id'].toString();
            final questionType = question['type'];
            
            if (questionType == 0 || questionType == 16) {
              // 单选题、判断题
              _answers[questionId] = '';
            } else if (questionType == 1) {
              // 多选题
              _answers[questionId] = <String>[];
            } else if (questionType == 4) {
              // 简答题
              _answers[questionId] = '';
            }
          }
        });
      } else {
        setState(() {
          _errorMessage = '加载问卷数据失败';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.active.name),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 主要内容
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadQuestionnaireData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                )
              : _questionList.isEmpty
                  ? const Center(child: Text('暂无题目'))
                  : Column(
                      children: [
                        // 题目列表
                        Expanded(
                          child: ListView.builder(
                            itemCount: _questionList.length,
                            itemBuilder: (context, index) {
                              return _buildQuestionItem(_questionList[index], index);
                            },
                          ),
                        ),
                        
                        // 账号选择器
                        AccountsSelector(
                          onSelectionChanged: (selected) {
                            setState(() {
                              _selectedAccounts = selected;
                            });
                          },
                          initiallyExpanded: false,
                          initialSelected: _initialSelectedAccounts,
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // 提交按钮
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitAnswersForAllAccounts,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: _isSubmitting
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('提交中...'),
                                    ],
                                  )
                                : const Text('提交', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionItem(dynamic question, int index) {
    final questionType = question['type'];
    final isMust = question['ismust'] == 1;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${index + 1}. ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isMust)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '必答',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${_getQuestionTypeName(questionType)}] ',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Html(
                        data: question['content'] ?? '',
                        extensions: [
                          ImageExtension(
                            builder: (context) {
                              final imageUrl = ApiService.toNewImageUrl(context.attributes['src'] ?? '');
                              return Image.network(
                                imageUrl,
                                headers: HeadersManager.chaoxingHeaders,
                                width: 80,
                                alignment: Alignment.bottomCenter
                              );
                            }
                          )
                        ]
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildQuestionContent(question, index),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionContent(dynamic question, int index) {
    final questionType = question['type'];
    switch (questionType) {
      case 0: // 单选题
        return _buildSingleChoiceOptions(question);
      case 1: // 多选题
        return _buildMultipleChoiceOptions(question);
      case 4: // 简答题
        return _buildShortAnswerInput(question, index);
      case 16: // 判断题
        return _buildSingleChoiceOptions(question);
      default:
        return const Text('暂不支持此题型');
    }
  }

  Widget _buildSingleChoiceOptions(dynamic question) {
    final questionId = question['id'].toString();
    final answers = question['answer'] as List?;
    if (answers == null || answers.isEmpty) {
      return const Text('无选项');
    }
    return RadioGroup<String>(
      groupValue: _answers[questionId],
      onChanged: (String? value) {
        setState(() {
          _answers[questionId] = value ?? '';
        });
      },
      child: Column(
        children: answers.map((option) {
          final optionLabel = option['name'] ?? '';
          final isSelected = _answers[questionId] == option['name'];
          return RadioListTile<String>(
            title: Html(
              data: option['content'] ?? '',
              extensions: [
                ImageExtension(
                  builder: (context) {
                    final imageUrl = ApiService.toNewImageUrl(context.attributes['src'] ?? '');
                    return Image.network(
                      imageUrl,
                      headers: HeadersManager.chaoxingHeaders,
                      width: 60,
                      alignment: Alignment.bottomCenter
                    );
                  }
                )
              ]
            ),
            secondary: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                optionLabel,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            value: option['name'],
            activeColor: Theme.of(context).colorScheme.primary,
            controlAffinity: ListTileControlAffinity.trailing,
            toggleable: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMultipleChoiceOptions(dynamic question) {
    final questionId = question['id'].toString();
    final answers = question['answer'] as List?;
    if (answers == null || answers.isEmpty) {
      return const Text('无选项');
    }
    
    // 确保答案是列表
    if (_answers[questionId] is! List) {
      _answers[questionId] = <String>[];
    }
    
    return Column(
      children: answers.map((option) {
        final optionLabel = option['name'] ?? '';
        final selectedOptions = _answers[questionId] as List<String>;
        final isSelected = selectedOptions.contains(option['name']);
        return CheckboxListTile(
          title: Html(
            data: option['content'] ?? '',
            extensions: [
              ImageExtension(
                builder: (context) {
                  final imageUrl = ApiService.toNewImageUrl(context.attributes['src'] ?? '');
                  return Image.network(
                    imageUrl,
                    headers: HeadersManager.chaoxingHeaders,
                    width: 60,
                    alignment: Alignment.bottomCenter
                  );
                }
              )
            ]
          ),
          secondary: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              optionLabel,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          value: isSelected,
          onChanged: (value) {
            setState(() {
              final selectedOptions = _answers[questionId] as List<String>;
              if (value == true) {
                if (!selectedOptions.contains(option['name'])) {
                  selectedOptions.add(option['name']);
                }
              } else {
                selectedOptions.remove(option['name']);
              }
            });
          },
          activeColor: Theme.of(context).colorScheme.primary,
        );
      }).toList(),
    );
  }

  Widget _buildShortAnswerInput(dynamic question, int questionIndex) {
    final questionId = question['id'].toString();
    final controller = _controllers.putIfAbsent(questionId,
      () => TextEditingController(text: _answers[questionId] ?? ''));
    return TextField(
      key: ValueKey(questionId),
      maxLines: 5,
      decoration: InputDecoration(
        hintText: '请输入答案',
        border: const OutlineInputBorder(),
        hintStyle: TextStyle(color: Colors.grey[400]),
      ),
      controller: controller,
      onChanged: (value) {
        setState(() {
          _answers[questionId] = value;
        });
      },
    );
  }

  String _getQuestionTypeName(int type) {
    const typeNames = {
      0: '单选题',
      1: '多选题',
      4: '简答题',
      16: '判断题'
    };
    return typeNames[type] ?? '未知题型';
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
    
    setState(() {
      _isSubmitting = true;
      _totalCount = _selectedAccounts.length;
      _failedAccounts.clear();
    });

    try {
      for (var account in _selectedAccounts) {
        AccountManager.setCurrentSessionTemp(account.uid);
        try {
          // 构造提交数据：Map<String, List<String>> answers (questionId -> [answer])
          final submitAnswers = <String, List<String>>{};
          for (var question in _questionList) {
            final questionId = question['id'].toString();
            final questionType = question['type'];
            final answer = _answers[questionId];
            
            if (answer != null) {
              if (questionType == 0 || questionType == 16) {
                // 单选题、判断题
                if (answer is String && answer.isNotEmpty) {
                  submitAnswers[questionId] = [answer];
                }
              } else if (questionType == 1) {
                // 多选题
                if (answer is List && answer.isNotEmpty) {
                  submitAnswers[questionId] = List<String>.from(answer);
                }
              } else if (questionType == 4) {
                // 简答题
                if (answer is String && answer.isNotEmpty) {
                  submitAnswers[questionId] = [answer];
                }
              }
            }
          }
          
          final result = await QuizApi.submitQuestionnaire(
            widget.courseId, 
            widget.classId, 
            widget.active.id, 
            submitAnswers
          );
          
          if (result == null || result['result'] != 1) {
            _failedAccounts.add('${account.name}: ${result?['errorMsg'] ?? '提交失败'}');
          }
        } catch (e) {
          _failedAccounts.add('${account.name}: 异常 - $e');
        } finally {
          setState(() {
          });
        }
      }
      
      // 恢复当前账号
      if (_currentUser != null) {
        AccountManager.setCurrentSessionTemp(_currentUser!.uid);
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

  void _showSubmitResult() {
    if (!mounted) return;

    final successCount = _totalCount - _failedAccounts.length;
    String message = '问卷提交完成！\n成功: $successCount/$_totalCount';
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
}
