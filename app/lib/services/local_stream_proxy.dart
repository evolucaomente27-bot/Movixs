import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Servidor Proxy Local HTTP dinâmico para contornar restrições de CORS
/// e injetar cabeçalhos de proteção anti-hotlink (Referer, Origin, Cookie, User-Agent)
/// exigidos por CDNs de vídeo em players nativos (ExoPlayer, AVPlayer, MediaKit).
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

  /// Inicia o servidor proxy local na porta dinâmica 0
  Future<Uri> startProxy({
    required Uri targetUri,
    Map<String, String> forwardHeaders = const {},
  }) async {
    await stop();

    _targetUri = targetUri;
    _forwardHeaders = Map<String, String>.from(forwardHeaders);

    // Garantir cabeçalhos padrão anti-hotlink se não foram fornecidos
    if (!_containsKeyIgnoreCase(_forwardHeaders, 'User-Agent')) {
      _forwardHeaders['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
    }

    _client = _createHttpClient();

    // 1. Iniciar HttpServer local dinâmico (porta 0 para alocação automática pelo SO)
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      // Fallback para loopback caso anyIPv4 falhe em certas permissões
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    _server = server;

    final targetStr = targetUri.toString().toLowerCase();
    final String extension;
    if (targetStr.contains('.m3u8')) {
      extension = '.m3u8';
    } else if (targetStr.contains('.mpd')) {
      extension = '.mpd';
    } else {
      extension = '.mp4';
    }

    _localUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/stream$extension',
    );

    _subscription = server.listen(
      _handleIncomingRequest,
      onError: (error, stackTrace) {
        debugPrint('[LocalStreamProxy] ⚠️ Erro no socket do servidor: $error');
      },
    );

    debugPrint('[LocalStreamProxy] 🚀 Proxy iniciado com sucesso: $_localUri -> $_targetUri');
    return _localUri!;
  }

  /// Alias conveniente para inicialização
  Future<Uri> start(Uri targetUri, [Map<String, String> headers = const {}]) {
    return startProxy(targetUri: targetUri, forwardHeaders: headers);
  }

  /// 3. Ciclo de Vida: Encerra o proxy liberando conexões, portas e sockets
  Future<void> stop() async {
    if (_server == null && _subscription == null && _client == null) {
      return;
    }
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
    debugPrint('[LocalStreamProxy] 🛑 Proxy finalizado e recursos liberados.');
  }

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.autoUncompress = false;
    client.connectionTimeout = const Duration(seconds: 15);
    // Permite certificados auto-assinados de servidores de streaming piratas/CDN
    client.badCertificateCallback = (cert, host, port) => true;

    final userAgent = _getHeaderValueIgnoreCase(_forwardHeaders, 'User-Agent');
    if (userAgent != null && userAgent.isNotEmpty) {
      client.userAgent = userAgent;
    }

    return client;
  }

  /// Trata a requisição recebida do player nativo
  Future<void> _handleIncomingRequest(HttpRequest request) async {
    // Tratamento de CORS Preflight (OPTIONS)
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

    // Identifica o destino upstream (suporte a /stream?url=...)
    Uri effectiveTargetUri = _targetUri!;
    final queryUrl = request.uri.queryParameters['url'];
    if (queryUrl != null && queryUrl.isNotEmpty) {
      try {
        effectiveTargetUri = Uri.parse(queryUrl);
      } catch (_) {
        effectiveTargetUri = _targetUri!.resolve(queryUrl);
      }
    } else if (request.uri.path != '/stream.m3u8' &&
        request.uri.path != '/stream.mp4' &&
        request.uri.path != '/stream.mpd') {
      // Caminho relativo a partir do destino principal
      effectiveTargetUri = _targetUri!.resolve(request.uri.path);
    }

    final client = _client ?? _createHttpClient();
    _client = client;

    int redirectCount = 0;
    const maxRedirects = 6;
    HttpClientResponse? upstreamResponse;
    Uri currentUri = effectiveTargetUri;

    // Resolução de redirects mantendo headers e cookies
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

      // 2. Injetar cabeçalhos de proteção exigidos pelo servidor de origem
      _forwardHeaders.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'host' || lower == 'connection' || lower == 'content-length') {
          return;
        }
        upstreamRequest.headers.set(key, value);
      });

      // 2. Repassar o cabeçalho Range: bytes=X-Y para permitir seek no player nativo
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
            currentUri = currentUri.resolve(location);
            await response.drain();
            redirectCount++;
            continue;
          }
        }

        upstreamResponse = response;
        break;
      } catch (error) {
        debugPrint('[LocalStreamProxy] ⚠️ Falha na conexão com upstream: $error');
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

    // 2. Repassar código de status (200 OK ou 206 Partial Content para seek)
    request.response.statusCode = upstreamResponse.statusCode;
    _addCorsHeaders(request.response);

    // 2. Retransmitir headers essenciais (Content-Type, Content-Range, Content-Length, Accept-Ranges)
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

    // Se o upstream não enviou explicitamente Accept-Ranges, garantimos bytes para o ExoPlayer
    if (request.response.headers.value(HttpHeaders.acceptRangesHeader) == null) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }

    final contentType = upstreamResponse.headers.contentType?.mimeType ?? '';
    final isPlaylist = contentType.contains('mpegurl') ||
        request.uri.path.endsWith('.m3u8') ||
        currentUri.path.endsWith('.m3u8');

    // Reescrita de HLS .m3u8 para que segmentos passem pelo proxy recebendo headers
    if (isPlaylist && request.method != 'HEAD') {
      try {
        final rawBytes = await upstreamResponse.fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );
        final bodyText = utf8.decode(rawBytes, allowMalformed: true);
        final rewrittenManifest = _rewriteM3u8Manifest(bodyText, currentUri);
        final rewrittenBytes = utf8.encode(rewrittenManifest);

        request.response.headers.contentLength = rewrittenBytes.length;
        request.response.add(rewrittenBytes);
        await request.response.close();
        return;
      } catch (e) {
        debugPrint('[LocalStreamProxy] ⚠️ Erro ao processar playlist HLS: $e');
      }
    }

    // Retransmissão contínua em tempo real (pipe)
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
    response.headers.set(
      'Access-Control-Expose-Headers',
      'Content-Range, Content-Length, Accept-Ranges, Content-Type',
    );
  }

  /// Reescreve linhas de URI no arquivo .m3u8 para que fragmentos .ts e chaves passem pelo proxy
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
        // Trata tags de chave #EXT-X-KEY:METHOD=...,URI="..."
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

  bool _containsKeyIgnoreCase(Map<String, String> map, String key) {
    final lowerKey = key.toLowerCase();
    return map.keys.any((k) => k.toLowerCase() == lowerKey);
  }

  String? _getHeaderValueIgnoreCase(Map<String, String> map, String key) {
    final lowerKey = key.toLowerCase();
    for (final entry in map.entries) {
      if (entry.key.toLowerCase() == lowerKey) {
        return entry.value;
      }
    }
    return null;
  }
}
