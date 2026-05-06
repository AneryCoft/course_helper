import 'package:flutter/material.dart';

import '../../../api/quiz.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../widget/accounts_selector.dart';

class VotePage extends StatefulWidget {
  final Active active;
  final String courseId;
  final String classId;
  
  const VotePage({
    super.key, 
    required this.active,
    required this.courseId,
    required this.classId
  });

  @override
  State<VotePage> createState() => _VotePageState();
}

class _VotePageState extends State<VotePage> {
  // 页面状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  
  // 批量提交状态
  int _totalCount = 0;
  final List<String> _failedAccounts = [];
  
  // 投票数据
  Map<String, dynamic>? _voteData; 
  List<Map<String, dynamic>> _options = [];
  String? _selectedOption;
  bool _isAnonymous = false;
  
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
    _loadVoteData();
  }

  Future<void> _loadVoteData() async {
    try {
      final data = await QuizApi.getQuizDetail(widget.active.id, true);
      if (data != null && data['questionlist'] != null && data['questionlist'].isNotEmpty) {
        final question = data['questionlist'][0];
        final options = question['answer'] as List?;
        
        if (options != null && options.isNotEmpty) {
          setState(() {
            _voteData = data;
            _options = options.map((opt) => Map<String, dynamic>.from(opt)).toList();
            _isAnonymous = data['pptActive']?['isanony'] == 1;
            _isLoading = false;
          });
          
          // 检查当前用户是否已参与投票
          if (_voteData!['pptUserAttend'] != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('当前用户已参与投票')),
              );
            }
            // 从初始选中列表中移除当前用户
            if (_currentUser != null) {
              _initialSelectedAccounts = AccountManager.allAccounts
                  .where((user) => user.uid != _currentUser!.uid)
                  .toList();
            }
          }
        } else {
          setState(() {
            _errorMessage = '未找到投票选项';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = '获取投票数据失败';
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

  Future<void> _submitForAllAccounts() async {
    if (_selectedAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择至少一个账号')),
        );
      }
      return;
    }
    
    if (_selectedOption == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择一个选项')),
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
          final result = await QuizApi.submitVote(
            widget.courseId,
            widget.classId,
            widget.active.id,
            _voteData!['questionlist'][0]['id'].toString(),
            _selectedOption!,
          );
          
          if (result == null || result['status'] != 1) {
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
    String message = '投票提交完成！\n成功: $successCount/$_totalCount';
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

  Widget _buildOptionCard(Map<String, dynamic> option, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: RadioListTile<String>(
        title: Text(
          '${option['content']}',
          style: const TextStyle(fontSize: 16),
        ),
        value: option['name'],
        activeColor: Theme.of(context).colorScheme.primary,
        controlAffinity: ListTileControlAffinity.trailing,
        toggleable: true,
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
            padding: const EdgeInsets.all(16),
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
                            onPressed: _loadVoteData,
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
                      // 匿名提示
                      if (_isAnonymous)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_off,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '匿名投票',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // 选项列表
                      RadioGroup<String>(
                        groupValue: _selectedOption,
                        onChanged: _isSubmitting ? (value) {} : (value) {
                          setState(() {
                            _selectedOption = value;
                          });
                        },
                        child: Column(
                          children: _options.asMap().entries.map((entry) {
                            return _buildOptionCard(entry.value, entry.key);
                          }).toList(),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 账号选择器
                      AccountsSelector(
                        onSelectionChanged: (selected) {
                          setState(() {
                            _selectedAccounts = selected;
                          });
                        },
                        initiallyExpanded: true,
                        initialSelected: _initialSelectedAccounts,
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
                      : const Text('提交投票', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
