import 'api_service.dart';

class Pick extends Api{
  Pick([super.user]);

  Future<List<dynamic>?> getPickList(String activeId) async {
    final url = 'https://mobilelearn.chaoxing.com/widget/webcache/pick/stu/pickAttend';
    final timeStampMS = DateTime.now().millisecondsSinceEpoch.toString();
    final params = {
      'activeId': activeId,
      'qasort': '0',
      'screenMode': '0',
      'webCacheId': activeId,
      '_': timeStampMS
    };

    final response = await ApiService.sendRequest(url, params: params);
    // {"result":1,"msg":"2","data":{"userListChoose":[{"name":"","userScore":null,"userId":},{"name":"Anery...","userScore":5.0,"userId":}],"count":2,"userListForRand":[],"status":1},"errorMsg":null}
    final data = response?.data;
    if (data['result'] == 0) {
      return [];
    } else if (data['result'] == 1) {
      return data['data']['userListChoose'];
    }
    return null;
  }
}