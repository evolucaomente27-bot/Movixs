import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalVideoProxy {
  static final LocalVideoProxy instance = LocalVideoProxy();

  HttpServer? _server;
  HttpClient? _client;
  StreamSubscription<HttpRequest>? _subscription;
  Uri? _localUri;
  Uri? _targetUri;
  Map<String, String> _forwardHeaders = {};

  bool get isRunning => _server != null;
  Uri? get localUri => _localUri;

  Future<Uri> startProxy({
    required Uri targetUri,
    required Map<String, String> forwardHeaders,
  }) async {
    await stop();

    _targetUri = targetUri;
    _forwardHeaders = Map<String, String>.from(forwardHeaders);

    _client = _createHttpClient();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    String pathExtension = '.mp4';
    final targetStr = targetUri.toString().toLowerCase();
    if (targetStr.contains('.m3u8')) {
      pathExtension = '.m3u8';
    }

    _localUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/stream$pathExtension',
    );

    _subscription = server.listen(
      _handleRequest,
      onError: (error, stackTrace) {
        debugPrint('LocalVideoProxy error: $error');
      },
    );

    debugPrint('LocalVideoProxy started at $_localUri for $_targetUri');
    return _localUri!;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    await _server?.close(force: true);
    _server = null;

    _client?.close(force: true);
    _client = null;

    _localUri = null;
    _targetUri = null;
    _forwardHeaders.clear();
  }

  HttpClient _createHttpClient() {
    final client = HttpClient();
    String? userAgent;
    for (final entry in _forwardHeaders.entries) {
      if (entry.key.toLowerCase() == 'user-agent') {
        userAgent = entry.value;
        break;
      }
    }
    if (userAgent != null && userAgent.isNotEmpty) {
      client.userAgent = userAgent;
    }
    client.autoUncompress = false;
    client.connectionTimeout = const Duration(seconds: 12);
    return client;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_targetUri == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final client = _client ?? _createHttpClient();
    _client = client;

    Uri currentTargetUri = _targetUri!;
    HttpClientResponse? finalResponse;
    int redirectCount = 0;
    const maxRedirects = 5;

    while (redirectCount < maxRedirects) {
      HttpClientRequest upstreamRequest;
      try {
        upstreamRequest = await client.openUrl(request.method, currentTargetUri);
        upstreamRequest.followRedirects = false;
      } catch (error) {
        debugPrint('LocalVideoProxy upstream open error: $error');
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      _forwardHeaders.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'connection' || lower == 'host' || lower == 'content-length' || lower == 'accept-encoding') {
          return;
        }
        upstreamRequest.headers.set(key, value);
      });

      final forwardedHeaders = <String>[
        HttpHeaders.rangeHeader,
        HttpHeaders.acceptHeader,
        HttpHeaders.acceptLanguageHeader,
      ];

      for (final headerName in forwardedHeaders) {
        final value = request.headers.value(headerName);
        if (value != null && value.isNotEmpty) {
          upstreamRequest.headers.set(headerName, value);
        }
      }

      if (upstreamRequest.headers.value(HttpHeaders.acceptEncodingHeader) == null) {
        final encoding = _forwardHeaders[HttpHeaders.acceptEncodingHeader] ?? 'identity';
        upstreamRequest.headers.set(HttpHeaders.acceptEncodingHeader, encoding);
      }

      HttpClientResponse upstreamResponse;
      try {
        upstreamResponse = await upstreamRequest.close();
      } catch (error) {
        debugPrint('LocalVideoProxy upstream request error: $error');
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      final isRedirect = upstreamResponse.statusCode == HttpStatus.movedPermanently ||
          upstreamResponse.statusCode == HttpStatus.found ||
          upstreamResponse.statusCode == HttpStatus.seeOther ||
          upstreamResponse.statusCode == HttpStatus.temporaryRedirect ||
          upstreamResponse.statusCode == HttpStatus.permanentRedirect;

      if (isRedirect) {
        final location = upstreamResponse.headers.value(HttpHeaders.locationHeader);
        if (location != null && location.isNotEmpty) {
          final redirectUri = currentTargetUri.resolve(location);
          await upstreamResponse.drain();
          currentTargetUri = redirectUri;
          redirectCount++;
          continue;
        }
      }

      finalResponse = upstreamResponse;
      break;
    }

    if (finalResponse == null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    request.response.statusCode = finalResponse.statusCode;

    finalResponse.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'connection' || lower == 'transfer-encoding') return;
      for (final value in values) {
        request.response.headers.add(name, value);
      }
    });

    try {
      if (request.method == 'HEAD') {
        await finalResponse.drain();
        await request.response.close();
      } else {
        await finalResponse.pipe(request.response);
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}
