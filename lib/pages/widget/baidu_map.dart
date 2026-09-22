import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_search/flutter_baidu_mapapi_search.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';

class BaiduMapWidget extends StatefulWidget {
  final Function(BMFCoordinate)? onLocationSelected;
  final Function(BMFCoordinate, String)? onLocationSelectedWithAddress;
  final bool showLocationButton;
  final bool showCurrentLocationInfo;

  const BaiduMapWidget({
    super.key,
    this.onLocationSelected,
    this.onLocationSelectedWithAddress,
    this.showLocationButton = true,
    this.showCurrentLocationInfo = true,
  });

  @override
  State<BaiduMapWidget> createState() => _BaiduMapWidgetState();
}

class _BaiduMapWidgetState extends State<BaiduMapWidget> {
  BMFMapController? _mapController;
  BMFCoordinate? _currentPosition;
  BMFCoordinate? _markerPosition;
  String _locationInfo = '正在获取位置...';
  bool _isLoading = true;
  bool _isDisposed = false;
  bool _isLocating = false;

  /// 是否已经移动过地图
  bool _hasMovedToLocation = false;

  /// 是否为用户主动触发
  bool _isManualRelocate = false;

  /// 本次定位请求是否已收到首次回调结果
  /// Android 端 singleLocation 底层复用连续定位回调
  bool _hasReceivedFirstFix = false;

  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();

  @override
  void initState() {
    super.initState();
    BMFMapSDK.setAgreePrivacy(true);
    _initLocation();
  }

  /// 初始化定位
  Future<void> _initLocation() async {
    final hasPermission = await _checkPermissions();
    if (_isDisposed) return;

    if (!hasPermission) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    await _initBaiduLocation();
    if (_isDisposed) return;

    await _getCurrentLocation(manual: false);
    if (_isDisposed) return;

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initBaiduLocation() async {
    _locationPlugin.singleLocationCallback(callback: (BaiduLocation result) {
      if (_isDisposed) return;

      if (result.locType != null && result.locType! > 0) {
        final coord = BMFCoordinate(result.latitude!, result.longitude!);
        _handleLocationUpdate(coord, result);
      } else {
        if (mounted) {
          setState(() {
            _locationInfo = '定位失败，请重试';
            _isLocating = false;
            _isManualRelocate = false;
          });
        }
      }
    });

    await _prepareHighAccuracyLocation();
  }

  /// 配置定位参数
  Future<void> _prepareHighAccuracyLocation() async {
    try {
      final androidOptions = BaiduLocationAndroidOption(
        coordType: BMFLocationCoordType.bd09ll,
        isNeedAddress: true,
        isNeedAltitude: false,
        isNeedLocationPoiList: false,
        isNeedNewVersionRgc: true,
        isNeedLocationDescribe: false,
        openGps: true,
        locationPurpose: BMFLocationPurpose.signIn
      );

      final iosOptions = BaiduLocationIOSOption(
        coordType: BMFLocationCoordType.bd09ll,
        locationTimeout: 15,
        reGeocodeTimeout: 15,
        desiredAccuracy: BMFDesiredAccuracy.best,
        distanceFilter: 3.0,
      );

      await _locationPlugin.prepareLoc(
        androidOptions.getMap(),
        iosOptions.getMap(),
      );
    } catch (e) {
      debugPrint('配置定位参数失败：$e');
    }
  }

  /// 处理定位结果
  void _handleLocationUpdate(BMFCoordinate coordinate, BaiduLocation location) {
    if (_isDisposed || !mounted) return;

    // 忽略重复定位回调
    if (_hasReceivedFirstFix) {
      return;
    }
    _hasReceivedFirstFix = true;

    setState(() {
      _currentPosition = coordinate;
      _isLocating = false;
      _locationInfo =
      '地址：${location.address ?? ''}\n纬度：${coordinate.latitude.toStringAsFixed(6)}, 经度：${coordinate.longitude.toStringAsFixed(6)}';
    });

    if (_mapController != null) {
      _updateMarkerToPosition(coordinate, triggerCallback: true).then((_) {
        if (_isDisposed || !mounted) return;

        // 只在首次定位 或 用户主动重新定位时移动地图，避免"左右横跳"
        if (!_hasMovedToLocation || _isManualRelocate) {
          _moveToMarkerPosition();
          _hasMovedToLocation = true;
          _isManualRelocate = false;
        }
      });
    }
  }

  /// 发起定位
  Future<void> _getCurrentLocation({bool manual = true}) async {
    if (_isDisposed || _isLocating) return;

    setState(() {
      _isLocating = true;
      _hasReceivedFirstFix = false; // 重置单次定位守卫
      _isManualRelocate = manual; // 用户主动时才允许再次移动地图
      _locationInfo = '正在定位...';
    });

    try {
      // 避免残留
      await _locationPlugin.stopLocation();
      if (_isDisposed) return;

      await _locationPlugin.singleLocation({
        'isReGeocode': true,
        'isNetworkState': true,
      });

      Future.delayed(const Duration(seconds: 15), () {
        if (_isDisposed || !mounted) return;
        if (_isLocating) {
          setState(() {
            _isLocating = false;
            _isManualRelocate = false;
            _locationInfo = '定位超时，请重试';
          });
        }
      });
    } catch (e) {
      debugPrint('定位失败：$e');
      if (!_isDisposed && mounted) {
        setState(() {
          _locationInfo = '定位失败：$e';
          _isLocating = false;
          _isManualRelocate = false;
        });
      }
    }
  }

  /// 权限检查（保留 permission_handler 实现，可区分"永久拒绝"）
  Future<bool> _checkPermissions() async {
    var status = await Permission.location.status;

    if (status.isDenied) {
      await Permission.location.request();
      status = await Permission.location.status;
    }

    if (_isDisposed) return false;

    if (status.isPermanentlyDenied) {
      if (mounted) setState(() => _locationInfo = '定位权限被永久拒绝，请前往设置手动开启');
      return false;
    }

    return status.isGranted || PermissionStatus.limited == status;
  }

  Future<String> _updateMarkerToPosition(
      BMFCoordinate position, {
        bool triggerCallback = false,
      }) async {
    if (_isDisposed || _mapController == null) return '';

    await _mapController!.cleanAllMarkers();
    if (_isDisposed || _mapController == null) return '';

    BMFMarker marker = BMFMarker.icon(
      position: position,
      icon: 'images/placeholder.png',
      title: '当前位置',
      scaleX: 0.3,
      scaleY: 0.3
    );
    await _mapController!.addMarker(marker);
    if (_isDisposed || _mapController == null) return '';

    String address = await _getAddressFromCoordinate(position);
    if (_isDisposed || !mounted) return address;

    setState(() {
      _markerPosition = position;
      _locationInfo = '地址：$address\n纬度：${position.latitude.toStringAsFixed(6)}, 经度：${position.longitude.toStringAsFixed(6)}';
    });

    if (triggerCallback) {
      _triggerCallback(position, address);
    }

    return address;
  }

  void _triggerCallback(BMFCoordinate coordinate, String address) {
    if (widget.onLocationSelectedWithAddress != null) {
      widget.onLocationSelectedWithAddress!(coordinate, address);
    } else if (widget.onLocationSelected != null) {
      widget.onLocationSelected!(coordinate);
    }
  }

  void _moveToMarkerPosition() {
    if (_isDisposed || _mapController == null || _markerPosition == null) return;
    _mapController!
        .setCenterCoordinate(_markerPosition!, true, animateDurationMs: 1000);
    _mapController!.setZoomTo(20.0, animateDurationMs: 1000);
  }

  Future<String> _getAddressFromCoordinate(BMFCoordinate coordinate) async {
    if (_isDisposed) return '未知位置';
    try {
      BMFReverseGeoCodeSearchOption option =
      BMFReverseGeoCodeSearchOption(location: coordinate);
      BMFReverseGeoCodeSearch search = BMFReverseGeoCodeSearch();
      Completer<String> completer = Completer<String>();

      search.onGetReverseGeoCodeSearchResult(
          callback: (BMFReverseGeoCodeSearchResult? result,
              BMFSearchErrorCode errorCode) {
            if (completer.isCompleted) return;
            String address = '';
            if (result != null) {
              address = result.address ?? '';
              if (address.isEmpty &&
                  result.poiList != null &&
                  result.poiList!.isNotEmpty) {
                address = result.poiList!.first.name ?? '';
              }
            }
            completer.complete(address.isNotEmpty ? address : '未知位置');
          });

      await search.reverseGeoCodeSearch(option);

      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => '未知位置',
      );
    } catch (e) {
      return '未知位置';
    }
  }

  void _onMapTap(BMFCoordinate coordinate) async {
    if (_isDisposed || _mapController == null) return;

    await _updateMarkerToPosition(coordinate, triggerCallback: true);
    if (_isDisposed || _mapController == null) return;

    _mapController!.setCenterCoordinate(coordinate, true, animateDurationMs: 500);
    _mapController!.setZoomTo(20.0, animateDurationMs: 500);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : BMFMapWidget(
            onBMFMapCreated: (controller) {
              if (_isDisposed) return;
              _mapController = controller;

              if (_currentPosition != null) {
                _updateMarkerToPosition(_currentPosition!,
                    triggerCallback: true)
                    .then((_) {
                  if (_isDisposed || !mounted) return;
                  if (!_hasMovedToLocation) {
                    _moveToMarkerPosition();
                    _hasMovedToLocation = true;
                  }
                });
              }

              _mapController!.setMapOnClickedMapBlankCallback(
                callback: (coordinate) => _onMapTap(coordinate),
              );
            },
            mapOptions: BMFMapOptions(
              center: _currentPosition ?? BMFCoordinate(0.0, 0.0),
              zoomLevel: 20,
              mapType: BMFMapType.Standard,
            ),
          ),
        ),
        if (widget.showCurrentLocationInfo)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.5),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('位置信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_locationInfo,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLocating ? null : () => _getCurrentLocation(manual: true),
                      icon: _isLocating
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.my_location, size: 18),
                      label: Text(_isLocating ? '定位中...' : '重新定位'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (widget.showLocationButton)
                      ElevatedButton.icon(
                        onPressed: _moveToMarkerPosition,
                        icon: const Icon(Icons.center_focus_strong, size: 18),
                        label: const Text('回到中心'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          Theme.of(context).colorScheme.secondary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _locationPlugin.stopLocation();
    _mapController = null;
    super.dispose();
  }
}