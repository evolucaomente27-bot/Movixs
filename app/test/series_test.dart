import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/data/models/movie.dart';
import 'package:app/data/models/tv_models.dart';
import 'package:app/data/services/movie_scraper_service.dart';
import 'package:app/data/repositories/streaming_repository.dart';

void main() {
  group('1. Modelo e Parsing de Séries de TV', () {
    test('Movie.fromJson reconhece TV shows via first_air_date e name', () {
      final json = {
        'id': 1396,
        'name': 'Breaking Bad',
        'first_air_date': '2008-01-20',
        'overview': 'Um professor de química se torna produtor de metanfetamina.',
        'poster_path': '/30erzlzIOtYJu3LJ4LJ8k4WqmFI.jpg',
        'backdrop_path': '/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg',
        'vote_average': 8.9,
        'number_of_seasons': 5,
        'number_of_episodes': 62,
        'genres': [{'id': 18, 'name': 'Drama'}, {'id': 80, 'name': 'Crime'}],
      };

      final movie = Movie.fromJson(json);

      expect(movie.id, equals(1396));
      expect(movie.title, equals('Breaking Bad'));
      expect(movie.isTvShow, isTrue);
      expect(movie.numberOfSeasons, equals(5));
      expect(movie.numberOfEpisodes, equals(62));
      expect(movie.duration, equals('5 Temporadas'));
      expect(movie.releaseYear, equals('2008'));
    });

    test('TvSeason e TvEpisode realizam parsing com getters formatados', () {
      final seasonJson = {
        'id': 3572,
        'season_number': 1,
        'name': 'Temporada 1',
        'overview': 'Primeira temporada eletrizante.',
        'episode_count': 7,
        'poster_path': '/sUbZ6TUTslNkM1f1PZclYVa60zv.jpg',
      };

      final season = TvSeason.fromJson(seasonJson);
      expect(season.seasonNumber, equals(1));
      expect(season.episodeCount, equals(7));
      expect(season.fullPosterUrl, contains('image.tmdb.org'));

      final episodeJson = {
        'id': 62085,
        'episode_number': 1,
        'season_number': 1,
        'name': 'Piloto',
        'overview': 'Walter White inicia sua jornada.',
        'still_path': '/88Z0fMP8a88EpQWMCs1593G0ngu.jpg',
        'runtime': 58,
        'vote_average': 8.4,
      };

      final episode = TvEpisode.fromJson(episodeJson);
      expect(episode.episodeNumber, equals(1));
      expect(episode.seasonNumber, equals(1));
      expect(episode.name, equals('Piloto'));
      expect(episode.durationFormatted, equals('58m'));
      expect(episode.fullStillUrl, contains('image.tmdb.org'));
    });
  });

  group('2. Resolução de Streams para Séries (VidSrc.to #1)', () {
    test('MovieScraperService gera servidores para Séries com VidSrc.to em primeiro', () async {
      final scraper = MovieScraperService.instance;
      final result = await scraper.resolveSeriesStreams(
        title: 'Breaking Bad',
        tmdbId: 1396,
        season: 1,
        episode: 1,
        imdbId: 'tt0903747',
      );

      expect(result.success, isTrue);
      expect(result.servers, isNotEmpty);

      // VidSrc.to deve ser o Servidor #1
      final firstServer = result.servers.first;
      expect(firstServer.name, contains('VidSrc.to'));
      expect(firstServer.url, equals('https://vidsrc.to/embed/tv/1396/1/1'));

      // Verifica presença de outros servidores de séries
      final serverNames = result.servers.map((s) => s.name).toList();
      expect(serverNames.any((n) => n.contains('VidLink')), isTrue);
      expect(serverNames.any((n) => n.contains('2Embed')), isTrue);
      expect(serverNames.any((n) => n.contains('Rivestream')), isTrue);
      expect(serverNames.any((n) => n.contains('MultiEmbed')), isTrue);
      expect(serverNames.any((n) => n.contains('SmashyStream')), isTrue);

      // Não deve conter fontes descontinuadas
      expect(serverNames.any((n) => n.toLowerCase().contains('superflix')), isFalse);
      expect(serverNames.any((n) => n.toLowerCase().contains('warez')), isFalse);
    });

    test('StreamingRepository.extractSeriesStream executa com sucesso', () async {
      final repo = StreamingRepository();
      final result = await repo.extractSeriesStream(
        title: 'Stranger Things',
        tmdbId: 66732,
        season: 1,
        episode: 1,
        imdbId: 'tt4574334',
      );

      expect(result.success, isTrue);
      expect(result.servers.first.url, equals('https://vidsrc.to/embed/tv/66732/1/1'));
    });

    test('Verificação ao vivo de conectividade do VidSrc.to para séries', () async {
      final res = await http.get(
        Uri.parse('https://vidsrc.to/embed/tv/1396/1/1'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://vidsrc.to/embed/tv/1396/1/1',
        },
      );

      expect(res.statusCode, equals(200));
    });
  });
}
