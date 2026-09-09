import 'package:flutter/material.dart';

import '../../../../models/user.dart';
import '../../../../api/sign_in.dart';
import '../../../../api/face.dart';
import '../../widget/scan.dart';
import 'sign_in.dart';

class QRCodeSign implements SignStrategy {
  @override
  Future<void> execute(
    BuildContext context,
    SignInPageState state,
    SignParams params,
  ) async {
    if (params.enc != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.performMultiSign();
      });
    }
  }

  @override
  Future<String?> signForAccount(
    User user,
    SignParams params,
    SignInPageState state,
  ) async {
    final api = SignInApi(user);
    final userValidate = state.getUserCaptchaValidate(user.uid);
    final validate = userValidate?['validate'];
    final enc2 = userValidate?['enc2'];

    String? faceId;
    String? faceEnc;
    if (state.needFace) {
      final faceApi = FaceApi(user);
      faceId = await faceApi.getFaceId();
      if (faceId != null && faceId.isNotEmpty) {
        faceEnc = await faceApi.getFaceEnc(params.active.id, faceId);
      }
    }

    return await api.qrCodeSign(
      params.courseId,
      params.active.id,
      params.enc!,
      address: params.address,
      latitude: params.latitude,
      longitude: params.longitude,
      enc2: enc2,
      validate: validate,
      faceId: faceId,
      faceEnc: faceEnc
    );
  }

  static Widget buildSignArea(SignInPageState state) {
    final hasLocation = state.signParams.address != null;

    return SignLocationUi.wrapWithAutoFill(
      state,
      buildChildren: (context) {
        return [
          // 定位相关UI
          ...SignLocationUi.buildSection(context, state),

          // 二维码扫描按钮（始终显示，位于位置信息下方）
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _scanQRCode(state),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫描二维码'),
              style: ElevatedButton.styleFrom(
                backgroundColor: (state.designatedPlace == null || hasLocation) ?
                Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // 二维码已扫描后的立即签到按钮
          if (state.signParams.enc != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => state.performMultiSign(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('立即签到'),
              ),
            ),
          ],
        ];
      },
    );
  }

  static void _scanQRCode(SignInPageState state) {
    final BuildContext context = state.context;

    // 权限已获得，打开扫描页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanPage(
          onScanResult: (String data) async {
            state.signParams.qrCodeData = data;

            try {
              final uri = Uri.parse(state.signParams.qrCodeData!);
              final baseUrl = uri.origin + uri.path;
              final queryParams = uri.queryParameters;

              if (baseUrl == 'https://mobilelearn.chaoxing.com/widget/sign/e') {
                if (queryParams['id'] == state.widget.active.id) {
                  final code = queryParams['c'];
                  state.signParams.enc = queryParams['enc']!;

                  final signDetail = await SignInApi.getSignDetail(
                    state.widget.active.id,
                    code,
                  );
                  final String signCode = signDetail?['signCode'];
                  if (signCode.isEmpty || code == signDetail?['signCode']) {
                    state.performMultiSign();
                  } else {
                    state.showErrorMessage('二维码已过期');
                  }
                } else {
                  state.showErrorMessage('二维码非该活动');
                }
              } else {
                state.showErrorMessage('错误二维码');
              }
            } catch (e) {
              state.showErrorMessage('二维码解析失败: $e');
            }
          },
        ),
      ),
    );
  }
}
