import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../session/account.dart';
import '../../platform.dart';

class AccountsSelector extends StatefulWidget {
  final ValueChanged<List<User>> onSelectionChanged;
  final String title;
  final bool initiallyExpanded;

  const AccountsSelector({
    super.key,
    required this.onSelectionChanged,
    this.title = '选择参加的账号',
    this.initiallyExpanded = true,
  });

  @override
  State<AccountsSelector> createState() => _AccountsSelectorState();
}

class _AccountsSelectorState extends State<AccountsSelector> {
  List<User> _allAccounts = [];
  List<User> _selectedAccounts = [];
  User? _currentUser;
  bool _selectAll = false;
  bool _isLoading = true;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      // 获取所有账号
      List<User> allAccounts = AccountManager.getAllAccounts();
        
      // 根据当前平台过滤账号
      final currentPlatform = PlatformManager().currentPlatform;
      final platformString = currentPlatform == PlatformType.chaoxing ? 'chaoxing' : 'rainClassroom';
      _allAccounts = allAccounts.where((account) => account.platform == platformString).toList();
        
      // 获取当前账号
      String? currentUserId = AccountManager.currentSessionId;
      _currentUser = _allAccounts.isEmpty ?
      null : _allAccounts.firstWhere((user) => user.uid == currentUserId, orElse: () => _allAccounts.first,);
        
      // 默认选中所有账号
      _selectedAccounts = List.from(_allAccounts);
      _selectAll = _allAccounts.isNotEmpty;
        
      setState(() {
        _isLoading = false;
      });
        
      // 通知外部初始选中状态
      widget.onSelectionChanged(_selectedAccounts);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('加载账号失败：$e');
    }
  }

  void _updateSelectAllState() {
    _selectAll = _selectedAccounts.length == _allAccounts.length && _allAccounts.isNotEmpty;
  }

  // 全选
  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;

      if (_selectAll) {
        _selectedAccounts = List.from(_allAccounts);
      } else {
        _selectedAccounts = _currentUser != null ? [_currentUser!] : [];
      }

      widget.onSelectionChanged(_selectedAccounts);
    });
  }

  void _toggleAccountSelection(User user, bool? value) {
    // 当前用户不能被操作
    if (user == _currentUser) {
      return;
    }

    setState(() {
      if (value == true) {
        if (!_selectedAccounts.contains(user)) {
          _selectedAccounts.add(user);
        }
      } else {
        _selectedAccounts.remove(user);
      }

      // 更新全选状态
      _updateSelectAllState();
      widget.onSelectionChanged(_selectedAccounts);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _isExpanded = expanded;
              });
            },
            title: Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('全选'),
                Checkbox(
                  value: _selectAll,
                  onChanged: _toggleSelectAll,
                  fillColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return Theme.of(context).colorScheme.primary;
                      }
                      return Colors.transparent;
                    },
                  ),
                ),
                // 添加展开/收起图标
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey,
                ),
              ],
            ),
            children: [
              if (_allAccounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    '没有账户',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              else
                ..._allAccounts.map((user) {
                  bool isCurrentUser = user == _currentUser;
                  bool isSelected = _selectedAccounts.contains(user);

                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Text(user.name),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    value: isSelected,
                    onChanged: isCurrentUser ? null : (bool? value) => _toggleAccountSelection(user, value),
                    enabled: !isCurrentUser,
                    checkColor: isCurrentUser ? Colors.white : null,
                    activeColor: Theme.of(context).colorScheme.primary,
                  );
                }),
            ],
          ),
        )
    );
  }
}