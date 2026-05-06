import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/user.dart';
import '../../session/account.dart';
import '../../api/api_service.dart';
import '../../api/image.dart';

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
  State<AccountsSelector> createState() => AccountsSelectorState();
}

class AccountsSelectorState extends State<AccountsSelector> {
  List<User> _allAccounts = [];
  List<User> _selectedAccounts = [];
  User? _currentUser;
  bool _isLoading = true;
  late bool _isExpanded;
  final Map<String, File> _userImages = {};
  final Map<String, String> _userObjectIds = {}; // uid -> objectId
  final Set<String> _uploadingUsers = {};
  final Set<String> _failedUsers = {};

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
      _allAccounts = AccountManager.allAccounts;
      
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

  void setImageForUser(String uid, File imageFile) {
    setState(() {
      _userImages[uid] = imageFile;
    });
  }

  void setObjectIdForUser(String uid, String objectId) {
    setState(() {
      if (objectId.isNotEmpty) {
        _userObjectIds[uid] = objectId;
      } else {
        _userObjectIds.remove(uid);
      }
    });
  }

  void setUploadingStatus(String uid, bool isUploading) {
    setState(() {
      if (isUploading) {
        _uploadingUsers.add(uid);
        _failedUsers.remove(uid);
      } else {
        _uploadingUsers.remove(uid);
      }
    });
  }

  void setUploadFailed(String uid) {
    setState(() {
      _uploadingUsers.remove(uid);
      _failedUsers.add(uid);
    });
  }

  /// 放大图片对话框
  void _showImageDialog(BuildContext context, String uid, String? imageUrl) {
    if (imageUrl == null && !_userImages.containsKey(uid)) return;
    
    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black12,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: _userImages.containsKey(uid)
                  ? Image.file(
                      _userImages[uid]!,
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      imageUrl!,
                      headers: HeadersManager.chaoxingHeaders,
                      fit: BoxFit.contain,
                    ),
            ),
          ),
        ),
      ),
    );
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
                        const Spacer(),
                        // 显示图片：优先显示本地文件，其次显示网络图片（objectId）
                        if (_userImages.containsKey(user.uid) || _userObjectIds.containsKey(user.uid))
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Stack(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    final imageUrl = _userImages.containsKey(user.uid)
                                        ? null
                                        : CXImageApi.getImageUrl(_userObjectIds[user.uid]!);
                                    _showImageDialog(context, user.uid, imageUrl);
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: _userImages.containsKey(user.uid)
                                        ? Image.file(
                                            _userImages[user.uid]!,
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                          )
                                        : Image.network(
                                            CXImageApi.getImageUrl(_userObjectIds[user.uid]!),
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                            headers: HeadersManager.chaoxingHeaders,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return Container(
                                                width: 40,
                                                height: 40,
                                                color: Colors.grey.shade200,
                                                child: Center(
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    value: loadingProgress.expectedTotalBytes != null
                                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                        : null,
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                width: 40,
                                                height: 40,
                                                color: Colors.grey.shade200,
                                                child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                if (_uploadingUsers.contains(user.uid))
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_failedUsers.contains(user.uid))
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle
                                      ),
                                      child: const Icon(
                                        Icons.error,
                                        size: 16,
                                        color: Colors.white
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
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