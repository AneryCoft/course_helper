import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform;
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
    if (!hasPermission) {
      setState(() => _isLoading = false);
      return;
    }
    
    await _initBaiduLocation();
    await _getCurrentLocation();
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 初始化百度定位插件
  Future<void> _initBaiduLocation() async {
    // Android 端设置连续定位回调
    if (Platform.isAndroid) {
      _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
        if (result.locType != null && result.locType! > 0) {
          final coord = BMFCoordinate(result.latitude!, result.longitude!);
          _handleLocationUpdate(coord, result);
        }
      });
    } else if (Platform.isIOS) {
      _locationPlugin.singleLocationCallback(callback: (BaiduLocation result) {
        if (result.locType != null && result.locType! > 0) {
          final coord = BMFCoordinate(result.latitude!, result.longitude!);
          _handleLocationUpdate(coord, result);
        }
      });
    }
    await _prepareHighAccuracyLocation();
  }
  
  /// 配置高精度定位参数
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
        distanceFilter: 3.0
      );
      
      await _locationPlugin.prepareLoc(androidOptions.getMap(), iosOptions.getMap());
    } catch (e) {
      debugPrint('配置定位参数失败：$e');
    }
  }

  /// 处理定位更新
  void _handleLocationUpdate(BMFCoordinate coordinate, BaiduLocation location) {
    setState(() {
      _currentPosition = coordinate;
      _locationInfo = '地址：${location.address ?? ''}\n纬度：${coordinate.latitude.toStringAsFixed(6)}, 经度：${coordinate.longitude.toStringAsFixed(6)}';
    });

    if (_mapController != null) {
      _updateMarkerToPosition(coordinate, triggerCallback: true).then((_) {
        _moveToMarkerPosition();
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _locationInfo = '正在重新定位...';
    });
      
    try {
      // iOS 使用单次定位
      if (Platform.isIOS) {
        await _locationPlugin.singleLocation({'isReGeocode': true, 'isNetworkState': true});
      } else if (Platform.isAndroid) {
        // Android 先停止再启动，避免冲突
        await _locationPlugin.stopLocation();
        await _locationPlugin.startLocation();
      }
    } catch (e) {
      debugPrint('定位失败：$e');
      setState(() {
        _locationInfo = '定位失败：$e';
      });
    }
  }

  Future<bool> _checkPermissions() async {
    var status = await Permission.location.status;
    
    if (status.isDenied) {
      await Permission.location.request();
      status = await Permission.location.status;
    }
    
    if (status.isPermanentlyDenied) {
      setState(() => _locationInfo = '定位权限被永久拒绝');
      return false;
    }
    
    return status.isGranted || PermissionStatus.limited == status;
  }

  Future<String> _updateMarkerToPosition(BMFCoordinate position, {bool triggerCallback = false}) async {
    if (_mapController == null) return '';

    await _mapController!.cleanAllMarkers();

    BMFMarker marker = BMFMarker.icon(
      position: position,
      icon: 'images/placeholder.png',
      title: '当前位置',
      scaleX: 0.3,
      scaleY: 0.3
    );
    await _mapController!.addMarker(marker);

    String address = await _getAddressFromCoordinate(position);

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
    if (_mapController == null || _markerPosition == null) return;
    _mapController!.setCenterCoordinate(_markerPosition!, true, animateDurationMs: 1000);
    _mapController!.setZoomTo(20.0, animateDurationMs: 1000);
  }

  Future<String> _getAddressFromCoordinate(BMFCoordinate coordinate) async {
    try {
      BMFReverseGeoCodeSearchOption option = BMFReverseGeoCodeSearchOption(location: coordinate);
      BMFReverseGeoCodeSearch search = BMFReverseGeoCodeSearch();
      Completer<String> completer = Completer<String>();

      search.onGetReverseGeoCodeSearchResult(callback: (BMFReverseGeoCodeSearchResult? result, BMFSearchErrorCode errorCode) {
        String address = '';
        if (result != null) {
          address = result.address ?? '';
          if (address.isEmpty && result.poiList != null && result.poiList!.isNotEmpty) {
            address = result.poiList!.first.name ?? '';
          }
        }

        if (address.isNotEmpty) {
          completer.complete(address);
        } else {
          completer.complete('未知位置');
        }
      });

      await search.reverseGeoCodeSearch(option);
      return await completer.future;
    } catch (e) {
      return '未知位置';
    }
  }

  void _onMapTap(BMFCoordinate coordinate) async {
    if (_mapController == null) return;

    await _updateMarkerToPosition(coordinate, triggerCallback: true);
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
              _mapController = controller;
              if (_currentPosition != null) {
                _updateMarkerToPosition(_currentPosition!, triggerCallback: true).then((_) {
                  _moveToMarkerPosition();
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
                Text(_locationInfo, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _getCurrentLocation,
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('重新定位'),
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
                          backgroundColor: Theme.of(context).colorScheme.secondary,
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
    _mapController?.cleanAllMarkers();
    super.dispose();
  }
}
