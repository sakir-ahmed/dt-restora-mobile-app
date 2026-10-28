import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code, this.status, this.details});

  final String message;
  final String? code;
  final int? status;
  final Map<String, dynamic>? details;

  bool get isNetwork => code == 'NETWORK';
  bool get isUnauthenticated => status == 401;

  /// Field errors flattened to one line, e.g. for 422 responses.
  String get fullMessage {
    if (details == null || details!.isEmpty) {
      return message;
    }
    final lines = details!.values
        .expand((v) => v is List ? v : [v])
        .map((v) => '$v')
        .toSet()
        .join('\n');
    return lines.isEmpty ? message : lines;
  }

  @override
  String toString() => fullMessage;
}

/// Response envelope: `data` plus optional pagination `meta`.
class ApiResult {
  ApiResult(this.data, this.meta, {this.message});

  final dynamic data;
  final Map<String, dynamic>? meta;
  final String? message;
}

/// Thin client for the DT Restora `/api/v1` API.
///
/// Responses use `{"success": true, "data": ...}`; errors use
/// `{"success": false, "error": {"code", "message", "details"}}`.
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _tokenKey = 'auth_token';
  static const _baseKey = 'api_base_url';

  final http.Client _http;
  String? _token;
  String language = 'en';
  String baseUrl = AppConfig.apiBaseUrl;

  /// Fired when the server rejects the token (401).
  final StreamController<void> _unauthorized = StreamController.broadcast();
  Stream<void> get onUnauthorized => _unauthorized.stream;

  bool get hasToken => _token != null;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    baseUrl = prefs.getString(_baseKey) ?? AppConfig.apiBaseUrl;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseKey, baseUrl);
  }

  Map<String, String> _headers({String? idempotencyKey}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Accept-Language': language,
        'X-App-Version': AppConfig.appVersion,
        'X-Platform': AppConfig.platform,
        if (_token != null) 'Authorization': 'Bearer $_token',
        'Idempotency-Key': ?idempotencyKey,
      };

  Uri _uri(String path, Map<String, dynamic>? query) {
    final q = query?.map((k, v) => MapEntry(k, '$v'));
    return Uri.parse('$baseUrl$path').replace(queryParameters: q?.isEmpty ?? true ? null : q);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      (await send('GET', path, query: query)).data;

  Future<dynamic> post(String path, {Map<String, dynamic>? body, String? idempotencyKey}) async =>
      (await send('POST', path, body: body, idempotencyKey: idempotencyKey)).data;

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async =>
      (await send('PUT', path, body: body)).data;

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async =>
      (await send('PATCH', path, body: body)).data;

  Future<dynamic> delete(String path) async => (await send('DELETE', path)).data;

  /// Downloads a binary response such as a PDF.
  Future<Uint8List> getBytes(String path) async {
    http.Response response;
    try {
      response = await _http
          .get(_uri(path, null), headers: {..._headers(), 'Accept': '*/*'})
          .timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      debugPrint('API GET $path failed: $e');
      throw ApiException('Cannot reach the server.', code: 'NETWORK');
    }
    if (response.statusCode == 401) {
      _unauthorized.add(null);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('The file could not be downloaded (${response.statusCode}).', status: response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<ApiResult> send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(idempotencyKey: idempotencyKey);
    final encoded = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      final future = switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'POST' => _http.post(uri, headers: headers, body: encoded ?? '{}'),
        'PUT' => _http.put(uri, headers: headers, body: encoded ?? '{}'),
        'PATCH' => _http.patch(uri, headers: headers, body: encoded ?? '{}'),
        'DELETE' => _http.delete(uri, headers: headers),
        _ => throw ArgumentError('Unsupported method $method'),
      };
      response = await future.timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      debugPrint('API $method $path failed: $e');
      throw ApiException(
        'Cannot reach the server. Working offline.',
        code: 'NETWORK',
      );
    }
    return _unwrap(response);
  }

  ApiResult _unwrap(http.Response response) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } on FormatException {
      json = null;
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        json != null &&
        json['success'] == true) {
      return ApiResult(
        json['data'],
        json['meta'] as Map<String, dynamic>?,
        message: json['message'] as String?,
      );
    }

    if (response.statusCode == 401) {
      _unauthorized.add(null);
    }

    final error = json?['error'];
    if (error is Map<String, dynamic>) {
      throw ApiException(
        (error['message'] as String?) ?? 'Something went wrong.',
        code: error['code'] as String?,
        status: response.statusCode,
        details: error['details'] as Map<String, dynamic>?,
      );
    }
    throw ApiException(
      (json?['message'] as String?) ?? 'Unexpected server response (${response.statusCode}).',
      status: response.statusCode,
    );
  }
}
