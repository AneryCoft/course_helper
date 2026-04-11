import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../session/account.dart';

class AccountsSelector extends StatefulWidget {
  final ValueChanged<List<User>> onSelectionChanged;
  final String title;
  final bool initiallyExpanded;
  final List<User>? initialSelected;

  const AccountsSelector({
    super.key,
    required this.onSelectionChanged,
    this.title = '选择参加的账号',
    this.initiallyExpanded = true,
    this.initialSelected,
  });

  @override
  State<AccountsSelector> createState() => _AccountsSelectorState();
}

class _AccountsSelectorState extends State<AccountsSelector> {
  List<User> _allAccounts = [];
  List<User> _selectedAccounts = [];
  User? _currentUser;
  bool _isLoading = true;
  late bool _isExpanded;

  // 为tristate创造条件
  bool get _hasSelectableAccounts => _allAccounts.any((user) => user != _currentUser);
  int get _selectableCount => _allAccounts.where((user) => user != _currentUser).length;
  int get _selectedSelectableCount => _selectedAccounts.where((user) => user != _currentUser).length;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _loadAccounts();
  }

  void _loadAccounts() {
    try {
      // 获取所有账号
      _allAccounts = AccountManager.getAllAccounts();
      
      // 使用外部传入的初始选中状态，否则默认全选
      if (widget.initialSelected != null) {
        _selectedAccounts = List.from(widget.initialSelected!);
      } else {
        _selectedAccounts = List.from(_allAccounts);
      }

      final currentUserId = AccountManager.currentSessionId;
      _currentUser = AccountManager.getAccountById(currentUserId!);
    } catch (e) {
      debugPrint('加载账号失败：$e');
    }
    // 通知外部初始选中状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          widget.onSelectionChanged(_selectedAccounts);
          _isLoading = false;
        });
      }
    });
  }

  // 全选/全不选逻辑
  void _toggleSelectAll(bool? value) {
    bool selectAll = value ?? false;

    final currentUser = _currentUser;
    Set<User> newSelected = {?currentUser};

    if (selectAll) {
      for (var user in _allAccounts) {
        if (user != currentUser) {
          newSelected.add(user);
        }
      }
    }
    setState(() {
      _selectedAccounts = newSelected.toList();
      widget.onSelectionChanged(_selectedAccounts);
    });
  }

  // 单个账号选择/取消
  void _toggleAccountSelection(User user, bool? value) {
    setState(() {
      if (value == true) {
        if (!_selectedAccounts.contains(user)) {
          _selectedAccounts.add(user);
        }
      } else {
        _selectedAccounts.remove(user);
      }

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
                tristate: true,
                value: !_hasSelectableAccounts ?
                false : _selectedSelectableCount == _selectableCount ?
                true : _selectedSelectableCount == 0 ?
                false : null,
                onChanged: _hasSelectableAccounts ? _toggleSelectAll : null,
                fillColor: WidgetStateProperty.resolveWith<Color>(
                      (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).colorScheme.primary;
                    }
                    return Colors.transparent;
                  },
                ),
              ),
              // 展开/收起图标
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
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _allAccounts.length,
                itemBuilder: (context, index) {
                  final user = _allAccounts[index];
                  bool isCurrentUser = user == _currentUser;
                  bool isSelected = _selectedAccounts.contains(user);

                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Text(user.name),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                    onChanged: isCurrentUser ?
                    null : (bool? value) => _toggleAccountSelection(user, value),
                    enabled: !isCurrentUser,
                    checkColor: isCurrentUser ? Colors.white : null,
                    activeColor: Theme.of(context).colorScheme.primary,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}