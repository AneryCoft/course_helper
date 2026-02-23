import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_search/flutter_baidu_mapapi_search.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';


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
  Position? _currentPosition;
  BMFCoordinate? _markerPosition;
  String _locationInfo = '正在获取位置...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    BMFMapSDK.setAgreePrivacy(true);
    _initMap();
  }

  Future<void> _initMap() async {
    await _checkPermissions();
    await _getCurrentLocation();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkPermissions() async {
    if (await Permission.location.status.isDenied) {
      await Permission.location.request();
    }
    if (Theme.of(context).platform == TargetPlatform.android &&
        await Permission.storage.status.isDenied) {
      await Permission.storage.request();
    }
  }

  /// 获取设备当前位置，并更新标记到该位置
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationInfo = '定位服务未开启');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationInfo = '定位权限被拒绝');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationInfo = '定位权限被永久拒绝');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings:
        const LocationSettings(accuracy: LocationAccuracy.high),
      );

      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      setState(() => _locationInfo = '获取位置失败: $e');
    }
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

    // 获取地址
    String address = await _getAddressFromCoordinate(position);

    setState(() {
      _markerPosition = position;
      _locationInfo =
      '地址: $address\n纬度: ${position.latitude.toStringAsFixed(6)}, 经度: ${position.longitude.toStringAsFixed(6)}';
    });

    // 如果需要触发回调，则调用 _triggerCallback
    if (triggerCallback) {
      _triggerCallback(position, address);
    }

    return address;
  }

  /// 触发外部回调
  void _triggerCallback(BMFCoordinate coordinate, String address) {
    if (widget.onLocationSelectedWithAddress != null) {
      widget.onLocationSelectedWithAddress!(coordinate, address);
    } else if (widget.onLocationSelected != null) {
      widget.onLocationSelected!(coordinate);
    }
  }

  /// 移动地图中心到当前标记位置（不改变标记）
  void _moveToMarkerPosition() {
    if (_mapController == null || _markerPosition == null) return;
    _mapController!.setCenterCoordinate(_markerPosition!, true, animateDurationMs: 1000);
    _mapController!.setZoomTo(16.0, animateDurationMs: 1000);
  }

  /// 逆地理编码获取地址（已修复空安全，无结果时返回"未知位置"）
  Future<String> _getAddressFromCoordinate(BMFCoordinate coordinate) async {
    try {
      BMFReverseGeoCodeSearchOption option = BMFReverseGeoCodeSearchOption(
        location: coordinate,
      );

      BMFReverseGeoCodeSearch search = BMFReverseGeoCodeSearch();
      Completer<String> completer = Completer<String>();

      search.onGetReverseGeoCodeSearchResult(callback:
          (BMFReverseGeoCodeSearchResult? result, BMFSearchErrorCode errorCode) {
        String address = '';
        if (result != null) {
          address = result.address ?? '';
          if (address.isEmpty &&
              result.poiList != null &&
              result.poiList!.isNotEmpty) {
            address = result.poiList!.first.name ?? '';
          }
        }

        if (address.isNotEmpty) {
          completer.complete(address);
        } else {
          debugPrint('逆地理编码无有效地址, errorCode: $errorCode');
          completer.complete('未知位置');
        }
      });

      await search.reverseGeoCodeSearch(option);
      return await completer.future;
    } catch (e) {
      debugPrint('获取地址异常: $e');
      return '未知位置';
    }
  }

  /// 处理地图点击：将标记移动到点击位置，并触发回调
  void _onMapTap(BMFCoordinate coordinate) async {
    if (_mapController == null) return;

    // 移动标记到点击位置，并触发回调
    await _updateMarkerToPosition(coordinate, triggerCallback: true);

    // 移动地图中心到点击位置并适当放大
    _mapController!.setCenterCoordinate(coordinate, true, animateDurationMs: 500);
    _mapController!.setZoomTo(18, animateDurationMs: 500);
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
              // 如果有当前位置，初始化标记并触发回调
              if (_currentPosition != null) {
                _updateMarkerToPosition(
                  BMFCoordinate(_currentPosition!.latitude, _currentPosition!.longitude),
                  triggerCallback: true, // 首次触发回调
                );
              }
              // 设置地图点击监听
              _mapController!.setMapOnClickedMapBlankCallback(
                callback: (coordinate) {
                  _onMapTap(coordinate);
                },
              );
            },
            mapOptions: BMFMapOptions(
              center: _currentPosition != null
                  ? BMFCoordinate(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              )
                  : BMFCoordinate(0.0, 0.0),
              zoomLevel: 16,
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
                Text(
                  '位置信息',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _locationInfo, // 显示地址+经纬度
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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