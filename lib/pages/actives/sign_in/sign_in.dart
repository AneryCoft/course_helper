import 'package:flutter/material.dart';
import 'dart:async';

import '../../../../api/sign_in.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../../widget/accounts_selector.dart';
import '../../widget/captcha.dart';
import 'normal.dart';
import 'pattern.dart';
import 'code.dart';
import 'qrcode.dart';
import 'location.dart';


class SignParams {
  final Active active;
  final String courseId;
  final String classId;
  final String cpi;

  String? validate;

  // 普通签到（拍照）
  final Map<String, String> _userObjectIds = {}; // userId -> objectId

  // 手势签到
  String pattern = '';

  // 签到码签到
  String code = '';
  int numberCount = 0;

  // 二维码签到
  String? enc;
  String? enc2;
  String? qrCodeData;

  // 位置签到
  String? address;
  double? latitude;
  double? longitude;

  SignParams({
    required this.active,
    required this.courseId,
    required this.classId,
    required this.cpi,
  });

  // 照片ID管理
  void setUserObjectId(String userId, String objectId) {
    _userObjectIds[userId] = objectId;
  }

  String? getUserObjectId(String userId) {
    return _userObjectIds[userId];
  }

  void setUserObjectIds(Map<String, String> objectIds) {
    _userObjectIds.addAll(objectIds);
  }

  Map<String, String> getAllUserObjectIds() {
    return Map.unmodifiable(_userObjectIds);
  }

  int get photoCount => _userObjectIds.length;
}

abstract class SignStrategy {
  /// 执行签到流程（UI交互+签到准备）
  Future<void> execute(
      BuildContext context,
      SignInPageState state,
      SignParams params,
  );

  /// 为单个账号执行签到（批量签到使用）
  Future<String?> signForAccount(
      User user,
      SignParams params,
  );

  /// 获取签到类型名称
  String get signTypeName;
}

class SignStrategyFactory {
  static SignStrategy? create(SignType? type) {
    switch (type) {
      case SignType.normal:
        return NormalSign();
      case SignType.pattern:
        return PatternSign();
      case SignType.code:
        return CodeSign();
      case SignType.qrCode:
        return QRCodeSign();
      case SignType.location:
        return LocationSign();
      default:
        return null;
    }
  }
}

class SignInPage extends StatefulWidget {
  final Active active;
  final String courseId;
  final String classId;
  final String cpi;

  const SignInPage({
    super.key,
    required this.active,
    required this.courseId,
    required this.classId,
    required this.cpi,
  });

  @override
  State<SignInPage> createState() => SignInPageState();
}

class SignInPageState extends State<SignInPage> {
  // 签到策略
  SignStrategy? _currentStrategy;
  late SignParams _signParams;

  bool _needCaptcha = false;

  // 签到状态管理
  bool _isLoading = false;
  bool _isMultiSigning = false;

  // 签到数据
  // late bool _needPhoto;
  bool _needPhoto = false;
  String? _locationRange;
  String? _designatedPlace;

  // 签到码相关
  final List<TextEditingController> _codeControllers = [];

  // 账号选择
  List<User> _selectedAccounts = [];
  User? _currentUser;

  // 批量签到进度
  int _signedCount = 0;
  int _totalCount = 0;
  final List<String> _failedAccounts = [];

  // Getter
  bool get needPhoto => _needPhoto;
  String? get designatedPlace => _designatedPlace;
  String? get locationRange => _locationRange;
  List<User> get selectedAccounts => _selectedAccounts;
  User? get currentUser => _currentUser;
  SignStrategy? get currentStrategy => _currentStrategy;
  SignParams get signParams => _signParams;

  @override
  void initState() {
    super.initState();
    _initializeAccounts();
    _signParams = SignParams(
      active: widget.active,
      courseId: widget.courseId,
      classId: widget.classId,
      cpi: widget.cpi,
    );
  }

  @override
  void dispose() {
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeAccounts() async {
    String? currentUserId = AccountManager.currentSessionId;
    _currentUser = AccountManager.getAccountById(currentUserId!);
    setState(() {
      _selectedAccounts = _currentUser != null ? [_currentUser!] : [];
    });

    // 账号初始化完成后初始化签到策略
    _initSignStrategy();
  }

  Future<void> _parseSignInfo() async {
    try {
      final results = await Future.wait([
        SignInApi.getActiveInfoWeb(widget.active.id),
        SignInApi.getAttendInfoWeb(widget.active.id)
      ]);
  
      final activeInfo = results[0];
      final attendInfo = results[1];
  
      if (activeInfo != null && activeInfo['result'] == 1){
        // openPreventCheatFlag 1
        final activeData = activeInfo['data'];
        _needCaptcha = activeData['showVCode'] == 1;
  
        switch (widget.active.signType) {
          case SignType.normal:
            _needPhoto = activeData['ifphoto'] == 1;
            break;
          case SignType.code:
            _signParams.numberCount = activeData['numberCount'];
            break;
          case SignType.qrCode:
          case SignType.location:
            _locationRange = activeData['locationRange'];
            _designatedPlace = activeData['locationText'];
            break;
          case _:
        }
      }
  
      if (attendInfo != null && attendInfo['result'] == 1){
        if (attendInfo['data']['status'] == 1){
          _showSuccessMessage('当前用户已签到');
          if (_currentUser != null) {
            setState(() {
              _selectedAccounts.removeWhere((user) => user.uid == _currentUser!.uid);
            });
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('签到信息解析失败：$e');
    }
  }

  Future<void> _initSignStrategy() async {
    await _parseSignInfo();
    _currentStrategy = SignStrategyFactory.create(widget.active.signType);

    if (_currentStrategy != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentStrategy!.execute(context, this, _signParams);
      });
    } else {
      _showErrorMessage('未知的签到类型');
    }
  }

  void updateMultiSignStatus(bool isMultiSigning, [int? totalCount]) {
    setState(() {
      _isMultiSigning = isMultiSigning;
      if (totalCount != null) {
        _totalCount = totalCount;
        _signedCount = 0;
        _failedAccounts.clear();
      }
    });
  }

  void updatePhotoProgress(int count) {
    setState(() {
      _signedCount = count;
    });
  }

  void addFailedAccount(String account) {
    setState(() {
      _failedAccounts.add(account);
    });
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
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // 批量签到进度显示
                if (_isMultiSigning)
                  _buildProgressCard(),

                const SizedBox(height: 20),

                // 签到操作区域 - 根据策略动态显示
                if (_currentStrategy != null)
                  _buildSignOperationArea(),

                const SizedBox(height: 20),

                // 账号选择
                AccountsSelector(
                  // accounts_selector 现在自己获取数据
                  onSelectionChanged: (selected) {
                    setState(() {
                      _selectedAccounts = selected;
                    });
                  },
                  title: '选择签到账号',
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // 加载指示器
          if (_isLoading)
            _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: _totalCount > 0 ? _signedCount / _totalCount : 0,
              backgroundColor: Theme.of(context).dividerColor,
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 10),
            Text(
              '签到进度: $_signedCount/$_totalCount',
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

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('批量签到中...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  /// 根据签到策略构建对应的签到操作UI
  Widget _buildSignOperationArea() {
    switch (widget.active.signType) {
      case SignType.normal:
        return NormalSign.buildSignArea(this);
      case SignType.pattern:
        return PatternSign.buildSignArea(this);
      case SignType.code:
        return CodeSign.buildSignArea(this);
      case SignType.qrCode:
        return QRCodeSign.buildSignArea(this);
      case SignType.location:
        return LocationSign.buildSignArea(this);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _performMultiSign() async {
    if (_selectedAccounts.isEmpty || _currentStrategy == null) return;

    setState(() {
      _isLoading = true;
      _isMultiSigning = true;
      _signedCount = 0;
      _totalCount = _selectedAccounts.length;
      _failedAccounts.clear();
    });

    for (var user in _selectedAccounts) {
      AccountManager.setCurrentSessionTemp(user.uid);
      SignInApi.updateUser();
    
      try {
        final result = await _currentStrategy!.signForAccount(user, _signParams);
        await _handleSignResult(result, user);
      } catch (e) {
        _addFailedAccount(user, '异常：$e');
      } finally {
        if (mounted) {
          setState(() => _signedCount++);
        }
      }
    }

    if (_currentUser != null) {
      AccountManager.setCurrentSessionTemp(_currentUser!.uid);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isMultiSigning = false;
      });
    }

    _showMultiSignResult();
  }

  Future<void> _handleSignResult(String? result, User user) async {
    if (result == null) {
      _addFailedAccount(user, '无响应');
      return;
    }

    if (result.startsWith('validate')) {
      if (result.contains('_')) {
        _signParams.enc2 = result.split('_')[1];
      }

      if (_signParams.validate == null) {
        bool captchaSuccess = await _handleCaptcha();
        if (!captchaSuccess) {
          // 用户取消验证码或验证码失败，标记为失败
          _addFailedAccount(user, '验证码取消或失败');
          return; // 直接返回，不再继续签到
        }
      }

      // 验证码成功，继续签到
      try {
        await _currentStrategy!.signForAccount(user, _signParams);
      } catch (e) {
        _addFailedAccount(user, '验证码重试失败: $e');
      }
    } else if (result == 'success') {
      // 签到成功
      debugPrint('账号 ${user.name} 签到成功');
    } else if (result == 'success2') {
      _addFailedAccount(user, '已过截止时间');
    } else if (result.contains('不在可签到范围内')){
      // 距教师指定签到地点150582.0米，不在可签到范围内。
      _addFailedAccount(user, result);
    } else {
      _addFailedAccount(user, result);
    }
  }

  void _addFailedAccount(User user, String reason) {
    setState(() {
      _failedAccounts.add('${user.name} ($reason)');
    });
  }

  Future<bool> _handleCaptcha() async {
    try {
      final validate = await CaptchaPage.showSlideCaptchaDialog(
        context,
        referer: widget.active.url,
      );

      if (validate != null) {
        setState(() {
          _signParams.validate = validate;
        });
        return true; // 验证码成功
      } else {
        return false; // 用户取消或验证码失败
      }
    } catch (e) {
      _showErrorMessage('验证码处理失败: $e');
      return false; // 处理异常
    }
  }

  void showPhotoResult(int successCount, int totalCount) {
    if (!mounted) return;

    String message = '拍照完成: $successCount/$totalCount 成功';
    if (_failedAccounts.isNotEmpty) {
      message += '\n\n失败:\n${_failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拍照完成'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showMultiSignResult() {
    if (!mounted) return;

    final successCount = _totalCount - _failedAccounts.length;
    String message = '签到完成！\n成功: $successCount/$_totalCount';
    if (_failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${_failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == _totalCount ? '全部签到成功' : '部分失败',
          style: TextStyle(
            color: successCount == _totalCount ? Colors.green : Colors.orange,
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

  void showProgressSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void performMultiSign() => _performMultiSign();
  void showErrorMessage(String message) => _showErrorMessage(message);
  String getCodeInput() => _codeControllers.map((c) => c.text).join('');
  void checkCodeCompletion() {
    final code = getCodeInput();
    if (code.length == _signParams.numberCount) {
      _signParams.code = code;
    }
  }
}