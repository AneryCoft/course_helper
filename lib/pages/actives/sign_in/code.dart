import 'package:flutter/material.dart';

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
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    final numberCount = widget.state.signParams.numberCount;
    _controllers = List.generate(numberCount, (index) => TextEditingController());
    _focusNodes = List.generate(numberCount, (index) => FocusNode());

    // 监听输入变化
    for (var i = 0; i < numberCount; i++) {
      _controllers[i].addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.removeListener(_onTextChanged);
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    final code = _controllers.map((c) => c.text).join();
    widget.state.signParams.code = code;
  }

  @override
  Widget build(BuildContext context) {
    final numberCount = widget.state.signParams.numberCount;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(numberCount, (index) {
        return SizedBox(
          width: 50,
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            maxLength: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              counterText: '',
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            onChanged: (value) {
              if (value.length == 1 && index < numberCount - 1) {
                // 自动跳到下一个输入框
                FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
              }

              // 输入完成时自动验证
              final currentCode = _controllers.map((c) => c.text).join();
              if (currentCode.length == numberCount) {
                _verifyAndAutoSign();
              }
            },
          ),
        );
      }),
    );
  }

  Future<void> _verifyAndAutoSign() async {
    final code = widget.state.signParams.code;

    // 验证签到码是否正确
    bool? isValid = await SignInApi.checkSignCode(
      widget.state.widget.active.id,
      code,
    );

    if (isValid == true) {
      // 验证通过，执行签到
      widget.state.performMultiSign();
    } else {
      widget.state.showErrorMessage('签到码不正确，请重新输入');

      // 清空所有输入框
      for (var controller in _controllers) {
        controller.clear();
      }
      widget.state.signParams.code = '';

      // 焦点回到第一个输入框
      _focusNodes[0].requestFocus();
    }
  }
}