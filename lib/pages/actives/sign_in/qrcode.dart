import 'package:flutter/material.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';

import '../../../../models/user.dart';
import '../../../../api/sign_in.dart';
import '../../widget/baidu_map.dart';
import '../../widget/scan.dart';
import 'sign_in.dart';

class QRCodeSign implements SignStrategy {
  @override
  String get signTypeName => '二维码签到';

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
  Future<String?> signForAccount(User user, SignParams params, SignInPageState state) async {
    final userValidate = state.getUserCaptchaValidate(user.uid);
    final validate = userValidate?['validate'];
    final enc2 = userValidate?['enc2'];
    
    return await SignInApi.qrCodeSign(
      params.courseId,
      params.active.id,
      params.enc!,
      user,
      address: params.address,
      latitude: params.latitude,
      longitude: params.longitude,
      enc2: enc2,
      validate: validate
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
                  if (state.designatedPlace != null && state.designatedPlace!.isNotEmpty && state.signParams.address == null) ...[
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
                    const SizedBox(height: 16),
                  ],

                  // 已选择位置信息区域（放在扫描按钮上方）
                  if (state.signParams.address != null) ...[
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
                                child: OutlinedButton(
                                  onPressed: () {
                                    state.signParams.address = null;
                                    state.signParams.latitude = null;
                                    state.signParams.longitude = null;
                                    if (state.mounted) {
                                      (state.context as Element).markNeedsBuild();
                                    }
                                  },
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

                  // 二维码扫描按钮（始终显示，位于位置信息下方）
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _scanQRCode(state),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫描二维码'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  // 二维码已扫描后的立即签到按钮
                  if (state.signParams.enc != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '二维码已扫描，点击下方按钮签到',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => state.performMultiSign(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('立即签到'),
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

  /// 位置选择页面
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
                          Navigator.pop(context); // 关闭地图页，不自动签到
                          // 返回后刷新UI，显示已选择位置
                          if (state.mounted) {
                            (state.context as Element).markNeedsBuild();
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
                      child: const Text('确认选择'), // 按钮文本为“确认选择”
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

                  final signDetail = await SignInApi.getSignDetail(state.widget.active.id, code);
                  if (code == signDetail?['signCode']) {
                    if (state.mounted) {
                      (state.context as Element).markNeedsBuild();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        state.performMultiSign();
                      });
                    }
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