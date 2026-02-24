import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

import '../../../../models/user.dart';
import '../../../../api/sign_in.dart';
import 'sign_in.dart';

class CodeSign implements SignStrategy {
  @override
  String get signTypeName => '签到码签到';

  @override
  Future<void> execute(
      BuildContext context,
      SignInPageState state,
      SignParams params,
      ) async {
  }

  @override
  Future<String?> signForAccount(User user, SignParams params) async {
    return await SignInApi.codeSign(
      params.courseId,
      params.active.id,
      params.code,
      validate: params.validate,
    );
  }

  static Widget buildSignArea(SignInPageState state) {
    return Builder(
      builder: (BuildContext context) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('请输入 ${state.signParams.numberCount} 位签到码'),
                const SizedBox(height: 16),
                _CodeInputField(state: state),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: state.getCodeInput().length == state.signParams.numberCount
                        ? () => _verifyAndSign(state)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('确认签到'),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  static Future<void> _verifyAndSign(SignInPageState state) async {
    final code = state.signParams.code;

    // 验证签到码是否正确
    bool? isValid = await SignInApi.checkSignCode(
      state.widget.active.id,
      code,
    );

    if (isValid == true) {
      // 验证通过，执行签到
      state.performMultiSign();
    } else {
      // 验证失败，清空输入并提示错误
      state.showErrorMessage('签到码不正确，请重新输入');
      state.signParams.code = '';

      // 刷新UI，清除输入框
      if (state.mounted) {
        (state.context as Element).markNeedsBuild();
      }
    }
  }
}

class _CodeInputField extends StatefulWidget {
  final SignInPageState state;

  const _CodeInputField({required this.state});

  @override
  State<_CodeInputField> createState() => _CodeInputFieldState();
}

class _CodeInputFieldState extends State<_CodeInputField> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    // 监听输入变化
    _pinController.addListener(_onPinChanged);
  }
  
  @override
  void dispose() {
    _pinController.removeListener(_onPinChanged);
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }
  
  void _onPinChanged() {
    widget.state.signParams.code = _pinController.text;
  }
  
  @override
  Widget build(BuildContext context) {
    final numberCount = widget.state.signParams.numberCount;
    
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 60,
      textStyle: const TextStyle(
        fontSize: 22,
        color: Color.fromRGBO(30, 60, 87, 1),
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.transparent),
      ),
    );

    return SizedBox(
      height: 68,
      child: Pinput(
        length: numberCount,
        controller: _pinController,
        focusNode: _pinFocusNode,
        defaultPinTheme: defaultPinTheme,
        keyboardType: TextInputType.number,
        autofillHints: null,
        showCursor: true,
        focusedPinTheme: defaultPinTheme.copyWith(
          height: 68,
          width: 64,
          decoration: defaultPinTheme.decoration!.copyWith(
            border: Border.all(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        errorPinTheme: defaultPinTheme.copyWith(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onCompleted: (pin) {
          widget.state.signParams.code = pin;
          _verifyAndAutoSign();
        },
      ),
    );
  }
  
  Future<void> _verifyAndAutoSign() async {
    bool? isValid = await SignInApi.checkSignCode(
      widget.state.widget.active.id,
      widget.state.signParams.code
    );
    
    if (isValid == true) {
      // 验证通过，执行签到
      widget.state.performMultiSign();
    } else {
      widget.state.showErrorMessage('签到码不正确，请重新输入');
      
      // 清空输入
      _pinController.clear();
      widget.state.signParams.code = '';
      
      // 焦点回到输入框
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pinFocusNode.requestFocus();
        }
      });
    }
  }
}