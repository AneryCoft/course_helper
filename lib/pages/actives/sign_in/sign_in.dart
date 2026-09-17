import 'package:flutter/material.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'dart:async';
import 'dart:io';

import '../../../../api/active.dart';
import '../../../../api/api_service.dart';
import '../../../../api/sign_in.dart';
import '../../../../setting/course_setting.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../models/course.dart';
import '../../../session/account.dart';
import '../../widget/accounts_selector.dart';
import '../../widget/baidu_map.dart';
import '../../widget/captcha.dart';
import 'normal.dart';
import 'pattern.dart';
import 'code.dart';
import 'qrcode.dart';
import 'location.dart';
import 'attend_list.dart';


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

  // 群聊签到列表数据
  List<Map<String, dynamic>>? groupSignedList;

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
  bool _isDataLoaded = false;

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

  // 账号状态（uid -> 状态信息），用于初始化选择器并同步更新
  final Map<String, AccountStatusInfo> _accountStatuses = {};

  // 签到状态文字描述
  static const Map<int, String> _statusTexts = {
    1: '签到成功',
    2: '教师代签',
    4: '请假',
    5: '缺勤',
    7: '病假',
    8: '事假',
    9: '迟到',
    10: '早退',
    11: '签到已过期',
    12: '公假'
  };

  // UserId -> {Validate, enc2}
  final Map<String, Map<String, String>> _userCaptchaValidate = {};

  // Getter
  bool get isGroupSign => widget.classId.isEmpty;
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

  void setObjectIdForUser(String uid, String objectId) {
    _accountsSelectorKey.currentState?.setObjectIdForUser(uid, objectId);
  }

  void setUserUploadingStatus(String uid, bool isUploading) {
    _accountsSelectorKey.currentState?.setUploadingStatus(uid, isUploading);
  }

  void setUserUploadFailed(String uid) {
    _accountsSelectorKey.currentState?.setUploadFailed(uid);
  }

  /// 设置账号状态图标（同时写入本地状态与选择器）
  void setUserStatus(String uid, AccountStatus status, {String? message}) {
    _accountStatuses[uid] = AccountStatusInfo(status, message: message);
    _accountsSelectorKey.currentState?.setUserStatus(uid, status, message: message);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  /// 清除已选择的签到位置
  void clearSignLocation() {
    _signParams.address = null;
    _signParams.latitude = null;
    _signParams.longitude = null;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final currentSessionId = AccountManager.currentSessionId!;
    _currentUser = AccountManager.getAccountById(currentSessionId);
    
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

    _loadActivityData();
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
      if (isGroupSign) { // 群聊签到
        final groupSignDetail = await SignInApi.getGroupSignDetail(widget.active.id);
        if (groupSignDetail != null) {
          _signTypeId = groupSignDetail['otherId'];
          _needPhoto = groupSignDetail['ifPhoto'] == 1;
          widget.active.signType = _signTypeId == 4 ?
          SignType.location : SignType.normal; // 只有位置签到和拍照签到需要输入
        }
        return;
      }

      final results = await Future.wait([
        ActiveApi.getActiveInfoWeb(widget.active.id),
        SignInApi.getAttendInfoWeb(widget.active.id)
      ]);
  
      final activeInfo = results[0];
      final attendInfo = results[1];
  
      if (activeInfo != null){
        _signTypeId = activeInfo['otherId'];
        // openPreventCheatFlag 1
        _needCaptcha = activeInfo['showVCode'] == 1;
        
        // 根据 otherId 确定签到类型
        if (widget.active.signType == null) {
          widget.active.signType = getSignTypeFromIndex(_signTypeId);
        } else if (widget.active.signType != SignType.normal) {
          _locationRange = activeInfo['locationRange'];
          _designatedPlace = activeInfo['locationText'];
        }

        switch (widget.active.signType) {
          case SignType.normal:
            _needPhoto = activeInfo['ifphoto'] == 1;
            break;
          case SignType.code:
            _signParams.numberCount = activeInfo['numberCount'];
            break;
          case SignType.qrCode:
          case SignType.location:
            _needFace = activeInfo['openCheckFaceFlag'] == 1;
            break;
          case _:
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取活动信息失败')),
          );
        }
      }
      if (attendInfo != null){
        _status = attendInfo['status'];
        if (_status == 1){
          setUserStatus(_currentUser!.uid, AccountStatus.completed);
          _showSuccessMessage('当前用户已签到');
          if (_currentUser != null) {
            setState(() {
              _selectedAccounts.removeWhere((user) => user.uid == _currentUser!.uid);
            });
          }
        } else if (_status == 0) {
          setUserStatus(_currentUser!.uid, AccountStatus.incomplete);
        } else {
          // 请假、缺勤等其他状态均视为已处理
          setUserStatus(_currentUser!.uid, AccountStatus.completed,
              message: _statusTexts[_status] ?? '已完成');
        }
      } else {
        setUserStatus(_currentUser!.uid, AccountStatus.error, message: '获取签到状态失败');
      }

      // 为已选中的账号分配图片
      if (widget.active.signType == SignType.normal && _needPhoto && _selectedAccounts.isNotEmpty) {
        _assignImages();
      }
    } catch (e, stackTrace) {
      debugPrint('签到信息解析失败：$e \n$stackTrace');
    }
  }

  Future<void> _loadActivityData() async {
    setState(() {
      _isLoading = true;
    });

    await _parseSignInfo();
    
    _currentStrategy = SignStrategyFactory.create(widget.active.signType);
    
    setState(() {
      _isLoading = false;
      _isDataLoaded = true;
    });

    // 查询其他账号的签到状态（选择器挂载后执行）
    if (!isGroupSign) {
      _checkOtherAccountsStatus();
    }

    if (_currentStrategy != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentStrategy!.execute(context, this, _signParams);
      });
    } else if (mounted) {
      _showErrorMessage('未知的签到类型');
    }
  }



  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.active.name),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator()
        )
      );
    }

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

                // 群聊签到列表
                if (isGroupSign)
                  AttendListWidget(state: this),

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
                  initialStatuses: _accountStatuses,
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
          setUserStatus(user.uid, AccountStatus.error, message: '验证码取消或失败');
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
      await _handleSignResult(result, user);
    }
  
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isMultiSigning = false;
      });
    }
  }

  /// 其他所有账号的签到状态
  Future<void> _checkOtherAccountsStatus() async {
    final otherAccounts = AccountManager.allAccounts
        .where((user) => user != _currentUser)
        .toList();
    if (otherAccounts.isEmpty) return;

    // 查询完成前状态未知
    for (var user in otherAccounts) {
      setUserStatus(user.uid, AccountStatus.unknown, message: '查询中...');
    }

    final results = await ApiService.sendForEachUser<Map<String, dynamic>>(
      otherAccounts,
      (user) => SignInApi.getAttendInfoWeb(widget.active.id, userId: user.uid),
    );

    for (int i = 0; i < otherAccounts.length; i++) {
      final user = otherAccounts[i];
      final result = results[i];
      if (result == null) {
        setUserStatus(user.uid, AccountStatus.error, message: '请求失败，请检查账号登录状态');
        continue;
      }

      final status = result['status'];
      if (status == 0) {
        setUserStatus(user.uid, AccountStatus.incomplete);
      } else if (status == 1) {
        setUserStatus(user.uid, AccountStatus.completed);
      } else if (status is int) {
        setUserStatus(user.uid, AccountStatus.completed,
            message: _statusTexts[status] ?? '已完成');
      } else {
        setUserStatus(user.uid, AccountStatus.unknown, message: '无法解析签到状态');
      }
    }
  }

  Future<void> _handleSignResult(String? result, User user) async {
    if (result == null) {
      setUserStatus(user.uid, AccountStatus.error, message: '签到请求无响应');
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
          setUserStatus(user.uid, AccountStatus.error, message: '验证码取消或失败');
          return;
        }
        final resignResult = await _currentStrategy!.signForAccount(user, _signParams, this);
        await _handleSignResult(resignResult, user);
      }
    } else if (result == 'success') {
      // 签到成功
      setUserStatus(user.uid, AccountStatus.completed);
    } else if (result == 'success2') {
      setUserStatus(user.uid, AccountStatus.error, message: '已过截止时间');
    } else if (result == '签到失败，请重新扫描。') {
      setUserStatus(user.uid, AccountStatus.error, message: '二维码过期');
    } else {
      setUserStatus(user.uid, AccountStatus.error, message: result);
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

/// 签到定位共用UI
class SignLocationUi {
  static Widget wrapWithAutoFill(
      SignInPageState state, {
        required List<Widget> Function(BuildContext context) buildChildren,
      }) {
    final hasLocation = state.signParams.address != null;

    return FutureBuilder<CourseSettings?>(
      future: loadCourseLocation(state),
      builder: (context, snapshot) {
        // 课程配置选择位置（仅在未选择位置且有配置时自动填充）
        if (!hasLocation && snapshot.hasData && snapshot.data?.location != null) {
          final location = snapshot.data!.location!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (state.mounted && state.signParams.address == null) {
              state.signParams.latitude = double.tryParse(location.latitude);
              state.signParams.longitude = double.tryParse(location.longitude);
              state.signParams.address = location.address.isEmpty ? '未知位置' : location.address;
              (state.context as Element).markNeedsBuild();
            }
          });
        }

        return Builder(
          builder: (context) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: buildChildren(context),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 定位相关UI
  static List<Widget> buildSection(
      BuildContext context,
      SignInPageState state, {
        bool alwaysShow = false,
        bool showSignButton = false,
        VoidCallback? onReselect,
      }) {
    final hasLocation = state.signParams.address != null;
    final showLocationUi = alwaysShow || state.designatedPlace != null;

    return [
      // 指定签到地点显示
      if (state.designatedPlace != null && state.designatedPlace!.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.info, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '指定签到地点：${state.designatedPlace!}\n范围：${state.locationRange!}米',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],

      // 位置选择按钮（未选位置时显示）
      if (showLocationUi && !hasLocation) ...[
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => showPicker(state, autoSign: showSignButton),
            icon: const Icon(Icons.location_on),
            label: const Text('选择签到位置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],

      // 已选择位置信息区域
      if (showLocationUi && hasLocation) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 18, color: Theme.of(context).colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.signParams.address!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (showSignButton) ...[
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => state.performMultiSign(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('签到'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReselect ?? state.clearSignLocation,
                      child: const Text('重新选择'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// 位置选择页面
  static Future<void> showPicker(SignInPageState state, {bool autoSign = false}) async {
    final BuildContext context = state.context;
    BMFCoordinate? selectedCoordinate;
    String? selectedAddress;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('选择签到位置')),
          body: Column(
            children: [
              Expanded(
                child: BaiduMapWidget(
                  onLocationSelectedWithAddress: (coordinate, address) {
                    selectedCoordinate = coordinate;
                    selectedAddress = address;
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (selectedCoordinate != null) {
                          // 保存位置到签到参数
                          state.signParams.latitude = selectedCoordinate!.latitude;
                          state.signParams.longitude = selectedCoordinate!.longitude;
                          state.signParams.address = selectedAddress?.isEmpty ?? true
                              ? '未知位置'
                              : selectedAddress!;
                          Navigator.pop(context);

                          // 异步保存位置到课程配置
                          saveLocationToCourse(state);

                          // 返回后刷新UI，显示已选择位置
                          if (state.mounted) {
                            (state.context as Element).markNeedsBuild();
                          }

                          if (autoSign) {
                            state.performMultiSign();
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请先点击地图选择位置')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(autoSign ? '确认选择并签到' : '确认选择'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 加载课程位置配置
  static Future<CourseSettings?> loadCourseLocation(SignInPageState state) async {
    final courseId = state.signParams.courseId;
    if (courseId.isEmpty) return null;
    return await CourseSetting.getSettings(courseId);
  }

  /// 保存位置到课程配置
  static Future<void> saveLocationToCourse(SignInPageState state) async {
    final courseId = state.signParams.courseId;
    if (courseId.isEmpty) return;

    final location = CourseLocation(
        address: state.signParams.address ?? '',
        latitude: state.signParams.latitude?.toString() ?? '',
        longitude: state.signParams.longitude?.toString() ?? ''
    );

    await CourseSetting.updateLocation(courseId, location);
  }
}