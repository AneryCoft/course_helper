import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/sign_in.dart';
import '../../../api/evaluate.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../widget/accounts_selector.dart';

class EvaluatePage extends StatefulWidget {
  final Active active;
  final String courseId;
  final String classId;
  
  const EvaluatePage({
    super.key, 
    required this.active,
    required this.courseId,
    required this.classId
  });

  @override
  State<EvaluatePage> createState() => _EvaluatePageState();
}

class _EvaluatePageState extends State<EvaluatePage> {
  // 页面状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  
  // 批量提交状态
  int _totalCount = 0;
  final List<String> _failedAccounts = [];
  
  // 评分数据
  List<dynamic> _normList = [];
  bool _hasNormList = false;
  final TextEditingController _totalScoreController = TextEditingController();
  final Map<int, TextEditingController> _scoreControllers = {};
  final TextEditingController _commentController = TextEditingController();
  
  // 账号选择
  List<User> _selectedAccounts = [];
  User? _currentUser;
  
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    try {
      final data = await SignInApi.getActiveInfoWeb(widget.active.id);
      if (data != null) {
        setState(() {
          if (data['normList'] != null && data['normList'].isNotEmpty) {
            _normList = data['normList'];
            _hasNormList = true;
            
            // 初始化分项评分输入控制器
            for (int i = 0; i < _normList.length; i++) {
              _scoreControllers[i] = TextEditingController();
            }
          } else {
            _hasNormList = false;
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '获取评分信息失败';
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
  void dispose() {
    _totalScoreController.dispose();
    for (var controller in _scoreControllers.values) {
      controller.dispose();
    }
    _commentController.dispose();
    super.dispose();
  }
  
  Future<void> _submitForAllAccounts() async {
    if (_selectedAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择至少一个账号')),
        );
      }
      return;
    }
    
    int totalScore;
    List<int> scoreList = [];
    
    if (_hasNormList) {
      // 分项评分模式
      for (int i = 0; i < _normList.length; i++) {
        final maxScore = int.parse(_normList[i]['score']);
        final inputText = _scoreControllers[i]?.text.trim() ?? '';
        
        if (inputText.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('请输入第${i + 1}项评分')),
            );
          }
          return;
        }
        
        final score = int.tryParse(inputText);
        if (score == null || score < 0 || score > maxScore) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('第${i + 1}项评分必须在0-$maxScore之间')),
            );
          }
          return;
        }
        
        scoreList.add(score);
      }
      totalScore = scoreList.reduce((a, b) => a + b);
    } else {
      // 单一总分模式
      final inputText = _totalScoreController.text.trim();
      if (inputText.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入评分')),
          );
        }
        return;
      }
      
      final score = int.tryParse(inputText);
      if (score == null || score < 0 || score > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('评分必须在0-100之间')),
          );
        }
        return;
      }
      
      totalScore = score;
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
          final result = await EvaluateApi.stuSubmitAnswer(
            widget.active.id,
            widget.classId,
            widget.courseId,
            totalScore,
            content: _commentController.text,
            scoreList: scoreList
          );
          
          if (result != true) {
            _failedAccounts.add('${account.name}: 提交失败');
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
    String message = '评分提交完成！\n成功: $successCount/$_totalCount';
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
  
  Widget _buildNormItem(dynamic norm, int index) {
    final maxScore = int.parse(norm['score']);
    final content = norm['content'];
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '评分标准 ${index + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _scoreControllers[index],
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                onChanged: (value) {
                  final int? num = int.tryParse(value);
                  if (num != null && num > maxScore) {
                    final controller = _scoreControllers[index];
                    if (controller != null) {
                      controller.text = '$maxScore';
                      controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: controller.text.length),
                      );
                    }
                  }
                },
                decoration: InputDecoration(
                  labelText: '0-$maxScore',
                  border: const OutlineInputBorder(),
                  hintText: '0-$maxScore',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.active.name),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_errorMessage != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
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
                            onPressed: _initialize,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasNormList)
                        // 分项评分模式
                        ..._normList.asMap().entries.map((entry) {
                          return _buildNormItem(entry.value, entry.key);
                        })
                      else
                        // 单一总分模式
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _totalScoreController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onChanged: (value) {
                              final int? num = int.tryParse(value);
                              if (num != null && num > 100) {
                                _totalScoreController.text = '100';
                                _totalScoreController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: _totalScoreController.text.length),
                                );
                              }
                            },
                            decoration: const InputDecoration(
                              labelText: '总分 (0-100)',
                              hintText: '请输入总分',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 16),
                      
                      // 评语输入框
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _commentController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: '评语',
                            hintText: '请输入评语',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // 账号选择器
                      AccountsSelector(
                        onSelectionChanged: (selected) {
                          setState(() {
                            _selectedAccounts = selected;
                          });
                        },
                        initiallyExpanded: true,
                      ),
                      
                      const SizedBox(height: 80),
                    ],
                  ),
              ],
            ),
          ),
          
          // 提交按钮固定在底部
          if (!_isLoading && _errorMessage == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForAllAccounts,
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
            ),
        ],
      ),
    );
  }
}
