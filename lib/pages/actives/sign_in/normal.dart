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
  String get signTypeName => '普通签到';

  @override
  Future<void> execute(
      BuildContext context,
      SignInPageState state,
      SignParams params,
      ) async {
    // 不需要额外操作，UI已经在build中集成
  }

  @override
  Future<String?> signForAccount(User user, SignParams params) async {
    final objectId = params.getUserObjectId(user.uid);

    return await SignInApi.normalSign(
      params.courseId,
      params.active.id,
      objectId: objectId,
      validate: params.validate,
    );
  }

  static Widget buildSignArea(SignInPageState state) {
    final needPhoto = state.needPhoto;
    final allPhotoTaken = state.signParams.photoCount == state.selectedAccounts.length;
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '拍照进度: ${state.signParams.photoCount}/${state.selectedAccounts.length}',
                              style: TextStyle(
                                fontSize: 14,
                                color: allPhotoTaken 
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: state.selectedAccounts.isEmpty
                                  ? 0
                                  : state.signParams.photoCount / state.selectedAccounts.length,
                              backgroundColor: Theme.of(context).dividerColor,
                              valueColor: AlwaysStoppedAnimation(
                                allPhotoTaken 
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 拍照按钮
                      ElevatedButton.icon(
                        onPressed: state.selectedAccounts.isEmpty || allPhotoTaken
                            ? null
                            : () => _takeBatchPhotoDirect(state, ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('拍照'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 相册按钮
                      ElevatedButton.icon(
                        onPressed: state.selectedAccounts.isEmpty || allPhotoTaken
                            ? null
                            : () => _takeBatchPhotoDirect(state, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('相册'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 签到按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSign ? () => state.performMultiSign() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '立即签到',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  static Future<void> _takeBatchPhotoDirect(SignInPageState state, ImageSource source) async {
    final BuildContext context = state.context;
    final selectedAccounts = state.selectedAccounts;
    
    if (selectedAccounts.isEmpty) return;
    
    // 请求相应权限
    PermissionStatus status;
    if (source == ImageSource.camera) {
      status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相机权限才能拍照')),
          );
        }
        return;
      }
    } else {
      status = await Permission.photos.request();
      if (status != PermissionStatus.granted) {
        if (context.mounted) {
          // 显示详细的权限说明
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请为应用开启相册访问权限'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }
    
    state.updateMultiSignStatus(true, selectedAccounts.length);
    state.showProgressSnackBar('开始为 ${selectedAccounts.length} 个账号${source == ImageSource.camera ? '拍照' : '选择图片'}...');
    
    final picker = ImagePicker();
    
    for (int i = 0; i < selectedAccounts.length; i++) {
      final user = selectedAccounts[i];
      
      AccountManager.setCurrentSessionTemp(user.uid);
      SignInApi.updateUser();
      state.showProgressSnackBar('正在为账号 ${user.name} ${source == ImageSource.camera ? '拍照' : '选择图片'} (${i + 1}/${selectedAccounts.length})');
      
      try {
        XFile? pickedFile;
        if (source == ImageSource.camera) {
          pickedFile = await picker.pickImage(source: ImageSource.camera);
        } else {
          pickedFile = await picker.pickImage(source: ImageSource.gallery);
        }
        
        if (pickedFile != null) {
          final File imageFile = File(pickedFile.path);
          final String? objectId = await SignInApi.uploadImage(imageFile);
          if (objectId != null) {
            state.signParams.setUserObjectId(user.uid, objectId);
            state.updatePhotoProgress(i + 1);
          } else {
            state.addFailedAccount('${user.name} (上传失败)');
          }
        } else {
          state.addFailedAccount('${user.name} (未选择图片)');
        }
      } catch (e) {
        state.addFailedAccount('${user.name} (处理异常: $e)');
      }
      
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    // 恢复原账号
    if (state.currentUser != null) {
      AccountManager.setCurrentSessionTemp(state.currentUser!.uid);
    }
    
    state.updateMultiSignStatus(false);
    state.showPhotoResult(state.signParams.photoCount, selectedAccounts.length);
  }
}