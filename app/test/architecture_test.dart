import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/models/scraper_models.dart';
import 'package:app/data/services/movie_scraper_service.dart';
import 'package:app/services/local_stream_proxy.dart';

void main() {
  test('Teste 1: Normalização de títulos', () {
    const sampleQuery = '  Vingadores: Guerra Infinita (2018) - Dublado & 1080p!  ';
    final normalized = MovieScraperService.normalizeQuery(sampleQuery);
    expect(normalized, equals('vingadores guerra infinita 2018 dublado 1080p'));

    // Acentos e caracteres complexos
    const complexQuery = 'À Vista d’Águia: Órfãos & Crianças!';
    expect(MovieScraperService.normalizeQuery(complexQuery), equals('a vista d aguia orfaos criancas'));
  });

  test('Teste 2: Modelos tipados ScrapedMovieItem e ScrapedPlayerSource', () {
    final movieItem = ScrapedMovieItem(
      title: 'Deadpool & Wolverine',
      pageUrl: 'https://exemplo.com/filme/deadpool',
      posterUrl: 'https://exemplo.com/poster.jpg',
      audioType: 'Dublado',
      year: '2024',
    );
    expect(movieItem.isDublado, isTrue);
    expect(movieItem.isLegendado, isFalse);

    final playerSource = ScrapedPlayerSource(
      name: 'Servidor VIP',
      playerUrl: 'https://exemplo.com/player/123',
      audioType: 'Dublado',
      serverType: 'Streamtape',
      headers: {'Referer': 'https://exemplo.com'},
    );
    expect(playerSource.serverType, equals('Streamtape'));
    expect(playerSource.isDublado, isTrue);
  });

  test('Teste 3: Servidor LocalStreamProxy (Seeking + CORS + Headers)', () async {
    final proxy = LocalStreamProxy.instance;

    // Servidor Mock Upstream representando CDN de streaming
    final mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mockUpstream.listen((req) {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      req.response.headers.set('Content-Type', 'video/mp4');
      req.response.headers.set('Accept-Ranges', 'bytes');
      if (range != null && range.contains('bytes=0-10')) {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set('Content-Range', 'bytes 0-10/1000');
        req.response.write('01234567890');
      } else {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentLength = 5;
        req.response.write('VIDEO');
      }
      req.response.close();
    });

    final upstreamUri = Uri.parse('http://127.0.0.1:${mockUpstream.port}/video.mp4');

    // Inicia o LocalStreamProxy
    final localProxyUri = await proxy.startProxy(
      targetUri: upstreamUri,
      forwardHeaders: {
        'Referer': 'https://origem-protegida.com/',
        'Origin': 'https://origem-protegida.com',
      },
    );

    expect(proxy.isRunning, isTrue);
    expect(localProxyUri.port, equals(proxy.port));

    // Requisição cliente simulando player nativo com cabeçalho Range (seek)
    final client = HttpClient();
    final testReq = await client.getUrl(localProxyUri);
    testReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-10');
    final testRes = await testReq.close();

    expect(testRes.statusCode, equals(HttpStatus.partialContent));
    expect(testRes.headers.value('access-control-allow-origin'), equals('*'));
    expect(testRes.headers.value('content-range'), equals('bytes 0-10/1000'));

    await testRes.drain();
    client.close();

    // Encerra o proxy e o mock upstream
    await proxy.stop();
    await mockUpstream.close(force: true);
    expect(proxy.isRunning, isFalse);
  });

  test('Teste 4: Extração Profunda de Streams (Regex e direct urls)', () async {
    final scraper = MovieScraperService.instance;

    // Stream direto .m3u8
    final hlsStream = await scraper.extractVideoStream('https://cdn.example.com/playlist.m3u8?token=xyz');
    expect(hlsStream, isNotNull);
    expect(hlsStream!.isHls, isTrue);
    expect(hlsStream.isDirect, isTrue);

    // Stream direto .mp4
    final mp4Stream = await scraper.extractVideoStream('https://cdn.example.com/movie.mp4');
    expect(mp4Stream, isNotNull);
    expect(mp4Stream!.isMp4, isTrue);
    expect(mp4Stream.isDirect, isTrue);
  });
}
