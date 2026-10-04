import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';

/// Dio interceptors shared by every call to the household API, in order:
/// [ApiAuthInterceptor] → [ApiRetryReadsInterceptor] → [ApiLogInterceptor].
const _startedKey = 'apiStarted';
const _attemptKey = 'attempt';
const requestIdHeader = 'x-request-id';

/// Method, path, request id and elapsed time for one call's log line.
/// Never bodies, tokens or query values.
Map<String, Object?> apiCallFields(
  RequestOptions options, [
  Map<String, Object?> extra = const {},
]) {
  final started = options.extra[_startedKey];
  return {
    'method': options.method,
    'path': options.uri.path,
    ...extra,
    if (started is DateTime)
      'ms': DateTime.now().difference(started).inMilliseconds,
    'rid': options.headers[requestIdHeader],
  };
}

/// Adds the household token and a request id. The same id shows in the app
/// log and the Railway request log, and stays the same on retries.
class ApiAuthInterceptor extends Interceptor {
  ApiAuthInterceptor(this._token);

  final String? Function() _token;
  static final _random = Random();

  static String _newRequestId() =>
      List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _token();
    if (token != null) options.headers['authorization'] = 'Bearer $token';
    options.headers.putIfAbsent(requestIdHeader, _newRequestId);
    options.extra.putIfAbsent(_startedKey, DateTime.now);
    handler.next(options);
  }
}

/// Retries reads after a dropped connection or a gateway error. Writes are
/// never retried (the outbox owns those).
class ApiRetryReadsInterceptor extends Interceptor {
  ApiRetryReadsInterceptor(this._dio, this._retries);

  final Dio _dio;
  final int _retries;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 0;
    final status = err.response?.statusCode ?? 0;
    final transient =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        status == 502 ||
        status == 503 ||
        status == 504;
    if (options.method != 'GET' || !transient || attempt >= _retries) {
      return handler.next(err);
    }
    AppLog.event(
      'api.retry',
      apiCallFields(options, {
        'attempt': attempt + 1,
        'status': status,
        'type': err.type.name,
      }),
    );
    await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    options.extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch<Object?>(options));
    } on DioException catch (next) {
      handler.next(next);
    }
  }
}

/// Debug line for each successful call:
/// `[pawsitive.api] api.ok method=POST path=/v1/sync/batch status=200 ms=84 rid=3fa1c2d0`.
/// Failures are logged once as `api.failed` where they are translated into a
/// user message, so a failed call never prints twice.
class ApiLogInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final fields = apiCallFields(response.requestOptions, {
      'status': response.statusCode,
    });
    debugPrint(
      '[pawsitive.api] api.ok '
      '${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
    handler.next(response);
  }
}
