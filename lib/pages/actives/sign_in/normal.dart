import 'package:course_helper/api/image.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../models/user.dart';
import '../../../../session/account.dart';
import '../../../../api/sign_in.dart';
import 'sign_in.dart';


class NormalSign implements SignStrategy {
  @override
  Future<void> execute(
      BuildContext context,
      SignInPageState state,
      SignParams params,
      ) async {
    // 不需要额外操作，图片分配在账号选择回调中处理
  }

  @override
  Future<String?> signForAccount(User user, SignParams params, SignInPageState state) async {
    final objectId = params.getUserObjectId(user.uid);
    if (state.isGroupSign) {
      return await SignInApi.groupSign(
          params.active.id,
          user,
          objectId: objectId
      );
    }

    final userValidate = state.getUserCaptchaValidate(user.uid);
    final validate = userValidate?['validate'];

    return await SignInApi.normalSign(
      params.courseId,
      params.active.id,
      user,
      objectId: objectId,
      validate: validate,
    );
  }

  static Widget buildSignArea(SignInPageState state) {
    final needPhoto = state.needPhoto;
    // 检查所有选中的账号是否都有objectId
    final allPhotoTaken = state.selectedAccounts.every((user) {
      final objectId = state.signParams.getUserObjectId(user.uid);
      return objectId != null && objectId.isNotEmpty;
    });
    final canSign = state.selectedAccounts.isNotEmpty && (!needPhoto || allPhotoTaken);

    return Builder(
      builder: (BuildContext context) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (needPhoto) ...[
                  // 拍照和相册按钮
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: state.selectedAccounts.isEmpty || allPhotoTaken ?
                          null : () => _takeBatchPhotoDirect(state, ImageSource.camera, context),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('拍照'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white
                          )
                        ),
                        const SizedBox(width: 32),
                        ElevatedButton.icon(
                          onPressed: state.selectedAccounts.isEmpty || allPhotoTaken ?
                          null : () => _takeBatchPhotoDirect(state, ImageSource.gallery, context),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('相册'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white
                          )
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 签到按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSign ? () {
                      if (needPhoto && state.signParams.photoCount < state.selectedAccounts.length) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('请为所有账号上传照片（已上传 ${state.signParams.photoCount}/${state.selectedAccounts.length}）'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      state.performMultiSign();
                    } : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '立即签到',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  static Future<void> _takeBatchPhotoDirect(SignInPageState state, ImageSource source, BuildContext context) async {
    final BuildContext context = state.context;
    final selectedAccounts = state.selectedAccounts;
    
    if (selectedAccounts.isEmpty) return;

    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相机权限才能拍照')),
          );
        }
        return;
      }
    }
    
    final picker = ImagePicker();
    List<XFile> pickedFiles = [];
    
    // 计算起始索引（从已上传的数量开始）
    final startIndex = state.signParams.photoCount;
    final neededCount = selectedAccounts.length;
    
    try {
      if (source == ImageSource.gallery) {
        final photoCount = neededCount - startIndex;
        // pickMultiImage 的 limit 不能小于 2
        if (photoCount <= 1) {
          final pickedFile = await picker.pickImage(source: ImageSource.gallery);
          if (pickedFile != null) {
            pickedFiles = [pickedFile];
          }
        } else {
          pickedFiles = await picker.pickMultiImage(limit: photoCount);
        }
      } else {
        final pickedFile = await picker.pickImage(source: ImageSource.camera);
        if (pickedFile != null) {
          pickedFiles = [pickedFile];
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片错误：$e')),
        );
      }
      return;
    }
    
    if (pickedFiles.isEmpty) {
      return;
    }

    final int remainingCount = neededCount - startIndex;
    if (pickedFiles.length > remainingCount) {
      pickedFiles = pickedFiles.sublist(0, remainingCount);
    }
    
    final failedAccounts = <String>[];
    
    // 串行上传图片（避免token冲突）
    for (int i = 0; i < pickedFiles.length; i++) {
      final int index = startIndex + i;
      final user = selectedAccounts[index];
      final pickedFile = pickedFiles[i];
      
      AccountManager.setCurrentSessionTemp(user.uid);
      
      // 设置图片和上传状态
      state.setUserImage(user.uid, File(pickedFile.path));
      state.setUserUploadingStatus(user.uid, true);
      
      try {
        final objectId = await CXImageApi.uploadImage(File(pickedFile.path), user.uid);
        
        if (objectId != null) {
          state.signParams.setUserObjectId(user.uid, objectId);
          state.setUserUploadingStatus(user.uid, false);
          state.refresh();
        } else {
          failedAccounts.add('${user.name} (上传失败)');
          state.signParams.setUserObjectId(user.uid, '');
          state.setUserUploadFailed(user.uid);
        }
      } catch (e) {
        failedAccounts.add('${user.name} (处理异常: $e)');
        state.setUserUploadFailed(user.uid);
      }
    }
    AccountManager.setCurrentSessionTemp(state.currentUser!.uid);
  }
}