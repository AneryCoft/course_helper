import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:course_helper/api/api_service.dart';
import 'package:course_helper/session/cookie.dart';
import 'package:course_helper/utils/logger.dart' as app_logging;
import 'package:course_helper/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' as logging;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late PathProviderPlatform originalPathProvider;
  late logging.Level originalLogLevel;

  setUpAll(() async {
    originalLogLevel = logging.Logger.level;
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'course_helper_http_log_test_',
    );
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(temporaryDirectory);
    await app_logging.initLogger();
    logging.Logger.level = logging.Level.trace;
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPathProvider;
    logging.Logger.level = originalLogLevel;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await temporaryDirectory.delete(recursive: true);
  });

  test('request bodies stay out of logs and are sent unchanged', () async {
    const password = 'FAKE_PASSWORD_71RUX_MOCK_ONLY';
    const code = 'FAKE_CODE_82ABC_MOCK_ONLY';
    const ticket = 'FAKE_TICKET_93DEF_MOCK_ONLY';
    const rand = 'FAKE_RAND_14GHI_MOCK_ONLY';
    const nestedToken = 'FAKE_NESTED_TOKEN_25JKL_MOCK_ONLY';
    const formPassword = 'FAKE_FORM_PASSWORD_36MNO_MOCK_ONLY';
    const textSecret = 'FAKE_TEXT_SECRET_47PQR_MOCK_ONLY';

    final requestBody = <String, dynamic>{
      'password': password,
      'code': code,
      'ticket': ticket,
      'rand': rand,
      'nested': <String, dynamic>{
        'values': <dynamic>[
          <String, dynamic>{'token': nestedToken},
        ],
      },
    };
    final formData = FormData.fromMap(<String, dynamic>{
      'password': formPassword,
      'nested': <String, dynamic>{'code': code},
    });
    const textBody = 'password=$textSecret&ticket=$ticket';
    final adapter = _ScriptedAdapter(<ResponseBody>[
      _jsonResponse(<String, dynamic>{'ok': true}),
      _jsonResponse(<String, dynamic>{'ok': true}),
      _jsonResponse(<String, dynamic>{'ok': true}),
    ]);
    final dio = _createDio(adapter);

    final logs = await _captureNewLogs(() async {
      await dio.post<dynamic>(
        'https://example.invalid/api/json',
        data: requestBody,
      );
      await dio.post<dynamic>(
        'https://example.invalid/api/form',
        data: formData,
      );
      await dio.post<dynamic>(
        'https://example.invalid/api/text',
        data: textBody,
        options: Options(contentType: Headers.textPlainContentType),
      );
    });

    expect(jsonDecode(adapter.requestBodies[0]!), equals(requestBody));
    expect(adapter.requestBodies[1], contains(formPassword));
    expect(adapter.requestBodies[1], contains(code));
    expect(adapter.requestBodies[2], textBody);
    for (final marker in <String>[
      password,
      code,
      ticket,
      rand,
      nestedToken,
      formPassword,
      textSecret,
    ]) {
      expect(logs, isNot(contains(marker)));
    }
    expect(logs, contains('POST'));
    expect(logs, isNot(contains('Body:')));
  });

  test(
    'URI logs keep method, host, and path but remove userinfo, query, and fragment',
    () async {
      const userInfo = 'FAKE_USERINFO_USER_58STU_MOCK_ONLY';
      const userInfoPassword = 'FAKE_USERINFO_PASSWORD_69VWX_MOCK_ONLY';
      const sessionId = 'FAKE_SESSIONID_70YZA_MOCK_ONLY';
      const token = 'FAKE_TOKEN_81BCD_MOCK_ONLY';
      const privateToken = 'FAKE_PRIVATE_TOKEN_92EFG_MOCK_ONLY';
      const fragment = 'FAKE_FRAGMENT_13HIJ_MOCK_ONLY';
      final adapter = _ScriptedAdapter(<ResponseBody>[
        _jsonResponse(<String, dynamic>{'ok': true}),
      ]);
      final dio = _createDio(adapter);

      final logs = await _captureNewLogs(() async {
        await dio.get<dynamic>(
          'https://$userInfo:$userInfoPassword@example.invalid/api/session'
          '?sessionid=$sessionId&token=$token&_token=$privateToken&view=lesson'
          '#$fragment',
        );
      });

      expect(logs, contains('GET'));
      expect(logs, contains('example.invalid/api/session'));
      expect(logs, contains('200'));
      expect(logs, isNot(contains('?')));
      expect(logs, isNot(contains('#')));
      for (final marker in <String>[
        userInfo,
        userInfoPassword,
        sessionId,
        token,
        privateToken,
        fragment,
      ]) {
        expect(logs, isNot(contains(marker)));
      }
    },
  );

  test('successful and error response bodies stay out of logs', () async {
    const successPassword = 'FAKE_SUCCESS_PASSWORD_24KLM_MOCK_ONLY';
    const successToken = 'FAKE_SUCCESS_TOKEN_35NOP_MOCK_ONLY';
    const errorCode = 'FAKE_ERROR_CODE_46QRS_MOCK_ONLY';
    const errorTicket = 'FAKE_ERROR_TICKET_57TUV_MOCK_ONLY';
    const errorQuery = 'FAKE_ERROR_QUERY_68WXY_MOCK_ONLY';

    final successAdapter = _ScriptedAdapter(<ResponseBody>[
      _jsonResponse(<String, dynamic>{
        'password': successPassword,
        'token': successToken,
      }),
    ]);
    final successDio = _createDio(successAdapter);
    late Response<dynamic> successResponse;
    final successLogs = await _captureNewLogs(() async {
      successResponse = await successDio.get<dynamic>(
        'https://example.invalid/api/success',
      );
    });

    expect(successResponse.data['password'], successPassword);
    expect(successResponse.data['token'], successToken);
    expect(successLogs, contains('200'));
    expect(successLogs, isNot(contains(successPassword)));
    expect(successLogs, isNot(contains(successToken)));

    final errorAdapter = _ScriptedAdapter(<ResponseBody>[
      _jsonResponse(<String, dynamic>{
        'code': errorCode,
        'ticket': errorTicket,
      }, statusCode: HttpStatus.unauthorized),
    ]);
    final errorDio = _createDio(errorAdapter);
    late DioException responseError;
    final errorLogs = await _captureNewLogs(() async {
      try {
        await errorDio.get<dynamic>(
          'https://example.invalid/api/error?token=$errorQuery',
        );
        fail('Expected an HTTP error response');
      } on DioException catch (error) {
        responseError = error;
      }
    });

    expect(responseError.response?.statusCode, HttpStatus.unauthorized);
    expect(responseError.response?.data['code'], errorCode);
    expect(responseError.response?.data['ticket'], errorTicket);
    expect(errorLogs, contains('401'));
    for (final marker in <String>[errorCode, errorTicket, errorQuery]) {
      expect(errorLogs, isNot(contains(marker)));
    }
  });

  test(
    'Dio error message, request options, error, and stack are not logged',
    () async {
      const userInfo = 'FAKE_EXCEPTION_USERINFO_79ZAB_MOCK_ONLY';
      const queryToken = 'FAKE_EXCEPTION_QUERY_TOKEN_80CDE_MOCK_ONLY';
      const bodyPassword = 'FAKE_EXCEPTION_BODY_PASSWORD_91FGH_MOCK_ONLY';
      const message = 'FAKE_EXCEPTION_MESSAGE_12IJK_MOCK_ONLY';
      const errorValue = 'FAKE_EXCEPTION_ERROR_23LMN_MOCK_ONLY';
      const stackValue = 'FAKE_EXCEPTION_STACK_34OPQ_MOCK_ONLY';
      final dio = Dio()..interceptors.add(DioLoggerInterceptor());
      dio.httpClientAdapter = _ThrowingAdapter(message, errorValue, stackValue);
      late DioException caught;

      final logs = await _captureNewLogs(() async {
        try {
          await dio.post<dynamic>(
            'https://$userInfo:secret@example.invalid/api/fail'
            '?_token=$queryToken#FAKE_EXCEPTION_FRAGMENT_MOCK_ONLY',
            data: <String, dynamic>{'password': bodyPassword},
          );
          fail('Expected the scripted DioException');
        } on DioException catch (error) {
          caught = error;
        }
      });

      expect(caught.message, message);
      expect(caught.error, errorValue);
      expect(caught.stackTrace.toString(), contains(stackValue));
      expect(
        (caught.requestOptions.data as Map<String, dynamic>)['password'],
        bodyPassword,
      );
      for (final marker in <String>[
        userInfo,
        queryToken,
        bodyPassword,
        message,
        errorValue,
        stackValue,
        'FAKE_EXCEPTION_FRAGMENT_MOCK_ONLY',
      ]) {
        expect(logs, isNot(contains(marker)));
      }
      expect(logs, contains('connectionError'));
      expect(logs, contains('POST'));
      expect(logs, contains('example.invalid/api/fail'));
    },
  );

  test('malformed Set-Cookie values are not logged', () async {
    const malformedHeader =
        'FAKE_SET_COOKIE_SECRET_WITHOUT_EQUALS_45RST_MOCK_ONLY';
    final adapter = _ScriptedAdapter(<ResponseBody>[
      _jsonResponse(
        <String, dynamic>{'ok': true},
        headers: <String, List<String>>{
          'set-cookie': <String>[malformedHeader],
        },
      ),
    ]);
    final dio = _createDio(adapter, includeCookieInterceptor: true);

    final logs = await _captureNewLogs(() async {
      await dio.get<dynamic>('https://example.invalid/api/cookie');
    });

    expect(logs, contains('忽略无法解析的 Set-Cookie 响应头'));
    expect(logs, isNot(contains(malformedHeader)));
  });

  test('ApiService failure logs only a safe URI and error type', () async {
    const queryToken = 'FAKE_SEND_REQUEST_QUERY_TOKEN_56UVW_MOCK_ONLY';
    const parameterSession = 'FAKE_SEND_REQUEST_SESSION_67XYZ_MOCK_ONLY';
    const bodyPassword = 'FAKE_SEND_REQUEST_PASSWORD_78ABC_MOCK_ONLY';
    const adapterError = 'FAKE_HTTP_ADAPTER_ERROR_89DEF_MOCK_ONLY';
    const malformedUriToken = 'FAKE_MALFORMED_URI_TOKEN_90GHI_MOCK_ONLY';

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageManager.initialize();
    final client = _FailingHttpClient(adapterError);

    final logs = await _captureNewLogs(() async {
      await HttpOverrides.runZoned(() async {
        await ApiService.initialize();
        final response = await ApiService.sendRequest(
          'https://example.invalid/api/send?token=$queryToken',
          method: 'POST',
          params: <String, String>{'sessionid': parameterSession},
          body: <String, dynamic>{'password': bodyPassword},
        );
        expect(response, isNull);

        final malformedResponse = await ApiService.sendRequest(
          'https://[malformed.invalid/api/send?token=$malformedUriToken',
        );
        expect(malformedResponse, isNull);
      }, createHttpClient: (_) => client);
    });

    expect(client.requestUris, hasLength(1));
    expect(client.requestUris.single.queryParameters['token'], queryToken);
    expect(
      client.requestUris.single.queryParameters['sessionid'],
      parameterSession,
    );
    expect(logs, contains('HTTP request failed'));
    expect(logs, contains('<invalid-uri>'));
    for (final marker in <String>[
      queryToken,
      parameterSession,
      bodyPassword,
      adapterError,
      malformedUriToken,
    ]) {
      expect(logs, isNot(contains(marker)));
    }
  });
}

Dio _createDio(
  _ScriptedAdapter adapter, {
  bool includeCookieInterceptor = false,
}) {
  final dio = Dio();
  if (includeCookieInterceptor) {
    dio.interceptors.add(CookieInterceptor());
  }
  dio.interceptors.add(DioLoggerInterceptor());
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody _jsonResponse(
  Object? data, {
  int statusCode = HttpStatus.ok,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) => ResponseBody.fromString(
  jsonEncode(data),
  statusCode,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
    ...headers,
  },
);

Future<String> _captureNewLogs(Future<void> Function() action) async {
  final before = app_logging.appLogOutput.content;
  await action();
  final after = app_logging.appLogOutput.content;
  return after.startsWith(before)
      ? after.substring(before.length).trimLeft()
      : after;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<String?> requestBodies = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream == null) {
      requestBodies.add(null);
    } else {
      final builder = await requestStream.fold<BytesBuilder>(
        BytesBuilder(),
        (buffer, chunk) => buffer..add(chunk),
      );
      requestBodies.add(utf8.decode(builder.takeBytes(), allowMalformed: true));
    }
    if (_responses.isEmpty) {
      throw StateError('Unexpected scripted HTTP request');
    }
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.message, this.errorValue, this.stackValue);

  final String message;
  final String errorValue;
  final String stackValue;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: message,
      error: errorValue,
      stackTrace: StackTrace.fromString(stackValue),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailingHttpClient implements HttpClient {
  _FailingHttpClient(this.errorValue);

  final String errorValue;
  final List<Uri> requestUris = <Uri>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requestUris.add(url);
    throw StateError('Scripted HTTP adapter failed: $errorValue');
  }

  @override
  set idleTimeout(Duration value) {}

  @override
  set connectionTimeout(Duration? value) {}

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}
