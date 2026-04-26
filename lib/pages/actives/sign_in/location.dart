import 'package:flutter/material.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';

import '../../../../models/user.dart';
import '../../../../api/sign_in.dart';
import '../../../../setting/course_setting.dart';
import '../../../../models/course.dart';
import '../../widget/baidu_map.dart';
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
    final userValidate = state.getUserCaptchaValidate(user.uid);
    final validate = userValidate?['validate'];
    
    String? faceId;
    if (state.needFace) {
      faceId = await SignInApi.getFaceId(user);
    }
    
    return await SignInApi.locationSign(
      params.courseId,
      params.active.id,
      params.address ?? '未知位置',
      params.latitude ?? 0,
      params.longitude ?? 0,
      user,
      validate: validate,
      faceId: faceId,
    );
  }

  static Widget buildSignArea(SignInPageState state) {
    final hasLocation = state.signParams.address != null;

    return FutureBuilder<CourseSettings?>(
      future: _loadCourseLocation(state),
      builder: (context, snapshot) {
        // 课程配置选择位置
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

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

                if (!hasLocation) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showLocationPicker(state),
                      icon: const Icon(Icons.location_on),
                      label: const Text('选择签到位置'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ] else ...[
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
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _showLocationPicker(state),
                                child: const Text('重新选择'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    );
  }

  /// 加载课程位置配置
  static Future<CourseSettings?> _loadCourseLocation(SignInPageState state) async {
    final courseId = state.signParams.courseId;
    if (courseId.isEmpty) return null;
    return await CourseSetting.getSettings(courseId);
  }

  static Future<void> _showLocationPicker(SignInPageState state) async {
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
              // 底部确认按钮
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (selectedCoordinate != null) {
                          state.signParams.latitude = selectedCoordinate!.latitude;
                          state.signParams.longitude = selectedCoordinate!.longitude;
                          state.signParams.address = selectedAddress?.isEmpty ?? true
                              ? '未知位置'
                              : selectedAddress!;
                          Navigator.pop(context);
                          
                          // 异步保存位置到课程配置
                          _saveLocationToCourse(state);
                          
                          state.performMultiSign();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请先点击地图选择位置')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('确认选择并签到'),
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

  /// 异步保存位置到课程配置
  static Future<void> _saveLocationToCourse(SignInPageState state) async {
    await saveLocationToCourse(state);
  }

  /// 公共方法：保存位置到课程配置
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