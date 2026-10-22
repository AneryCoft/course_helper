// Offline regression test for the `_token` query parameter in
// lib/api/image.dart. Run from the course_helper project root:
//   flutter test --no-pub test/security/image_token_logging_test.dart
//
// ApiService.initialize installs the production DioLoggerInterceptor. A
// zone-scoped HttpOverrides returns scripted responses, so the production
// CXImageApi.uploadImage -> ApiService.sendRequest path runs without sockets.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:course_helper/api/api_service.dart';
import 'package:course_helper/api/image.dart';
import 'package:course_helper/models/user.dart';
import 'package:course_helper/utils/logger.dart' as app_logging;
import 'package:course_helper/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' as logging;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'image CRC request keeps the synthetic _token on the request, not in logs',
    () async {
      const fakeToken = 'FAKE_TOKEN_92MNO_MOCK_ONLY';
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await StorageManager.initialize();
      final originalLogLevel = logging.Logger.level;
      logging.Logger.level = logging.Level.trace;
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'course_helper_image_log_',
      );
      final fakeImageFile = File('${temporaryDirectory.path}/fake.jpg');
      await fakeImageFile.writeAsBytes(<int>[0x46, 0x41, 0x4b, 0x45]);
      final originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(temporaryDirectory);
      await app_logging.logger.init;
      addTearDown(() async {
        PathProviderPlatform.instance = originalPathProvider;
        logging.Logger.level = originalLogLevel;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await temporaryDirectory.delete(recursive: true);
      });

      final offlineClient = _ScriptedHttpClient(<String>[
        jsonEncode(<String, dynamic>{'_token': fakeToken}),
        jsonEncode(<String, dynamic>{
          'result': true,
          'exist': true,
          'data': <String, dynamic>{'objectid': 'FAKE_OBJECT_ID'},
        }),
      ]);

      final logs = await _captureNewLogs(() async {
        await HttpOverrides.runZoned(() async {
          // This production initializer registers DioLoggerInterceptor on the
          // same Dio instance subsequently used by CXImageApi.uploadImage.
          await ApiService.initialize();
          final api = CXImageApi(
            User(
              name: 'offline test user',
              avatar: '',
              phone: '',
              uid: 'FAKE_UID_ONLY',
              school: '',
            ),
          );

          final result = await api.uploadImage(fakeImageFile);

          expect(result, 'FAKE_OBJECT_ID');
          expect(offlineClient.requestUris, hasLength(2));
          expect(
            offlineClient.requestUris[1].queryParameters['_token'],
            fakeToken,
          );
        }, createHttpClient: (SecurityContext? context) => offlineClient);
      });

      // The overridden client served both requests in memory. No real server was
      // opened, and the token is synthetic.
      expect(offlineClient.requestUris, hasLength(2));
      expect(logs, contains('api/crcStorageStatus'));
      expect(logs, isNot(contains(fakeToken)));
    },
  );
}

Future<String> _captureNewLogs(Future<void> Function() action) async {
  final before = app_logging.appLogOutput.content;
  await action();
  final after = app_logging.appLogOutput.content;
  return after.startsWith(before)
      ? after.substring(before.length).trimLeft()
      : after;
}

class _ScriptedHttpClient implements HttpClient {
  _ScriptedHttpClient(this._jsonResponses);

  final List<String> _jsonResponses;
  final List<Uri> requestUris = <Uri>[];
  int _nextResponse = 0;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requestUris.add(url);
    if (_nextResponse >= _jsonResponses.length) {
      throw StateError('Unexpected offline request: $method $url');
    }
    return _ScriptedHttpClientRequest(_jsonResponses[_nextResponse++]);
  }

  @override
  set idleTimeout(Duration value) {}

  @override
  set connectionTimeout(Duration? value) {}

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedHttpClientRequest implements HttpClientRequest {
  _ScriptedHttpClientRequest(this._body);

  final String _body;
  final _ScriptedHttpHeaders _headers = _ScriptedHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async =>
      _ScriptedHttpClientResponse(_body);

  @override
  set followRedirects(bool value) {}

  @override
  set maxRedirects(int value) {}

  @override
  set persistentConnection(bool value) {}

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _ScriptedHttpClientResponse(String body)
    : _body = utf8.encode(body),
      _headers = _ScriptedHttpHeaders()
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

  final List<int> _body;
  final _ScriptedHttpHeaders _headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  int get statusCode => HttpStatus.ok;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpHeaders get headers => _headers;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = <String>[value.toString()];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}
