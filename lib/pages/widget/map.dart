import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';
import 'package:flutter_baidu_mapapi_search/flutter_baidu_mapapi_search.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../api/map_tencent.dart';
import '../../utils/logger.dart';


class MapPoint {
  final double latitude;
  final double longitude;

  const MapPoint(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is MapPoint &&
              runtimeType == other.runtimeType &&
              latitude == other.latitude &&
              longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'MapPoint($latitude, $longitude)';
}


class LocationMapWidget extends StatefulWidget {
  final Function(MapPoint)? onLocationSelected;
  final Function(MapPoint, String)? onLocationSelectedWithAddress;
  final bool showLocationButton;
  final bool showCurrentLocationInfo;

  const LocationMapWidget({
    super.key,
    this.onLocationSelected,
    this.onLocationSelectedWithAddress,
    this.showLocationButton = true,
    this.showCurrentLocationInfo = true,
  });

  @override
  State<LocationMapWidget> createState() => _LocationMapWidgetState();
}

class _LocationMapWidgetState extends State<LocationMapWidget> {
  static const int _defaultZoomLevel = 20;
  static const int _mapMoveDurationMs = 1000;
  static const int _mapTapMoveDurationMs = 500;

  BMFMapController? _mapController;
  BMFCoordinate? _currentPosition;
  BMFCoordinate? _markerPosition;
  String _locationInfo = '正在获取位置...';
  bool _isLoading = true;
  bool _isDisposed = false;
  bool _isLocating = false;

  /// 是否已经移动过地图（防止反复回调）
  bool _hasMovedToLocation = false;

  /// 用户主动触发重新定位
  bool _isManualRelocate = false;

  /// 定位请求是否已收到首次回调结果
  bool _hasReceivedFirstFix = false;

  Timer? _locationTimeoutTimer;

  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();
  final _GeocodeService _geocodeService = _GeocodeService();

  bool get _isActive => !_isDisposed && mounted;

  @override
  void initState() {
    super.initState();
    BMFMapSDK.setAgreePrivacy(true);
    _initLocation();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _locationTimeoutTimer?.cancel();
    _locationPlugin.stopLocation();
    _mapController = null;
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      if (!await _checkPermissions()) return;
      if (!_isActive) return;

      await _initBaiduLocation();
      if (!_isActive) return;

      await _getCurrentLocation(manual: false);
    } finally {
      if (_isActive) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkPermissions() async {
    var status = await Permission.location.status;

    if (status.isDenied) {
      await Permission.location.request();
      status = await Permission.location.status;
    }

    if (!_isActive) return false;

    if (status.isPermanentlyDenied) {
      if (mounted) {
        setState(() => _locationInfo = '定位权限被永久拒绝，请前往设置手动开启');
      }
      return false;
    }

    return status.isGranted || status == PermissionStatus.limited;
  }

  Future<void> _initBaiduLocation() async {
    _locationPlugin.singleLocationCallback(callback: (BaiduLocation result) {
      if (!_isActive) return;

      // locType 仅 Android 返回，iOS 恒为 null；iOS 用经纬度判定
      final hasFix = result.latitude != null && result.longitude != null &&
          (result.locType == null || result.locType! > 0);

      if (hasFix) {
        _handleLocationUpdate(
          BMFCoordinate(result.latitude!, result.longitude!),
          result
        );
      } else {
        if (!_isActive) return;
        setState(() {
          _locationInfo =
          '定位失败(code=${result.errorCode}, info=${result.errorInfo})，请重试';
          _isLocating = false;
          _isManualRelocate = false;
        });
      }
    });

    await _prepareLocation();
  }

  Future<void> _prepareLocation() async {
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
        distanceFilter: 3.0
      );

      await _locationPlugin.prepareLoc(
        androidOptions.getMap(),
        iosOptions.getMap()
      );
    } catch (e) {
      logger.e('配置定位参数失败：$e');
    }
  }

  Future<void> _handleLocationUpdate(BMFCoordinate coordinate, BaiduLocation location) async {
    if (!_isActive || _hasReceivedFirstFix) return;
    _hasReceivedFirstFix = true;

    _locationTimeoutTimer?.cancel();

    final shouldMoveMap = !_hasMovedToLocation || _isManualRelocate;

    setState(() {
      _currentPosition = coordinate;
      _isLocating = false;
      _isManualRelocate = false;
    });

    try {
      await _updateMarkerToPosition(
        coordinate,
        triggerCallback: true,
        knownAddress: location.address
      );
    } catch (e) {
      logger.e('更新 marker 失败：$e');
      return;
    }

    if (!_isActive) return;

    if (shouldMoveMap) {
      _moveMapTo(coordinate, durationMs: _mapMoveDurationMs);
      _hasMovedToLocation = true;
    }
  }

  Future<void> _getCurrentLocation({bool manual = true}) async {
    if (!_isActive || _isLocating) return;

    setState(() {
      _isLocating = true;
      _hasReceivedFirstFix = false;
      _isManualRelocate = manual;
      _locationInfo = '正在定位...';
    });

    // 可取消的超时定时器，避免旧请求误报超时
    _locationTimeoutTimer?.cancel();
    _locationTimeoutTimer = Timer(Duration(seconds: 15), () {
      if (!_isActive || !_isLocating) return;
      setState(() {
        _isLocating = false;
        _isManualRelocate = false;
        _locationInfo = '定位超时，请重试';
      });
    });

    try {
      await _locationPlugin.stopLocation();
      if (!_isActive) return;

      await _locationPlugin.singleLocation({
        'isReGeocode': true,
        'isNetworkState': true
      });
    } catch (e) {
      logger.e('定位失败：$e');
      if (!_isActive) return;
      _locationTimeoutTimer?.cancel();
      setState(() {
        _locationInfo = '定位失败：$e';
        _isLocating = false;
        _isManualRelocate = false;
      });
    }
  }

  Future<String> _updateMarkerToPosition(BMFCoordinate position, {bool triggerCallback = false, String? knownAddress}) async {
    final controller = _mapController;
    if (!_isActive || controller == null) return '';

    await controller.cleanAllMarkers();
    if (!_isActive) return '';

    final marker = BMFMarker.icon(
      position: position,
      icon: 'images/location_on_120dp.png',
      title: '当前位置',
      enabled: false, // 忽略触摸
    );
    await controller.addMarker(marker);
    if (!_isActive) return '';

    final address = (knownAddress != null && knownAddress.isNotEmpty) ?
    knownAddress : await _geocodeService.reverseGeocode(latitude: position.latitude, longitude: position.longitude);
    if (!_isActive) return address;

    setState(() {
      _markerPosition = position;
      _locationInfo =
      '地址：$address\n纬度：${position.latitude.toStringAsFixed(6)}, 经度：${position.longitude.toStringAsFixed(6)}';
    });

    if (triggerCallback) _triggerCallback(position, address);
    return address;
  }

  void _triggerCallback(BMFCoordinate coordinate, String address) {
    final point = MapPoint(coordinate.latitude, coordinate.longitude);
    if (widget.onLocationSelectedWithAddress != null) {
      widget.onLocationSelectedWithAddress!(point, address);
    } else if (widget.onLocationSelected != null) {
      widget.onLocationSelected!(point);
    }
  }

  void _moveMapTo(
      BMFCoordinate coordinate, {
        int durationMs = _mapMoveDurationMs,
      }) {
    final controller = _mapController;
    if (!_isActive || controller == null) return;
    controller.setCenterCoordinate(coordinate, true, animateDurationMs: durationMs);
    controller.setZoomTo(_defaultZoomLevel.toDouble(), animateDurationMs: durationMs);
  }

  void _moveToMarkerPosition() {
    final marker = _markerPosition;
    if (!_isActive || marker == null) return;
    _moveMapTo(marker);
  }

  Future<void> _onMapTap(BMFCoordinate coordinate) async {
    if (!_isActive) return;
    await _updateMarkerToPosition(coordinate, triggerCallback: true);
    if (!_isActive) return;
    _moveMapTo(coordinate, durationMs: _mapTapMoveDurationMs);
  }

  void _onMapCreated(BMFMapController controller) {
    if (!_isActive) return;
    _mapController = controller;

    final initialPosition = _currentPosition;
    if (initialPosition != null) {
      _updateMarkerToPosition(initialPosition, triggerCallback: true)
          .then((_) {
        if (!_isActive) return;
        if (!_hasMovedToLocation) {
          _moveMapTo(initialPosition);
          _hasMovedToLocation = true;
        }
      });
    }

    controller.setMapOnClickedMapBlankCallback(
      callback: (coordinate) => _onMapTap(coordinate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : BMFMapWidget(
            onBMFMapCreated: _onMapCreated,
            mapOptions: BMFMapOptions(
              center: _currentPosition ?? BMFCoordinate(0.0, 0.0),
              zoomLevel: _defaultZoomLevel,
              mapType: BMFMapType.Standard
            ),
          ),
        ),
        if (widget.showCurrentLocationInfo)
          _LocationInfoPanel(
            locationInfo: _locationInfo,
            isLocating: _isLocating,
            showCenterButton: widget.showLocationButton,
            onRelocate: () => _getCurrentLocation(manual: true),
            onCenter: _moveToMarkerPosition,
          ),
      ],
    );
  }
}

class _LocationInfoPanel extends StatelessWidget {
  final String locationInfo;
  final bool isLocating;
  final bool showCenterButton;
  final VoidCallback onRelocate;
  final VoidCallback onCenter;

  const _LocationInfoPanel({
    required this.locationInfo,
    required this.isLocating,
    required this.showCenterButton,
    required this.onRelocate,
    required this.onCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(locationInfo, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isLocating ? null : onRelocate,
                icon: isLocating
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white
                  ),
                )
                    : const Icon(Icons.my_location, size: 18),
                label: Text(isLocating ? '定位中...' : '重新定位'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white
                ),
              ),
              const SizedBox(width: 12)                                      ,
              if (showCenterButton)
                ElevatedButton.icon(
                  onPressed: onCenter,
                  icon: const Icon(Icons.center_focus_strong, size: 18),
                  label: const Text('回到中心'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeocodeService {
  static const _unknownAddress = '未知位置';

  Future<String> reverseGeocode({required double latitude, required double longitude}) async {
    final coordinate = BMFCoordinate(latitude, longitude);
    final baiduAddress = await _baiduReverseGeocode(coordinate);
    if (baiduAddress != null && baiduAddress.isNotEmpty) {
      return baiduAddress;
    }

    final tencentAddress =
    await TencentMapApi().reverseGeocode(latitude, longitude);
    if (tencentAddress == null || tencentAddress.isEmpty) {
      return _unknownAddress;
    }
    return tencentAddress;
  }

  Future<String?> _baiduReverseGeocode(BMFCoordinate coordinate) async {
    try {
      final option = BMFReverseGeoCodeSearchOption(location: coordinate);
      final search = BMFReverseGeoCodeSearch();
      final completer = Completer<String?>();

      search.onGetReverseGeoCodeSearchResult(
        callback: (result, errorCode) {
          // resultJson: {"acode":0,"cityCode":0,"poiList":[],"poiRegions":[]}
          if (completer.isCompleted) return;
          var address = result.address ?? '';
          if (address.isEmpty && result.poiList!.isNotEmpty) {
            address = result.poiList!.first.name ?? '';
          }
          completer.complete(address.isEmpty ? null : address);
        },
      );

      await search.reverseGeoCodeSearch(option);

      return await completer.future.timeout(
        Duration(seconds: 3),
        onTimeout: () => null
      );
    } catch (e) {
      logger.e('百度逆地理编码失败：$e');
      return null;
    }
  }
}