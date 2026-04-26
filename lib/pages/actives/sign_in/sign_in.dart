import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import '../../../../api/active.dart';
import '../../../../api/api_service.dart';
import '../../../../api/sign_in.dart';
import '../../../../setting/course_setting.dart';
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

  // 普通签到（拍照）
  final Map<String, String> _userObjectIds = {}; // userId -> objectId

  // 手势签到
  String pattern = '';

  // 签到码签到
  String code = '';
  int numberCount = 0;

  // 二维码签到
  String? enc;
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
      SignInPageState state,
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
  final String? enc;

  const SignInPage({
    super.key,
    required this.active,
    required this.courseId,
    required this.classId,
    required this.cpi,
    this.enc,
  });

  @override
  State<SignInPage> createState() => SignInPageState();
}

class SignInPageState extends State<SignInPage> {
  // 签到策略
  SignStrategy? _currentStrategy;
  late SignParams _signParams;

  int _signTypeId = 0;

  int? _attendNum;

  int _status = 0;
  /*
  status:
    0: unsign // 未签
    1: signed // 已签
    1: SignSuccessfully // 签到成功
    2: signedbyteacher // 教师代签
    4: PersonalLeave2 // 请假
    5: Absence // 缺勤
    7: SickLeave // 病假
    8: PersonalLeave // 事假
    9: Late // 迟到
    10: LeaveEarly // 早退
    11: SignExpiredy // 签到已过期
    12: PublicLeave // 公假
  */

  // 签到状态管理
  bool _isLoading = false;
  bool _isMultiSigning = false;

  // 签到数据
  // late bool _needPhoto;
  bool _needCaptcha = false;
  bool _needFace = false;
  bool _needPhoto = false;
  String? _locationRange;
  String? _designatedPlace;

  // 签到码相关
  final List<TextEditingController> _codeControllers = [];

  // 账号选择
  List<User> _selectedAccounts = [];
  User? _currentUser;
  final GlobalKey<AccountsSelectorState> _accountsSelectorKey = GlobalKey<AccountsSelectorState>();



  // UserId -> {Validate, enc2}
  final Map<String, Map<String, String>> _userCaptchaValidate = {};

  // Getter
  bool get needPhoto => _needPhoto;
  bool get needFace => _needFace;
  String? get designatedPlace => _designatedPlace;
  String? get locationRange => _locationRange;
  List<User> get selectedAccounts => _selectedAccounts;
  User? get currentUser => _currentUser;
  SignStrategy? get currentStrategy => _currentStrategy;
  SignParams get signParams => _signParams;
  
  Map<String, String>? getUserCaptchaValidate(String userId) {
    return _userCaptchaValidate[userId];
  }

  void setUserImage(String uid, File imageFile) {
    _accountsSelectorKey.currentState?.setImageForUser(uid, imageFile);
  }

  void setUserUploadingStatus(String uid, bool isUploading) {
    _accountsSelectorKey.currentState?.setUploadingStatus(uid, isUploading);
  }

  void setUserUploadFailed(String uid) {
    _accountsSelectorKey.currentState?.setUploadFailed(uid);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final currentSessionId = AccountManager.currentSessionId!;
    _currentUser = AccountManager.getAccountById(currentSessionId);
    _initSignStrategy();
    
    _signParams = SignParams(
      active: widget.active,
      courseId: widget.courseId,
      classId: widget.classId,
      cpi: widget.cpi,
    );

    // 扫码签到
    if (widget.enc != null) {
      _signParams.enc = widget.enc;
    }
  }

  @override
  void dispose() {
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _parseSignInfo() async {
    try {
      final results = await Future.wait([
        ActiveApi.getActiveInfoWeb(widget.active.id),
        SignInApi.getAttendInfoWeb(widget.active.id)
      ]);
  
      final activeInfo = results[0];
      final attendInfo = results[1];
  
      if (activeInfo != null){
        _signTypeId = activeInfo['otherId'];
        _attendNum = activeInfo['attendNum'];
        // openPreventCheatFlag 1
        _needCaptcha = activeInfo['showVCode'] == 1;
  
        switch (widget.active.signType) {
          case SignType.normal:
            _needPhoto = activeInfo['ifphoto'] == 1;
            break;
          case SignType.code:
            _signParams.numberCount = activeInfo['numberCount'];
            break;
          case SignType.qrCode:
          case SignType.location:
            _locationRange = activeInfo['locationRange'];
            _designatedPlace = activeInfo['locationText'];
            _needFace = activeInfo['openCheckFaceFlag'] == 1;
            break;
          case _:
        }
      }
      if (attendInfo != null){
        _status = attendInfo['status'];
        // TODO 支持其他状态
        if (_status == 1){
          _showSuccessMessage('当前用户已签到');
          if (_currentUser != null) {
            setState(() {
              _selectedAccounts.removeWhere((user) => user.uid == _currentUser!.uid);
            });
          }
        }
      }
      if (mounted) setState(() {});

      // 为已选中的账号分配图片
      if (widget.active.signType == SignType.normal && _needPhoto && _selectedAccounts.isNotEmpty) {
        _assignImages();
      }
    } catch (e, stackTrace) {
      debugPrint('签到信息解析失败：$e \n$stackTrace');
    }
  }

  Future<void> _initSignStrategy() async {
    await _parseSignInfo();
    if (widget.active.signType == null) {
      widget.active.signType = getSignTypeFromIndex(_signTypeId);
    }
    _currentStrategy = SignStrategyFactory.create(widget.active.signType);
    if (_currentStrategy != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentStrategy!.execute(context, this, _signParams);
      });
    } else {
      _showErrorMessage('未知的签到类型');
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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),



                // 签到操作区域 - 根据策略动态显示
                if (_currentStrategy != null)
                  _buildSignOperationArea(),

                const SizedBox(height: 20),

                // 账号选择
                AccountsSelector(
                  key: _accountsSelectorKey,
                  onSelectionChanged: (selected) {
                    setState(() {
                      _selectedAccounts = selected;
                    });
                    // 普通签到需要照片时，自动分配课程配置的图片
                    if (widget.active.signType == SignType.normal && _needPhoto) {
                      _assignImages();
                    }
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
    if (_isMultiSigning) return;
  
    setState(() {
      _isLoading = true;
      _isMultiSigning = true;
    });

    final failedAccounts = <String>[];
    final totalCount = _selectedAccounts.length;

    final isQrCodeSign = widget.active.signType == SignType.qrCode;

    // 除二维码签到以外 其他签到预先处理验证码
    if (_needCaptcha && !isQrCodeSign) {
      for (var user in _selectedAccounts) {
        AccountManager.setCurrentSessionTemp(user.uid);

        if (!await _handleCaptcha(user.uid)) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isMultiSigning = false;
            });
          }
          _showErrorMessage('验证码取消或失败');
          return;
        }
      }
      AccountManager.setCurrentSessionTemp(_currentUser!.uid);
    }

    final results = await ApiService.sendForEachUser(
      _selectedAccounts,
      (user) async {
        return await _currentStrategy!.signForAccount(user, _signParams, this);
      }
    );
    
    // 统一处理所有签到结果
    for (int i = 0; i < _selectedAccounts.length; i++) {
      final user = _selectedAccounts[i];
      final result = results[i];
      await _handleSignResult(result, user, failedAccounts);
    }
  
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isMultiSigning = false;
      });
    }
  
    _showMultiSignResult(totalCount, failedAccounts);
  }

  Future<void> _handleSignResult(String? result, User user, List<String> failedAccounts) async {
    if (result == null) {
      failedAccounts.add('${user.name} (无响应)');
      return;
    }

    if (result.startsWith('validate')) {
      if (result.contains('_')) {
        final enc2 = result.split('_')[1];
        (_userCaptchaValidate[user.uid] ??= {})['enc2'] = enc2;
        if (!await _handleCaptcha(user.uid)) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isMultiSigning = false;
            });
          }
          _showErrorMessage('验证码取消或失败');
          return;
        }
        final resignResult = await _currentStrategy!.signForAccount(user, _signParams, this);
        await _handleSignResult(resignResult, user, failedAccounts);
      }
    } else if (result == 'success') {
      // 签到成功
      debugPrint('${user.name} 签到成功');
    } else if (result == 'success2') {
      failedAccounts.add('${user.name} (已过截止时间)');
    } else {
      // 签到失败，请重新签到 -> 二维码过期
      failedAccounts.add('${user.name} ($result)');
    }
  }

  Future<bool> _handleCaptcha(String userId) async {
    try {
      final validate = await CaptchaPage.showSlideCaptchaDialog(
        context,
        referer: widget.active.url
      );

      if (validate != null) {
        (_userCaptchaValidate[userId] ??= {})['validate'] = validate;
        return true; // 验证码成功
      } else {
        return false; // 用户取消或验证码失败
      }
    } catch (e) {
      _showErrorMessage('验证码处理失败: $e');
      return false; // 处理异常
    }
  }

  void _showMultiSignResult(int totalCount, List<String> failedAccounts) {
    if (!mounted) return;

    final successCount = totalCount - failedAccounts.length;
    String message = '签到完成！\n成功: $successCount/$totalCount';
    if (failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == totalCount ? '全部签到成功' : '部分失败',
          style: TextStyle(
            color: successCount == totalCount ? Colors.green : Colors.orange,
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

  /// 为选中的账号分配课程配置的图片objectId
  Future<void> _assignImages() async {
    if (_selectedAccounts.isEmpty) return;
    
    final settings = await CourseSetting.getSettings(_signParams.courseId);
    if (settings?.imageObjectIds == null || settings!.imageObjectIds!.isEmpty) return;
    
    final imageObjectIds = settings.imageObjectIds!;
    
    // 为每个选中的账号分配图片objectId
    for (int i = 0; i < _selectedAccounts.length && i < imageObjectIds.length; i++) {
      final user = _selectedAccounts[i];
      final existingObjectId = _signParams.getUserObjectId(user.uid);
      
      // 只在没有objectId时才分配
      if (existingObjectId == null || existingObjectId.isEmpty) {
        _signParams.setUserObjectId(user.uid, imageObjectIds[i]);
        // 通知账号选择器显示网络图片
        _accountsSelectorKey.currentState?.setObjectIdForUser(user.uid, imageObjectIds[i]);
      }
    }
    
    if (mounted) setState(() {});
  }
}