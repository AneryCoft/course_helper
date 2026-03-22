import 'package:flutter/material.dart';
import 'dart:async';

import '../../../api/topic_discuss.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../widget/accounts_selector.dart';
import '../widget/avatar.dart';

class TopicDiscussPage extends StatefulWidget {
  final Active active;
  
  const TopicDiscussPage({super.key, required this.active});

  @override
  State<TopicDiscussPage> createState() => _TopicDiscussPageState();
}

class _TopicDiscussPageState extends State<TopicDiscussPage> {
  // 页面状态
  bool _isLoading = true;
  bool _isPosting = false;
  String? _errorMessage;
  
  // 批量评论状态
  int _totalCount = 0;
  final List<String> _failedAccounts = [];
  
  // 主题数据
  late final String _topicId = widget.active.extras['topicId'] ?? '';
  Map<String, dynamic>? _topicData;
  late String _topicUuid;
  bool _canAnonymous = false;
  // List<Map<String, dynamic>> _replies = [];
  List<dynamic> _replies = [];

  // 账号选择
  List<User> _selectedAccounts = [];
  User? _currentUser;
  
  // 评论输入
  bool _isAnonymous = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    TopicDiscussApi.updateUser();
    await _loadTopicData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadTopicData() async {
    try {
      final topicData = await TopicDiscussApi.getTopic(_topicId);
      if (topicData != null && topicData['result'] == 1) {
        _topicData = topicData['data'];
        _topicUuid = _topicData!['uuid'] ?? '';
        _canAnonymous = _topicData!['userAuth']['operationAuth']['canAnonymousAddReply'] == 1;
        final repliesData = await TopicDiscussApi.getReplies(_topicUuid);
        if (repliesData != null && repliesData['result'] == 1) {
          setState(() {
            _replies = repliesData['data']['list'];
            _isLoading = false;
          });
        } else {
          setState(() {
            _replies = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = '获取主题数据失败';
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

  Future<void> _postCommentForAllAccounts() async {
    if (_commentController.text.trim().isEmpty) {
      return;
    }
    if (_selectedAccounts.isEmpty) {
      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择至少一个账号')),
        );
      }
      return;
    }
    setState(() {
      _isPosting = true;
      _totalCount = _selectedAccounts.length;
      _failedAccounts.clear();
    });

    try {
      for (var account in _selectedAccounts) {
        AccountManager.setCurrentSessionTemp(account.uid);
              
        // 更新 TopicDiscussAPI 的用户信息
        TopicDiscussApi.updateUser();
        
        try {
          final result = await TopicDiscussApi.addReply(
            _commentController.text.trim(),
            _isAnonymous,
            _topicUuid,
          );
          
          if (result != null && result['result'] == 1) {
            // 发布成功
          } else {
            _failedAccounts.add('${account.name}: ${result?['errorMsg'] ?? '发布失败'}');
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
      
      // 重新加载评论
      await _reloadComments();
      
      _showMultiPostResult();
    } finally {
      // 确保状态总是能被重置
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  Future<void> _reloadComments() async {
    try {
      final repliesData = await TopicDiscussApi.getReplies(_topicUuid);
      if (repliesData != null && repliesData['result'] == 1) {
        setState(() {
          _replies = repliesData['data']['list'];
        });
      }
    } catch (e) {
      debugPrint('重新加载评论失败: $e');
    }
  }

  void _showMultiPostResult() {
    if (!mounted) return;

    final successCount = _totalCount - _failedAccounts.length;
    String message = '评论发布完成！\n成功: $successCount/$_totalCount';
    if (_failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${_failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == _totalCount ? '全部发布成功' : '部分失败',
          style: TextStyle(
            color: successCount == _totalCount 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).colorScheme.error,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicHeader() {
    if (_topicData == null) return const SizedBox.shrink();
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarWidget(
                  key: ValueKey(_topicData!['photo']),
                  imageUrl: _topicData!['photo'],
                  isLoading: _isLoading,
                  size: 60,
                  borderRadius: 8,
                  iconSize: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _topicData!['createrName'] ?? '未知发布者',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _topicData!['ftime'],
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (_topicData!['title'] != null)
              Text(
                _topicData!['title'],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 10),
            SelectableText(
              _topicData!['text_content'] ?? '',
              style: TextStyle(fontSize: 16),
            ),
            // TODO [img_data]
          ],
        ),
      ),
    );
  }

  Widget _buildReplyItem(Map<String, dynamic> reply) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarWidget(
                  key: ValueKey(reply['photo']),
                  imageUrl: reply['photo'],
                  size: 48,
                  borderRadius: 8,
                  iconSize: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reply['creater_name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Text(
                  reply['ftime'],
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              reply['content'] ?? '',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  /*
  Widget _buildProgressCard() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: _totalCount > 0 ? _postedCount / _totalCount : 0,
              backgroundColor: Theme.of(context).dividerColor,
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 10),
            Text(
              '发布进度: $_postedCount/$_totalCount',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (_failedAccounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '失败: ${_failedAccounts.length}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
  */

  Widget _buildBottomCommentInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_canAnonymous)
            IconButton(
              icon: Icon(
                _isAnonymous ? Icons.person_off : Icons.person,
                color: _isAnonymous 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: () {
                setState(() {
                  _isAnonymous = !_isAnonymous;
                });
              },
              tooltip: '匿名',
            ),
          
          // 输入框
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  hintText: '请输入评论...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _postCommentForAllAccounts(),
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 发布按钮
          IconButton(
            icon: Icon(
              Icons.send,
              color: _commentController.text.trim().isNotEmpty && !_isPosting
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              if (_commentController.text.trim().isEmpty || _isPosting) {
                return;
              }
              _postCommentForAllAccounts();
            },
          ),
        ],
      ),
    );
  }
    
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('主题讨论'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator()),
                  
                  if (_errorMessage != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                  
                  if (!_isLoading && _topicData != null)
                    _buildTopicHeader(),
                  
                  AccountsSelector(
                    onSelectionChanged: (selected) {
                      setState(() {
                        _selectedAccounts = selected;
                      });
                    },
                    initiallyExpanded: false
                  ),
                  
                  const SizedBox(height: 20),
                  
                  if (!_isLoading && _replies.isNotEmpty)
                    Column(
                      children: _replies.map((reply) => _buildReplyItem(reply)).toList(),
                    ),
                ],
              ),
            ),
          ),
          _buildBottomCommentInput(),
        ],
      ),
    );
  }
}