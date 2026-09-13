import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/movie_item.dart';

class TMDBService {
  static const String _defaultApiKey = '4e44d9029b1270a757cddc766a1bcb63';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  static final TMDBService instance = TMDBService();

  final http.Client _client;

  TMDBService({http.Client? client}) : _client = client ?? http.Client();

  String get _apiKey {
    try {
      final envKey = dotenv.env['TMDB_API_KEY'];
      if (envKey != null && envKey.trim().isNotEmpty) {
        return envKey.trim();
      }
    } catch (_) {}
    return _defaultApiKey;
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
      };

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final params = <String, String>{
      'api_key': _apiKey,
      'language': 'pt-BR',
      ...?queryParams,
    };
    return Uri.parse('$_baseUrl$path').replace(queryParameters: params);
  }

  /// Busca textual retornando filmes e séries com títulos em PT-BR, pôsteres e tmdb_id
  Future<List<MovieItem>> searchMedia(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return getTrendingMovies();
    }

    try {
      final uri = _buildUri('/search/multi', {
        'query': cleanQuery,
        'include_adult': 'false',
      });

      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] is List) {
          final List results = data['results'];
          return results
              .where((item) {
                final mediaType = item['media_type'];
                return mediaType == 'movie' || mediaType == 'tv';
              })
              .map((json) => MovieItem.fromTmdb(json))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[TMDBService] Erro ao buscar mídias para "$cleanQuery": $e');
    }

    return _searchFallback(cleanQuery);
  }

  /// Lista de filmes populares e em alta
  Future<List<MovieItem>> getTrendingMovies() async {
    try {
      final uri = _buildUri('/trending/movie/day');
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] is List) {
          final List results = data['results'];
          return results.map((j) => MovieItem.fromTmdb(j, defaultType: 'movie')).toList();
        }
      }
    } catch (e) {
      debugPrint('[TMDBService] Erro ao buscar trending movies: $e');
    }

    return _mockTrendingMovies;
  }

  /// Lista de séries populares e em alta
  Future<List<MovieItem>> getTrendingSeries() async {
    try {
      final uri = _buildUri('/trending/tv/day');
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] is List) {
          final List results = data['results'];
          return results.map((j) => MovieItem.fromTmdb(j, defaultType: 'tv')).toList();
        }
      }
    } catch (e) {
      debugPrint('[TMDBService] Erro ao buscar trending series: $e');
    }

    return _mockTrendingSeries;
  }

  /// Listar episódios de uma temporada para alimentar a seleção de episódios
  Future<List<EpisodeItem>> getSeriesEpisodes(int tmdbId, int seasonNumber) async {
    try {
      final uri = _buildUri('/tv/$tmdbId/season/$seasonNumber');
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['episodes'] is List) {
          final List episodes = data['episodes'];
          return episodes.map((j) => EpisodeItem.fromJson(j)).toList();
        }
      }
    } catch (e) {
      debugPrint('[TMDBService] Erro ao buscar episódios da série $tmdbId (temp $seasonNumber): $e');
    }

    // Fallback com episódios gerados caso falhe a conexão
    return List.generate(
      10,
      (index) => EpisodeItem(
        id: tmdbId * 100 + (index + 1),
        seasonNumber: seasonNumber,
        episodeNumber: index + 1,
        name: 'Episódio ${index + 1}',
        overview: 'Reproduza este episódio via SuperFlix API.',
      ),
    );
  }

  /// Detalhes completos da série (incluindo total de temporadas)
  Future<Map<String, dynamic>?> getSeriesDetails(int tmdbId) async {
    try {
      final uri = _buildUri('/tv/$tmdbId');
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('[TMDBService] Erro ao buscar detalhes da série $tmdbId: $e');
    }
    return null;
  }

  List<MovieItem> _searchFallback(String query) {
    final all = [..._mockTrendingMovies, ..._mockTrendingSeries];
    final q = query.toLowerCase();
    return all.where((m) =>
        m.title.toLowerCase().contains(q) ||
        m.overview.toLowerCase().contains(q) ||
        m.genres.any((g) => g.toLowerCase().contains(q))).toList();
  }

  static final List<MovieItem> _mockTrendingMovies = [
    MovieItem(
      id: 533535,
      title: 'Deadpool & Wolverine',
      overview: 'Wolverine se recupera de seus graves ferimentos quando cruza o caminho do tagarela Deadpool em uma aventura pelo Multiverso.',
      posterPath: '/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
      backdropPath: '/by8z9Fe8y7p4jo2YlW2SZDnptyT.jpg',
      voteAverage: 8.7,
      releaseDate: '2024-07-25',
      mediaType: 'movie',
      genres: ['Ação', 'Comédia', 'Ficção'],
      duration: '2h 08m',
    ),
    MovieItem(
      id: 569094,
      title: 'Homem-Aranha: Através do Aranhaverso',
      overview: 'Miles Morales é catapultado através do Multiverso, onde encontra uma equipe de elite de Pessoas-Aranha.',
      posterPath: '/dB6Krk806zeqd0YNp2ngQ9zXteH.jpg',
      backdropPath: '/4HodYYKEIsGOdinkGi2Ucz6X9i0.jpg',
      voteAverage: 8.9,
      releaseDate: '2023-06-01',
      mediaType: 'movie',
      genres: ['Animação', 'Ação', 'Aventura'],
      duration: '2h 20m',
    ),
    MovieItem(
      id: 940721,
      title: 'Godzilla e Kong: O Novo Império',
      overview: 'Uma jornada colossal onde duas forças lendárias se unem contra uma ameaça oculta na Terra Oca.',
      posterPath: '/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg',
      backdropPath: '/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg',
      voteAverage: 8.5,
      releaseDate: '2024-03-27',
      mediaType: 'movie',
      genres: ['Ação', 'Ficção Científica'],
      duration: '1h 55m',
    ),
  ];

  static final List<MovieItem> _mockTrendingSeries = [
    MovieItem(
      id: 94997,
      title: 'A Casa do Dragão',
      overview: 'A história da guerra civil Targaryen que aconteceu cerca de 200 anos antes dos eventos de Game of Thrones.',
      posterPath: '/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg',
      backdropPath: '/etj5CuMuamBvRdPqgQwhQq3uNYe.jpg',
      voteAverage: 8.4,
      releaseDate: '2022-08-21',
      mediaType: 'tv',
      genres: ['Drama', 'Ação & Aventura', 'Sci-Fi & Fantasy'],
      duration: '2 Temp.',
      numberOfSeasons: 2,
    ),
    MovieItem(
      id: 1399,
      title: 'Game of Thrones',
      overview: 'Em uma terra onde os verões podem durar décadas e o inverno uma vida inteira, perigos e disputas pelo Trono de Ferro aguardam.',
      posterPath: '/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg',
      backdropPath: '/2OMB0ynKlyIenMJWI2Dy9IWT4c.jpg',
      voteAverage: 8.5,
      releaseDate: '2011-04-17',
      mediaType: 'tv',
      genres: ['Sci-Fi & Fantasy', 'Drama', 'Ação & Aventura'],
      duration: '8 Temp.',
      numberOfSeasons: 8,
    ),
    MovieItem(
      id: 66732,
      title: 'Stranger Things',
      overview: 'Quando um garoto desaparece, uma pequena cidade descobre um mistério envolvendo experimentos secretos e forças sobrenaturais.',
      posterPath: '/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
      backdropPath: '/56v2KjBlU4XaOv9rVYEQypROD7P.jpg',
      voteAverage: 8.6,
      releaseDate: '2016-07-15',
      mediaType: 'tv',
      genres: ['Sci-Fi & Fantasy', 'Drama', 'Mistério'],
      duration: '4 Temp.',
      numberOfSeasons: 4,
    ),
  ];
}
