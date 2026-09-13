import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/models/movie_item.dart';
import 'package:app/models/superflix_stream.dart';
import 'package:app/services/superflix_service.dart';
import 'package:app/services/tmdb_service.dart';
import 'package:app/services/local_stream_proxy.dart';

void main() {
  group('1. SuperFlixService URL Builder Tests', () {
    final service = SuperFlixService();

    test('Deve gerar URL correta para filme', () {
      final url = service.buildPlayerUrl(tmdbId: 533535);
      expect(url, equals('https://superflixapi.top/filme/533535'));
    });

    test('Deve gerar URL correta para série com temporada e episódio', () {
      final url = service.buildPlayerUrl(
        tmdbId: 94997,
        season: 2,
        episode: 4,
      );
      expect(url, equals('https://superflixapi.top/serie/94997/2/4'));
    });
  });

  group('2. SuperFlixService Stream Extraction Tests', () {
    test('Deve extrair streams diretos (.m3u8 e .mp4) e separar Dublado/Legendado', () async {
      const mockHtml = '''
        <!DOCTYPE html>
        <html>
        <head><title>SuperFlix Player</title></head>
        <body>
          <div class="audio-tab" data-audio="dublado">
            <video src="https://cdn.superflix.top/hls/533535_dub.m3u8"></video>
            <iframe src="https://embed.superflix.top/player/dublado/1"></iframe>
          </div>
          <div class="audio-tab" data-audio="legendado">
            <video src="https://cdn.superflix.top/media/533535_leg.mp4"></video>
            <iframe src="https://embed.superflix.top/player/legendado/1"></iframe>
          </div>
        </body>
        </html>
      ''';

      final mockClient = MockClient((request) async {
        return http.Response(mockHtml, 200, headers: {
          'content-type': 'text/html; charset=utf-8',
        });
      });

      final service = SuperFlixService(client: mockClient);
      final streams = await service.extractStreamSources('https://superflixapi.top/filme/533535');

      expect(streams, isNotEmpty);

      // Verifica presença de Dublado e Legendado
      final dublados = streams.where((s) => s.audioType == 'Dublado').toList();
      final legendados = streams.where((s) => s.audioType == 'Legendado').toList();

      expect(dublados, isNotEmpty);
      expect(legendados, isNotEmpty);

      // Verifica stream direto .m3u8 extraído
      expect(
        dublados.any((s) => s.isDirectStream && s.url.contains('.m3u8')),
        isTrue,
      );

      // Verifica stream direto .mp4 extraído
      expect(
        legendados.any((s) => s.isDirectStream && s.url.contains('.mp4')),
        isTrue,
      );
    });

    test('Deve fornecer fallbacks seguros de Dublado e Legendado se o HTML for protegido', () async {
      final mockClient = MockClient((request) async {
        return http.Response('<html><body>Protected JS Challenge</body></html>', 403);
      });

      final service = SuperFlixService(client: mockClient);
      final streams = await service.extractStreamSources('https://superflixapi.top/filme/123');

      expect(streams.length, greaterThanOrEqualTo(2));
      expect(streams.any((s) => s.audioType == 'Dublado'), isTrue);
      expect(streams.any((s) => s.audioType == 'Legendado'), isTrue);
    });
  });

  group('3. LocalStreamProxy Lifecycle & Seeking Tests', () {
    late HttpServer mockCdnServer;
    late int mockCdnPort;

    setUp(() async {
      // Inicia um servidor CDN mock local simulando a CDN da SuperFlix
      mockCdnServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockCdnPort = mockCdnServer.port;

      mockCdnServer.listen((request) async {
        // Valida cabeçalho anti-hotlink repassado
        final referer = request.headers.value('referer');
        if (referer == null || !referer.contains('superflixapi.top')) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write('Anti-Hotlink: Referer blocked');
          await request.response.close();
          return;
        }

        // Simula resposta de Range (Seeking)
        final rangeHeader = request.headers.value('range');
        if (rangeHeader != null && rangeHeader.startsWith('bytes=100-')) {
          const chunkData = 'CHUNK_PARTIAL_BYTES';
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 100-118/200');
          request.response.headers.set('Content-Length', '${chunkData.length}');
          request.response.write(chunkData);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('Content-Type', 'video/mp4');
        request.response.write('FULL_VIDEO_STREAM');
        await request.response.close();
      });
    });

    tearDown(() async {
      await mockCdnServer.close(force: true);
      await LocalStreamProxy.instance.stop();
    });

    test('Proxy deve iniciar, repassar Referer anti-hotlink e Range para seek', () async {
      final proxy = LocalStreamProxy.instance;
      final targetUri = Uri.parse('http://127.0.0.1:$mockCdnPort/video.mp4');

      final localUri = await proxy.startProxy(
        targetUri: targetUri,
        forwardHeaders: {
          'Referer': 'https://superflixapi.top/',
          'Origin': 'https://superflixapi.top',
        },
      );

      expect(proxy.isRunning, isTrue);
      expect(localUri.port, isPositive);
      expect(localUri.path, equals('/stream.mp4'));

      // 1. Testa requisição padrão via proxy
      final client = HttpClient();
      final req1 = await client.getUrl(localUri);
      final res1 = await req1.close();
      final body1 = await utf8.decodeStream(res1);

      expect(res1.statusCode, equals(HttpStatus.ok));
      expect(body1, equals('FULL_VIDEO_STREAM'));

      // 2. Testa requisição com Range (Seek)
      final req2 = await client.getUrl(localUri);
      req2.headers.set(HttpHeaders.rangeHeader, 'bytes=100-');
      final res2 = await req2.close();
      final body2 = await utf8.decodeStream(res2);

      expect(res2.statusCode, equals(HttpStatus.partialContent));
      expect(body2, equals('CHUNK_PARTIAL_BYTES'));
      expect(res2.headers.value('Content-Range'), equals('bytes 100-118/200'));

      client.close();

      // 3. Testa parada limpa sem travar portas
      await proxy.stop();
      expect(proxy.isRunning, isFalse);
    });
  });

  group('4. TMDBService & Models Tests', () {
    test('MovieItem.fromTmdb deve mapear corretamente filmes e séries em PT-BR', () {
      final movieJson = {
        'id': 533535,
        'title': 'Deadpool & Wolverine',
        'overview': 'Aventura pelo multiverso',
        'poster_path': '/poster.jpg',
        'backdrop_path': '/backdrop.jpg',
        'vote_average': 8.7,
        'release_date': '2024-07-25',
        'genre_ids': [28, 35],
      };

      final movie = MovieItem.fromTmdb(movieJson);
      expect(movie.id, equals(533535));
      expect(movie.title, equals('Deadpool & Wolverine'));
      expect(movie.isSeries, isFalse);
      expect(movie.releaseYear, equals('2024'));
      expect(movie.genres, contains('Ação'));

      final seriesJson = {
        'id': 94997,
        'name': 'A Casa do Dragão',
        'overview': 'Guerra civil Targaryen',
        'poster_path': '/series.jpg',
        'vote_average': 8.4,
        'first_air_date': '2022-08-21',
        'number_of_seasons': 2,
      };

      final series = MovieItem.fromTmdb(seriesJson);
      expect(series.id, equals(94997));
      expect(series.title, equals('A Casa do Dragão'));
      expect(series.isSeries, isTrue);
      expect(series.numberOfSeasons, equals(2));
    });

    test('EpisodeItem.fromJson deve mapear dados de episódio corretamente', () {
      final episodeJson = {
        'id': 101,
        'season_number': 1,
        'episode_number': 3,
        'name': 'O Segundo de Seu Nome',
        'overview': 'Caçada real e tensões políticas',
        'still_path': '/still.jpg',
        'vote_average': 8.2,
      };

      final episode = EpisodeItem.fromJson(episodeJson);
      expect(episode.episodeNumber, equals(3));
      expect(episode.name, equals('O Segundo de Seu Nome'));
      expect(episode.titleLabel, equals('Ep. 3 - O Segundo de Seu Nome'));
      expect(episode.fullStillUrl, contains('/still.jpg'));
    });

    test('SuperFlixStreamResult deve mapear propriedades e helpers de áudio e formato', () {
      final streamDub = SuperFlixStreamResult(
        url: 'https://cdn.superflix.top/hls/stream.m3u8',
        audioType: 'Dublado',
        isDirectStream: true,
      );
      expect(streamDub.isDublado, isTrue);
      expect(streamDub.isLegendado, isFalse);
      expect(streamDub.isHls, isTrue);
      expect(streamDub.isMp4, isFalse);

      final streamLeg = SuperFlixStreamResult(
        url: 'https://cdn.superflix.top/media/stream.mp4',
        audioType: 'Legendado',
        isDirectStream: true,
      );
      expect(streamLeg.isDublado, isFalse);
      expect(streamLeg.isLegendado, isTrue);
      expect(streamLeg.isHls, isFalse);
      expect(streamLeg.isMp4, isTrue);
    });

    test('TMDBService deve retornar listas de tendências em fallback', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{}', 500);
      });
      final tmdb = TMDBService(client: mockClient);
      final movies = await tmdb.getTrendingMovies();
      expect(movies, isNotEmpty);
      expect(movies.first.title, isNotEmpty);

      final series = await tmdb.getTrendingSeries();
      expect(series, isNotEmpty);
      expect(series.first.isSeries, isTrue);
    });
  });
}
