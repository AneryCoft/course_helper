import 'dart:math' as math;

import 'api_service.dart';
import '../utils/logger.dart';

class TencentMapApi {
  /// WebService key
  static const _key = 'ATDBZ-MQSLT-RHPXA-LXJ6U-KRVS3-THFLM';

  /// 逆地理编码
  /// 输入百度 BD09 坐标，返回腾讯解析的地址
  Future<String?> reverseGeocode(double bdLat, double bdLng) async {
    final g = _bd09ToGcj02(bdLat, bdLng);
    final url = 'https://apis.map.qq.com/ws/geocoder/v1/';
    final params = {
      'location': '${g.lat},${g.lng}',
      'key': _key,
      'get_poi': '0'
    };
    final resp = await ApiService.sendRequest(url, params: params, receiveTimeoutSeconds: 5);
    if (resp == null) return null;

    final data = resp.data;
    if (data is Map && data['status'] == 0) {
      final result = data['result'];
      if (result is Map) {
        final address = result['address'] as String?;
        if (address != null && address.isNotEmpty) return address;
        final recommend =
            (result['formatted_addresses'] as Map?)?['recommend'] as String?;
        if (recommend != null && recommend.isNotEmpty) return recommend;
      }
    } else {
      logger.e('腾讯地图逆地理编码失败: '
          'status=${data is Map ? data['status'] : data} '
          'msg=${data is Map ? data['message'] : ''}');
    }
    return null;
  }

  /// BD09（百度）→ GCJ-02（腾讯/高德）坐标转换
  static ({double lat, double lng}) _bd09ToGcj02(double bdLat, double bdLng) {
    const double xPi = 3.14159265358979324 * 3000.0 / 180.0;
    final x = bdLng - 0.0065;
    final y = bdLat - 0.006;
    final z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * xPi);
    final theta = math.atan2(y, x) - 0.000003 * math.cos(x * xPi);
    return (lat: z * math.sin(theta), lng: z * math.cos(theta));
  }
}
