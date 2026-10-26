import 'package:flutter/material.dart';
import 'package:flutter_tencent_captcha/flutter_tencent_captcha.dart';
import 'dart:async';

import '../api/login.dart';
import '../models/user.dart';
import '../session/account.dart';
import '../ui/design_tokens.dart';
import '../utils/encrypt.dart';
import '../platform.dart';
import '../utils/logger.dart';

/// 登录成功处理
Future<bool> handleLoginSuccess(BuildContext context) async {
  try {
    late User? user;
    if (PlatformManager().isChaoxing) {
      user = await CXLoginApi(User.empty).getUserInfo();
    } else {
      user = await RCLoginApi(User.empty).getUserInfo();
    }
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取用户信息失败')),
        );
      }
      return false;
    }

    await AccountManager.addAccount(user);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} 登录成功')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录处理失败')),
      );
    }
    return false;
  }
}

class LoginPage extends StatefulWidget {
  final String initialLoginType;

  const LoginPage({super.key, this.initialLoginType = 'password'});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// 二维码登录状态管理类
class QRCodeLoginState {
  String? qrUuid;
  String? qrEnc; // 学习通
  String? qrToken; // 雨课堂
  String? qrImageUrl;
  bool isLoading = true;
  bool isRefreshing = false;
  bool isLoginActive = true;

  Timer? _pollingTimer;
  final _isChaoxing = PlatformManager().isChaoxing;
  VoidCallback? onRefresh;

  /// 获取二维码数据
  Future<Map<String, dynamic>?> _getQRCodeData() async {
    if (_isChaoxing) {
      return await CXLoginApi.getQRCodeData();
    } else {
      return await RCLoginApi.getQRCodeData();
    }
  }

  /// 更新二维码信息
  void _updateQRInfo(Map<String, dynamic> qrData) {
    if (_isChaoxing) {
      qrUuid = qrData['uuid'];
      qrEnc = qrData['enc'];
      qrImageUrl = 'https://passport2.chaoxing.com/createqr?uuid=$qrUuid&fid=-1';
    } else {
      qrToken = qrData['token'];
      qrImageUrl = qrData['qrImage'];
    }
  }

  /// 初始化二维码数据
  Future<bool> initialize() async {
    try {
      final qrData = await _getQRCodeData();
      if (qrData != null) {
        _updateQRInfo(qrData);
        isLoading = false;
        return true;
      }
      return false;
    } catch (e) {
      logger.e('初始化二维码失败: $e');
      return false;
    }
  }

  /// 开始轮询登录状态
  void startPolling(Function(bool success) onLoginComplete, {VoidCallback? onRefresh}) {
    _pollingTimer?.cancel();
    this.onRefresh = onRefresh;

    if (_isChaoxing) {
      // 每3秒检查一次
      _startChaoxingPolling(onLoginComplete);
    } else {
      _startRainClassroomNewPolling(onLoginComplete);
    }
  }

  /// 雨课堂新API轮询逻辑（使用token）
  void _startRainClassroomNewPolling(Function(bool success) onLoginComplete) async {
    while (isLoginActive && qrToken != null) {
      try {
        final result = await RCLoginApi.loginQRCode(qrToken!);
        if (result != null) {
          // 登录成功
          onLoginComplete(true);
          return;
        } else {
          // 超时或失败，刷新二维码
          await refreshQRCode();
          onRefresh?.call();
          if (!isLoginActive || qrToken == null) return;
        }
      } catch (e) {
        logger.e('轮询失败: $e');
      }
      
      // 如果不是活跃状态则退出
      if (!isLoginActive) return;
    }
  }

  /// 学习通轮询逻辑
  void _startChaoxingPolling(Function(bool success) onLoginComplete) {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!isLoginActive || qrUuid == null || qrEnc == null) {
        timer.cancel();
        return;
      }

      try {
        final result = await CXLoginApi.checkQRAuthStatus(qrUuid!, qrEnc!);
        if (result != null) {
          if (result['status'] == true) {
            timer.cancel();
            onLoginComplete(true);
          } else if (result['type']?.toString() == '2') {
            timer.cancel();
            await refreshQRCode();
            onRefresh?.call();
          }
        }
      } catch (e) {
        logger.e('轮询失败: $e');
      }
    });
  }

  /// 刷新二维码
  Future<void> refreshQRCode() async {
    if (isRefreshing) return;

    isRefreshing = true;
    isLoading = true;
    qrImageUrl = null;
    onRefresh?.call();
    
    try {
      final qrData = await _getQRCodeData();
      if (qrData != null) {
        _updateQRInfo(qrData);
      }
    } catch (e) {
      logger.e('刷新二维码失败: $e');
    } finally {
      isRefreshing = false;
      isLoading = false;
    }
  }

  void dispose() {
    isLoginActive = false;
    _pollingTimer?.cancel();
  }
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  final _captchaFocusNode = FocusNode();
  bool _isLoading = false;
  bool _showPassword = false;
  String _currentLoginType = '1'; // '1'密码登录，'2'验证码登录，'3'二维码登录
  Timer? _countdownTimer;
  int _countdownSeconds = 0;
  
  // 腾讯验证码参数
  String? _ticket;
  String? _randstr;
  bool _hasShownCaptchaHint = false;

  @override
  void initState() {
    super.initState();
    if (PlatformManager().isRainClassroom) {
      TencentCaptcha.init(Constant.tCaptchaAppId);
    }
    if (widget.initialLoginType == 'captcha') {
      _currentLoginType = '2';
    } else if (widget.initialLoginType == 'qrcode') {
      _currentLoginType = '3';
      _showQRCodeLogin();
    } else {
      _currentLoginType = '1';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    _countdownTimer?.cancel();
    _captchaFocusNode.dispose();
    super.dispose();
  }

  /// 显示二维码登录对话框
  Future<void> _showQRCodeLogin() async {
    final qrState = QRCodeLoginState();

    final initialized = await qrState.initialize();
    if (!initialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取二维码失败')),
        );
      }
      qrState.dispose();
      return;
    }

    qrState.startPolling((bool success) async {
      if (success && mounted) {
        final loginSuccess = await handleLoginSuccess(context);
        if (loginSuccess && mounted) {
          Navigator.pop(context, true);
        }
      }
      qrState.dispose();
    });

    if (!mounted) {
      qrState.dispose();
      return;
    }
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            qrState.onRefresh = () {
              setState(() {});
            };
            
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (didPop) {
                  qrState.isLoginActive = false;
                  qrState.dispose();
                }
              },
              child: AlertDialog(
                title: const Text('二维码登录'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: qrState.qrImageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                qrState.qrImageUrl!,
                                fit: BoxFit.contain,
                              ),
                            )
                          : qrState.isLoading
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 8),
                                  Text(
                                    '生成中...',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '二维码加载失败',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '请使用学习通APP扫描上方二维码进行登录',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '二维码失效时会自动刷新',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      qrState.isLoginActive = false;
                      qrState.dispose();
                      Navigator.pop(context);
                    },
                    child: const Text('取消'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    qrState.dispose();
  }

  /// 显示腾讯验证码并进行验证
  ///
  /// 说明：人机验证是平台的安全机制，本应用只负责调起官方验证组件，
  /// 不做任何绕过处理。这里主要优化等待与失败时的反馈体验。
  Future<bool?> _showTencentCaptcha() async {
    final config = TencentCaptchaConfig(
      bizState: 'tencent-captcha',
      enableDarkMode: Theme.of(context).brightness == Brightness.dark
    );

    // 首次触发时提示用户为什么会出现验证
    if (!_hasShownCaptchaHint) {
      _hasShownCaptchaHint = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('平台要求人机验证，请按提示完成操作'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    try {
      final Completer<bool?> completer = Completer<bool?>();

      await TencentCaptcha.verify(
        config: config,
        onSuccess: (data) {
          final ticket = data?['ticket'];
          final randstr = data?['randstr'];
          if (ticket != null && randstr != null) {
            _ticket = ticket;
            _randstr = randstr;
            completer.complete(true);
          } else {
            completer.complete(false);
          }
        },
        onFail: (data) {
          if (mounted) {
            final message = data['errorMessage']?.toString() ?? '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  message.isEmpty
                      ? '验证未通过，请重试'
                      : '验证未通过：$message',
                ),
              ),
            );
          }
          completer.complete(false);
        },
      );

      // await 让 verify 抛出的异常能被下方 catch 捕获
      return await completer.future;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('验证组件加载失败，请检查网络后重试：$e')),
        );
      }
      return false;
    }
  }

  /// 密码/验证码登录
  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
  
      try {
        Map<String, dynamic>? result;
          
        if (PlatformManager().isChaoxing) {
          result = await CXLoginApi.loginAPP(
            _currentLoginType,
            _usernameController.text,
            _currentLoginType == '2' ? _captchaController.text : _passwordController.text,
          );
  
          if (result != null && result['status']) {
            if (!result.containsKey('url')) {
              await _showSecurityVerificationDialog();
            }
  
            if (!mounted) return;
            final success = await handleLoginSuccess(context);
            if (success && mounted) {
              Navigator.pop(context, true);
            }
          } else {
            String errorMessage = result?['mes'] ?? '登录失败，请检查账号密码';
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errorMessage)),
              );
            }
          }
        } else {
          // 雨课堂验证码前置校验
          if (_currentLoginType == '2') {
            final verifyResult = await RCLoginApi.verifyCaptcha(
                _usernameController.text,
                _captchaController.text
            );
        
            if (verifyResult == null || verifyResult['code'] != 0) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(verifyResult?['msg'] ?? '验证码验证失败')),
                );
              }
              return;
            }
          } else {
            // 非验证码模式需要腾讯验证码
            if (_ticket == null || _randstr == null){
              final captchaResult = await _showTencentCaptcha();
              if (captchaResult != true) {
                return;
              }
            }
          }

          result = await RCLoginApi.login(
            _currentLoginType == '2' ? 3 : 2, // 1: 密码登录 2: 邮箱登录 3: 验证码登录
            _usernameController.text,
            _currentLoginType == '2' ? _captchaController.text : _passwordController.text,
            _ticket!,
            _randstr!,
          );

          // 非验证码模式清空验证码凭证
          if (_currentLoginType != '2') {
            _ticket = null;
            _randstr = null;
          }

          late String errorMessage;
          if (result != null) {
            if (result['code'] == 0) {
              if (!mounted) return;
              final success = await handleLoginSuccess(context);
              if (success && mounted) {
                Navigator.pop(context, true);
              }
              return;
            } else {
              errorMessage = result['msg'];
            }
          } else {
            errorMessage = '登录失败，请检查账号密码';
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage)),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('登录时发生错误：$e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _sendCaptcha() async {
    String phone = _usernameController.text.trim();
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入手机号')),
        );
      }
      return;
    }
  
    // 仅雨课堂需要腾讯验证码验证
    if (PlatformManager().isRainClassroom) {
      final captchaResult = await _showTencentCaptcha();
      if (captchaResult != true) {
        return;
      }
  
      if (_ticket == null || _randstr == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('验证码验证失败，请重试')),
          );
        }
        return;
      }
    }
  
    try {
      setState(() {
        _isLoading = true;
      });
  
      Map<String, dynamic>? result;
        
      if (PlatformManager().isChaoxing) {
        result = await CXLoginApi.sendCaptcha(phone);
          
        if (result == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('发送验证码失败，请重试')),
            );
          }
          return;
        }
  
        if (result['status'] == true) {
          _startCountdown();
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('验证码已发送')),
                );
              }
            });
          }
        } else {
          final message = result['mes'] ?? '发送验证码失败';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        }
      } else {
        result = await RCLoginApi.sendCaptcha(phone, _ticket!, _randstr!);
          
        if (result == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('发送验证码失败，请重试')),
            );
          }
          return;
        }
  
        if (result['code'] == 0) {
          _startCountdown();
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('验证码已发送')),
                );
              }
            });
          }
        } else {
          final message = result['msg'] ?? '发送验证码失败';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送验证码时发生错误：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startCountdown() {
    _countdownSeconds = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 0) {
        setState(() {
          _countdownSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _showSecurityVerificationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('安全验证'),
          content: const Text('新设备登录需要安全验证，请使用验证码登录'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _currentLoginType = '2';
                });
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPassword = _currentLoginType == '1';
    final isCaptcha = _currentLoginType == '2';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          isPassword ? '密码登录' : isCaptcha ? '验证码登录' : '二维码登录',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------- 头部标识 ----------
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary(cs),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      PlatformManager().isChaoxing
                          ? Icons.school_rounded
                          : Icons.cloud_rounded,
                      color: cs.onPrimary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PlatformManager().isChaoxing ? '学习通' : '雨课堂',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '登录以同步你的课程与活动',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // ---------- 账号 ----------
              TextFormField(
                controller: _usernameController,
                keyboardType: TextInputType.number,
                autofocus: true,
                autofillHints: [
                  AutofillHints.username,
                  AutofillHints.telephoneNumber,
                ],
                decoration: InputDecoration(
                  labelText: '账号',
                  hintText: PlatformManager().isChaoxing ? '手机号 / 超星号' : '手机号 / 邮箱',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '请输入账号';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // ---------- 凭据 ----------
              if (isPassword)
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入密码';
                    return null;
                  },
                )
              else if (isCaptcha)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _captchaController,
                        focusNode: _captchaFocusNode,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        decoration: const InputDecoration(
                          labelText: '验证码',
                          prefixIcon: Icon(Icons.sms_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return '请输入验证码';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () {
                            if (_countdownSeconds == 0 && !_isLoading) {
                              _sendCaptcha();
                              FocusScope.of(context).requestFocus(_captchaFocusNode);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                          child: Text(
                            _countdownSeconds > 0
                                ? '${_countdownSeconds}s'
                                : '获取验证码',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: AppSpacing.xl),

              // ---------- 提交 ----------
              FilledButton(
                onPressed: _isLoading
                    ? null
                    : _currentLoginType == '3'
                        ? _showQRCodeLogin
                        : _login,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        isPassword
                            ? '登录'
                            : isCaptcha
                                ? '验证码登录'
                                : '二维码登录',
                      ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ---------- 提示 ----------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 13, color: cs.outline),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '账号信息仅保存在本机，不会上传到第三方服务器',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
