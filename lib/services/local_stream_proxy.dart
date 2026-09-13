import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalStreamProxy {
  static final LocalStreamProxy instance = LocalStreamProxy();

  HttpServer? _server;
  HttpClient? _client;
  StreamSubscription<HttpRequest>? _subscription;
  Uri? _localUri;
  Uri? _targetUri;
  Map<String, String> _forwardHeaders = {};

  bool get isRunning => _server != null;
  Uri? get localUri => _localUri;
  int? get port => _server?.port;

  /// Inicia o servidor proxy local na porta dinâmica para contornar CORS e anti-hotlink
  Future<Uri> startProxy({
    required Uri targetUri,
    Map<String, String> forwardHeaders = const {},
  }) async {
    await stop();

    _targetUri = targetUri;
    _forwardHeaders = Map<String, String>.from(forwardHeaders);

    // Garantir cabeçalhos essenciais da SuperFlix
    if (!_forwardHeaders.containsKey('Referer') && !_forwardHeaders.containsKey('referer')) {
      _forwardHeaders['Referer'] = 'https://superflixapi.top/';
    }
    if (!_forwardHeaders.containsKey('Origin') && !_forwardHeaders.containsKey('origin')) {
      _forwardHeaders['Origin'] = 'https://superflixapi.top';
    }
    if (!_forwardHeaders.containsKey('User-Agent') && !_forwardHeaders.containsKey('user-agent')) {
      _forwardHeaders['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
    }

    _client = _createHttpClient();

    // Bind em loopback na porta 0 (porta dinâmica livre do SO)
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    final targetStr = targetUri.toString().toLowerCase();
    final isHls = targetStr.contains('.m3u8');
    final extension = isHls ? '.m3u8' : '.mp4';

    _localUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/stream$extension',
    );

    _subscription = server.listen(
      _handleIncomingRequest,
      onError: (error, stackTrace) {
        debugPrint('[LocalStreamProxy] ⚠️ Erro no servidor: $error');
      },
    );

    debugPrint('[LocalStreamProxy] 🚀 Servidor proxy iniciado em $_localUri -> $_targetUri');
    return _localUri!;
  }

  /// Finaliza o servidor proxy e libera sockets e memória
  Future<void> stop() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;

    try {
      _client?.close(force: true);
    } catch (_) {}
    _client = null;

    _localUri = null;
    _targetUri = null;
    _forwardHeaders.clear();
    debugPrint('[LocalStreamProxy] 🛑 Servidor proxy finalizado com sucesso.');
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
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }

  Future<void> _handleIncomingRequest(HttpRequest request) async {
    // Tratamento de requisições OPTIONS (CORS Preflight)
    if (request.method == 'OPTIONS') {
      _addCorsHeaders(request.response);
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (_targetUri == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    // Determina a URL de destino da requisição
    Uri effectiveTargetUri = _targetUri!;
    final queryUrl = request.uri.queryParameters['url'];
    if (queryUrl != null && queryUrl.isNotEmpty) {
      effectiveTargetUri = Uri.parse(queryUrl);
    } else if (request.uri.path != '/stream.m3u8' && request.uri.path != '/stream.mp4') {
      // Caminho relativo a partir do destino principal
      effectiveTargetUri = _targetUri!.resolve(request.uri.path);
    }

    final client = _client ?? _createHttpClient();
    _client = client;

    int redirectCount = 0;
    const maxRedirects = 5;
    HttpClientResponse? upstreamResponse;
    Uri currentUri = effectiveTargetUri;

    while (redirectCount < maxRedirects) {
      HttpClientRequest upstreamRequest;
      try {
        upstreamRequest = await client.openUrl(request.method, currentUri);
        upstreamRequest.followRedirects = false;
      } catch (error) {
        debugPrint('[LocalStreamProxy] ⚠️ Erro ao abrir upstream ($currentUri): $error');
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      // Repassar cabeçalhos configurados (Referer, Origin, etc.)
      _forwardHeaders.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'host' || lower == 'connection' || lower == 'content-length') {
          return;
        }
        upstreamRequest.headers.set(key, value);
      });

      // Repassar cabeçalhos de Range e Accept enviados pelo player nativo
      final playerRange = request.headers.value(HttpHeaders.rangeHeader);
      if (playerRange != null && playerRange.isNotEmpty) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, playerRange);
      }

      final playerAccept = request.headers.value(HttpHeaders.acceptHeader);
      if (playerAccept != null && playerAccept.isNotEmpty) {
        upstreamRequest.headers.set(HttpHeaders.acceptHeader, playerAccept);
      }

      try {
        final response = await upstreamRequest.close();
        final isRedirect = response.statusCode == HttpStatus.movedPermanently ||
            response.statusCode == HttpStatus.found ||
            response.statusCode == HttpStatus.seeOther ||
            response.statusCode == HttpStatus.temporaryRedirect ||
            response.statusCode == HttpStatus.permanentRedirect;

        if (isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null && location.isNotEmpty) {
            final redirectUri = currentUri.resolve(location);
            await response.drain();
            currentUri = redirectUri;
            redirectCount++;
            continue;
          }
        }

        upstreamResponse = response;
        break;
      } catch (error) {
        debugPrint('[LocalStreamProxy] ⚠️ Falha na requisição upstream: $error');
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
    }

    if (upstreamResponse == null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    // Configurar código de status (ex: 200 OK ou 206 Partial Content para seeking)
    request.response.statusCode = upstreamResponse.statusCode;
    _addCorsHeaders(request.response);

    // Repassar cabeçalhos da resposta (Content-Type, Content-Length, Content-Range, etc.)
    upstreamResponse.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'connection' ||
          lower == 'transfer-encoding' ||
          lower == 'access-control-allow-origin') {
        return;
      }
      for (final value in values) {
        request.response.headers.add(name, value);
      }
    });

    final contentType = upstreamResponse.headers.contentType?.mimeType ?? '';
    final isPlaylist = contentType.contains('mpegurl') ||
        request.uri.path.endsWith('.m3u8') ||
        currentUri.path.endsWith('.m3u8');

    // Se for manifesto M3U8, reescrever URLs para passar pelo proxy local
    if (isPlaylist && request.method != 'HEAD') {
      try {
        final rawBytes = await upstreamResponse.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        final bodyText = utf8.decode(rawBytes, allowMalformed: true);
        final rewrittenManifest = _rewriteM3u8Manifest(bodyText, currentUri);
        final rewrittenBytes = utf8.encode(rewrittenManifest);

        request.response.headers.contentLength = rewrittenBytes.length;
        request.response.add(rewrittenBytes);
        await request.response.close();
        return;
      } catch (e) {
        debugPrint('[LocalStreamProxy] ⚠️ Erro ao processar manifesto M3U8: $e');
      }
    }

    // Caso contrário, transmitir bytes em tempo real (pipe)
    try {
      if (request.method == 'HEAD') {
        await upstreamResponse.drain();
        await request.response.close();
      } else {
        await upstreamResponse.pipe(request.response);
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', '*');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');
  }

  /// Reescreve linhas de URI no arquivo .m3u8 para que passem pelo servidor proxy local
  String _rewriteM3u8Manifest(String manifest, Uri manifestUri) {
    if (_server == null) return manifest;
    final proxyBase = 'http://127.0.0.1:${_server!.port}/stream';

    final lines = LineSplitter.split(manifest);
    final output = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        output.add(line);
        continue;
      }

      if (trimmed.startsWith('#')) {
        // Trata tags de chave de criptografia #EXT-X-KEY:METHOD=...,URI="..."
        if (trimmed.startsWith('#EXT-X-KEY')) {
          final uriRegex = RegExp(r'URI="([^"]+)"');
          final match = uriRegex.firstMatch(trimmed);
          if (match != null) {
            final rawKeyUri = match.group(1)!;
            final resolvedKey = manifestUri.resolve(rawKeyUri).toString();
            final proxiedKey = '$proxyBase?url=${Uri.encodeComponent(resolvedKey)}';
            output.add(trimmed.replaceFirst('URI="$rawKeyUri"', 'URI="$proxiedKey"'));
            continue;
          }
        }
        output.add(line);
      } else {
        // Linha com caminho de sub-playlist ou fragmento .ts
        final resolvedSegment = manifestUri.resolve(trimmed).toString();
        final proxiedSegment = '$proxyBase?url=${Uri.encodeComponent(resolvedSegment)}';
        output.add(proxiedSegment);
      }
    }

    return output.join('\n');
  }
}
