import 'package:flutter/material.dart';
import '../api/login.dart';
import '../models/user.dart';
import '../session/account.dart';

import 'dart:async';
import 'dart:typed_data';

/// 统一的登录成功处理函数
Future<bool> handlePostLoginSuccess(BuildContext context) async {
  try {
    final userInfo = await LoginApi.getUserInfo();
    if (userInfo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取用户信息失败')),
        );
      }
      return false;
    }
    final data = userInfo['msg'];
    final user = User(
      uid: data['puid']?.toString() ?? '',
      name: data['name'] ?? '未知用户',
      avatar: data['pic'] ?? '',
      phone: data['phone'] ?? '未知手机号',
    );
    await AccountManager.addAccount(user);

    final currentSession = await AccountManager.getCurrentSession();
    if (currentSession == user.uid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} 登录成功')),
        );
      }
      return true;
    } else {
      debugPrint('会话设置失败，当前会话: $currentSession');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录状态异常')),
        );
      }
      return false;
    }
  } catch (e) {
    debugPrint('处理登录成功失败: $e');
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
  String? qrEnc;
  Uint8List? qrImageData;
  bool isLoading = true;
  bool isRefreshing = false;
  bool isLoginActive = true;

  Timer? _pollingTimer;

  /// 初始化二维码数据
  Future<bool> initialize() async {
    try {
      final qrData = await LoginApi.getQRCodeData();
      if (qrData != null) {
        qrUuid = qrData['uuid'];
        qrEnc = qrData['enc'];
        final imageData = await LoginApi.getQRCodeImage(qrUuid!);
        qrImageData = imageData;
        isLoading = false;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('初始化二维码失败: $e');
      return false;
    }
  }

  /// 开始轮询登录状态
  void startPolling(Function(bool success) onLoginComplete) {
    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!isLoginActive || qrUuid == null || qrEnc == null) {
        timer.cancel();
        return;
      }

      try {
        final result = await LoginApi.checkQRAuthStatus(qrUuid!, qrEnc!);
        if (result != null) {
          if (result['status'] == true) {
            timer.cancel();
            onLoginComplete(true);
          } else if (result['type']?.toString() == '2') {
            timer.cancel();
            await refreshQRCode();
          }
        }
      } catch (e) {
        debugPrint('轮询失败: $e');
      }
    });
  }

  /// 刷新二维码
  Future<void> refreshQRCode() async {
    if (isRefreshing) return;

    isRefreshing = true;
    try {
      final qrData = await LoginApi.getQRCodeData();
      if (qrData != null) {
        qrUuid = qrData['uuid'];
        qrEnc = qrData['enc'];
        final imageData = await LoginApi.getQRCodeImage(qrUuid!);
        qrImageData = imageData;
      }
    } catch (e) {
      debugPrint('刷新二维码失败: $e');
    } finally {
      isRefreshing = false;
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
  bool _isLoading = false;
  bool _showPassword = false;
  String _currentLoginType = '1'; // '1'密码登录，'2'验证码登录，'3'二维码登录
  Timer? _countdownTimer;
  int _countdownSeconds = 0;

  @override
  void initState() {
    super.initState();
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
      if (success) {
        final loginSuccess = await handlePostLoginSuccess(context);
        if (loginSuccess && mounted) {
          Navigator.pop(context, true);
        }
      }
      qrState.dispose();
    });

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                      child: qrState.qrImageData != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          qrState.qrImageData!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      )
                          : qrState.isLoading
                          ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('生成中...', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      )
                          : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('二维码加载失败', style: TextStyle(color: Colors.grey)),
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
                  TextButton(
                    onPressed: qrState.isRefreshing || qrState.isLoading
                        ? null
                        : () async {
                      setState(() {
                        qrState.isRefreshing = true;
                      });
                      await qrState.refreshQRCode();
                      setState(() {
                        qrState.isRefreshing = false;
                      });
                    },
                    child: qrState.isRefreshing ? const Text('刷新中...') : const Text('刷新'),
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

  /// 密码/验证码登录
  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        Map<String, dynamic>? result = await LoginApi.loginAPP(
          _currentLoginType,
          _usernameController.text,
          _currentLoginType == '2' ? _captchaController.text : _passwordController.text,
        );

        if (result != null && result['status']) {
          if (!result.containsKey('url')) {
            await _showSecurityVerificationDialog();
          }

          final success = await handlePostLoginSuccess(context);
          if (success && mounted) {
            Navigator.pop(context, true);
          }
        } else {
          if (mounted) {
            String errorMessage = result?['mes'] ?? '登录失败，请检查账号密码';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage)),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('登录时发生错误: $e')),
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

    try {
      setState(() {
        _isLoading = true;
      });

      var result = await LoginApi.sendCaptcha(phone);

      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('发送验证码失败，请重试')),
          );
        }
        return;
      }

      if (result['status'] && result['mes'].contains('已发送')) {
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
        String message = result['mes'] ?? '发送验证码失败';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送验证码时发生错误: $e')),
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(_currentLoginType == '1'
            ? '密码登录'
            : _currentLoginType == '2'
            ? '验证码登录'
            : '二维码登录'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: _usernameController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '账号',
                      hintText: '手机号/超星号',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入账号';
                      }
                      return null;
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _currentLoginType == '1'
                      ? TextFormField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _showPassword = !_showPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                  )
                      : Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _captchaController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '验证码',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入验证码';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _countdownSeconds > 0 || _isLoading
                              ? null
                              : _sendCaptcha,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _countdownSeconds > 0
                                ? Colors.grey
                                : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            _countdownSeconds > 0
                                ? '${_countdownSeconds}s'
                                : '获取验证码',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : _currentLoginType == '3'
                        ? _showQRCodeLogin
                        : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      //padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      _currentLoginType == '1'
                          ? '登录'
                          : _currentLoginType == '2'
                          ? '验证码登录'
                          : '二维码登录',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}