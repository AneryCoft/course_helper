import 'package:flutter/material.dart';

import '../../../../models/user.dart';
import '../../../../api/sign_in.dart';
import '../../../../api/face.dart';
import 'sign_in.dart';

class LocationSign implements SignStrategy {
  @override
  Future<void> execute(
      BuildContext context,
      SignInPageState state,
      SignParams params,
      ) async {
    // UI已在build中集成
  }

  @override
  Future<String?> signForAccount(User user, SignParams params, SignInPageState state) async {
    final api = SignInApi(user);
    if (state.isGroupSign) {
      return await api.groupSign(
          params.active.id,
          address: params.address,
          latitude: params.latitude,
          longitude: params.longitude
      );
    }

    final userValidate = state.getUserCaptchaValidate(user.uid);
    final validate = userValidate?['validate'];
    
    String? faceId;
    String? faceEnc;
    if (state.needFace) {
      final faceApi = FaceApi(user);
      faceId = await faceApi.getFaceId();
      if (faceId != null && faceId.isNotEmpty) {
        faceEnc = await faceApi.getFaceEnc(params.active.id, faceId);
      }
    }

    return await api.locationSign(
      params.courseId,
      params.active.id,
      params.address!,
      params.latitude!,
      params.longitude!,
      validate: validate,
      faceId: faceId,
      faceEnc: faceEnc
    );
  }

  static Widget buildSignArea(SignInPageState state) {
    return SignLocationUi.wrapWithAutoFill(
      state,
      buildChildren: (context) {
        return SignLocationUi.buildSection(
          context,
          state,
          alwaysShow: true,
          showSignButton: true,
          onReselect: () => SignLocationUi.showPicker(state, autoSign: true),
        );
      },
    );
  }
}
