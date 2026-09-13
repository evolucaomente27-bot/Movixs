import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/movie.dart';
import '../models/tv_models.dart';

class TMDBRepository {
  static const String _defaultKey = '4e44d9029b1270a757cddc766a1bcb63';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.themoviedb.org/3',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  String get _apiKey {
    try {
      final envKey = dotenv.env['TMDB_API_KEY'];
      if (envKey != null && envKey.trim().isNotEmpty) {
        return envKey.trim();
      }
    } catch (_) {}
    return _defaultKey;
  }

  Future<List<Movie>> getFeaturedHeroMovies() async {
    try {
      final response = await _dio.get('/trending/movie/week', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.take(6).map((json) => Movie.fromJson(json)).toList();
      }
    } catch (e) {
      print('TMDB Hero Live Error: $e');
    }
    return _getHeroBillboardList();
  }

  Future<List<Movie>> getTrendingMovies() async {
    try {
      final response = await _dio.get('/trending/movie/day', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.map((json) => Movie.fromJson(json)).toList();
      }
    } catch (e) {
      print('TMDB Trending Live Error: $e');
    }
    return _getTrendingMock();
  }

  Future<List<Movie>> getTop10Movies() async {
    try {
      final response = await _dio.get('/movie/top_rated', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.take(10).map((json) => Movie.fromJson(json)).toList();
      }
    } catch (e) {
      print('TMDB Top Rated Live Error: $e');
    }
    return _getTop10Mock();
  }

  Future<List<Movie>> getActionMovies() async {
    try {
      final response = await _dio.get('/discover/movie', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
        'with_genres': '28',
        'sort_by': 'popularity.desc',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.map((json) => Movie.fromJson(json)).toList();
      }
    } catch (e) {
      print('TMDB Action Live Error: $e');
    }
    return _getActionMock();
  }

  Future<List<Movie>> getSciFiMovies() async {
    try {
      final response = await _dio.get('/discover/movie', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
        'with_genres': '878',
        'sort_by': 'popularity.desc',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.map((json) => Movie.fromJson(json)).toList();
      }
    } catch (e) {
      print('TMDB Sci-Fi Live Error: $e');
    }
    return _getSciFiMock();
  }

  // --- SÉRIES DE TV (TMDB TV) ---

  /// Séries em Alta (Trending TV)
  Future<List<Movie>> getTrendingTvShows() async {
    try {
      final response = await _dio.get('/trending/tv/week', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.map((json) {
          final m = Map<String, dynamic>.from(json);
          m['media_type'] = 'tv';
          return Movie.fromJson(m);
        }).toList();
      }
    } catch (e) {
      print('TMDB Trending TV Live Error: $e');
    }
    return _getTrendingTvMock();
  }

  /// Séries Mais Populares
  Future<List<Movie>> getPopularTvShows() async {
    try {
      final response = await _dio.get('/tv/popular', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.map((json) {
          final m = Map<String, dynamic>.from(json);
          m['media_type'] = 'tv';
          return Movie.fromJson(m);
        }).toList();
      }
    } catch (e) {
      print('TMDB Popular TV Live Error: $e');
    }
    return _getTrendingTvMock();
  }

  /// Séries Mais Bem Avaliadas (Top Rated TV)
  Future<List<Movie>> getTopRatedTvShows() async {
    try {
      final response = await _dio.get('/tv/top_rated', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      final List results = response.data['results'] ?? [];
      if (results.isNotEmpty) {
        return results.take(10).map((json) {
          final m = Map<String, dynamic>.from(json);
          m['media_type'] = 'tv';
          return Movie.fromJson(m);
        }).toList();
      }
    } catch (e) {
      print('TMDB Top Rated TV Live Error: $e');
    }
    return _getTrendingTvMock();
  }

  /// Detalhes completos da Série (incluindo temporadas)
  Future<Map<String, dynamic>?> getTvShowDetails(int tvId) async {
    try {
      final response = await _dio.get('/tv/$tvId', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data);
      }
    } catch (e) {
      print('TMDB TV Details Error: $e');
    }
    return null;
  }

  /// Lista de Temporadas da Série
  Future<List<TvSeason>> getTvShowSeasons(int tvId) async {
    final details = await getTvShowDetails(tvId);
    if (details != null && details['seasons'] is List) {
      final list = (details['seasons'] as List)
          .map((s) => TvSeason.fromJson(Map<String, dynamic>.from(s)))
          .where((s) => s.seasonNumber > 0) // Remove Especiais (Temporada 0)
          .toList();
      if (list.isNotEmpty) return list;
    }
    return [
      TvSeason(
        id: 1,
        seasonNumber: 1,
        name: 'Temporada 1',
        overview: 'Primeira temporada completa.',
        episodeCount: 8,
      )
    ];
  }

  /// Lista de Episódios de uma Temporada
  Future<List<TvEpisode>> getTvSeasonEpisodes(int tvId, int seasonNumber) async {
    try {
      final response = await _dio.get('/tv/$tvId/season/$seasonNumber', queryParameters: {
        'api_key': _apiKey,
        'language': 'pt-BR',
      });
      if (response.statusCode == 200 && response.data != null) {
        final List eps = response.data['episodes'] ?? [];
        if (eps.isNotEmpty) {
          return eps
              .map((e) => TvEpisode.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (e) {
      print('TMDB TV Season Episodes Error: $e');
    }

    return List.generate(
      8,
      (i) => TvEpisode(
        id: i + 1,
        episodeNumber: i + 1,
        seasonNumber: seasonNumber,
        name: 'Episódio ${i + 1}',
        overview: 'Assista agora em alta definição com áudio dublado e legendado.',
        voteAverage: 8.5,
        runtime: 48,
      ),
    );
  }

  // --- BUSCA UNIFICADA (FILMES E SÉRIES) ---

  Future<List<Movie>> searchMovies(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return getTrendingMovies();
    }
    try {
      // 1. Detecta ano se o usuário digitou ex: "Batman 1989" ou "Homem-Aranha 2002"
      final yearRegex = RegExp(r'\b(19\d\d|20\d\d)\b');
      final yearMatch = yearRegex.firstMatch(cleanQuery);
      String queryTerm = cleanQuery;
      int? targetYear;
      if (yearMatch != null) {
        targetYear = int.tryParse(yearMatch.group(1)!);
        queryTerm = cleanQuery.replaceAll(yearRegex, '').trim();
        if (queryTerm.isEmpty) queryTerm = cleanQuery;
      }

      final movieParams = <String, dynamic>{
        'api_key': _apiKey,
        'language': 'pt-BR',
        'query': queryTerm,
        'include_adult': false,
      };
      if (targetYear != null) {
        movieParams['primary_release_year'] = targetYear;
      }

      final tvParams = <String, dynamic>{
        'api_key': _apiKey,
        'language': 'pt-BR',
        'query': queryTerm,
        'include_adult': false,
      };

      // Busca simultânea de filmes e séries
      final responses = await Future.wait([
        _dio.get('/search/movie', queryParameters: movieParams),
        _dio.get('/search/tv', queryParameters: tvParams),
      ]);

      final List movieResults = responses[0].data['results'] ?? [];
      final List tvResults = responses[1].data['results'] ?? [];

      final parsedMovies = movieResults.map((json) => Movie.fromJson(json)).toList();
      final parsedTv = tvResults.map((json) {
        final m = Map<String, dynamic>.from(json);
        m['media_type'] = 'tv';
        return Movie.fromJson(m);
      }).toList();

      final allParsed = [...parsedMovies, ...parsedTv];
      if (allParsed.isNotEmpty) {

        // 2. Filtro estrito de Filmes "Reais" (lançados, com capa e com audiência confirmada)
        final realMovies = allParsed.where((m) {
          // Descarta sem pôster
          if (m.posterPath == null || m.posterPath!.trim().isEmpty) return false;

          // Descarta filmes do futuro não lançados (ex: anúncios e rumores de 2026/2027)
          if (!m.isReleased) return false;

          // Descarta registros vazios sem votos e sem popularidade
          if (m.voteCount < 3 && m.popularity < 3.0) return false;

          return true;
        }).toList();

        // 3. Ordenação inteligente: Correspondência de Título + Votos Reais + Popularidade
        final lowerQuery = queryTerm.toLowerCase();
        realMovies.sort((a, b) {
          // Correspondência exata do título em PT-BR ou nome original
          final aExact = a.title.toLowerCase() == lowerQuery ||
              (a.originalTitle?.toLowerCase() == lowerQuery);
          final bExact = b.title.toLowerCase() == lowerQuery ||
              (b.originalTitle?.toLowerCase() == lowerQuery);
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;

          // Título que começa com a busca
          final aStarts = a.title.toLowerCase().startsWith(lowerQuery);
          final bStarts = b.title.toLowerCase().startsWith(lowerQuery);
          if (aStarts && !bStarts) return -1;
          if (!aStarts && bStarts) return 1;

          // Score ponderado de popularidade e contagem de avaliações reais
          final aScore = (a.voteCount * 1.5) + (a.popularity * 3.0);
          final bScore = (b.voteCount * 1.5) + (b.popularity * 3.0);
          return bScore.compareTo(aScore);
        });

        if (realMovies.isNotEmpty) {
          return realMovies;
        }

        // Fallback defensivo com pôster caso o termo seja ultra-específico
        final fallbackList = allParsed
            .where((m) => m.posterPath != null && m.posterPath!.isNotEmpty)
            .toList();
        if (fallbackList.isNotEmpty) {
          return fallbackList;
        }
      }
    } catch (e) {
      print('TMDB Search Live Error: $e');
    }

    // Fallback de busca local
    final all = [
      ..._getHeroBillboardList(),
      ..._getTrendingMock(),
      ..._getTop10Mock(),
      ..._getActionMock(),
      ..._getSciFiMock(),
    ];
    final seen = <int>{};
    return all.where((m) => seen.add(m.id)).where((m) =>
      m.title.toLowerCase().contains(cleanQuery.toLowerCase()) ||
      m.genres.any((g) => g.toLowerCase().contains(cleanQuery.toLowerCase())) ||
      m.overview.toLowerCase().contains(cleanQuery.toLowerCase())
    ).toList();
  }

  // --- CATÁLOGO DE FALLBACK SE ESTIVER OFFLINE ---

  List<Movie> _getHeroBillboardList() {
    return [
      Movie(
        id: 533535,
        title: 'Deadpool & Wolverine',
        overview: 'Wolverine se recupera de seus graves ferimentos quando cruza o caminho do tagarela e desbocado Deadpool. Juntos, eles viajam pelo Multiverso em uma missão explosiva.',
        posterPath: '/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
        backdropPath: '/by8z9Fe8y7p4jo2YlW2SZDnptyT.jpg',
        voteAverage: 8.7,
        releaseDate: '2024',
        genres: ['Ação', 'Comédia', 'Ficção Científica'],
        duration: '2h 08m',
        quality: '4K IMAX',
        ageRating: '18+',
      ),
      Movie(
        id: 569094,
        title: 'Homem-Aranha: Através do Aranhaverso',
        overview: 'Miles Morales é catapultado através do Multiverso, onde encontra uma equipe de elite de Pessoas-Aranha encarregadas de proteger sua própria existência.',
        posterPath: '/dB6Krk806zeqd0YNp2ngQ9zXteH.jpg',
        backdropPath: '/4HodYYKEIsGOdinkGi2Ucz6X9i0.jpg',
        voteAverage: 8.9,
        releaseDate: '2023',
        genres: ['Animação', 'Ação', 'Aventura'],
        duration: '2h 20m',
        quality: '4K Ultra HD',
        ageRating: '10+',
      ),
      Movie(
        id: 940721,
        title: 'Godzilla e Kong: O Novo Império',
        overview: 'Uma jornada colossal onde duas forças lendárias se unem contra uma ameaça oculta que coloca em perigo a existência dos Titãs e da humanidade.',
        posterPath: '/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg',
        backdropPath: '/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg',
        voteAverage: 8.5,
        releaseDate: '2024',
        genres: ['Ação', 'Ficção Científica', 'Aventura'],
        duration: '1h 55m',
        quality: '4K HDR',
        ageRating: '12+',
      ),
    ];
  }

  List<Movie> _getTrendingMock() {
    return [
      Movie(
        id: 533535,
        title: 'Deadpool & Wolverine',
        overview: 'O mercenário tagarela une forças com o lendário mutante Wolverine em uma missão pelo Multiverso.',
        posterPath: '/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
        backdropPath: '/by8z9Fe8y7p4jo2YlW2SZDnptyT.jpg',
        voteAverage: 8.7,
        releaseDate: '2024',
        genres: ['Ação', 'Comédia'],
      ),
      Movie(
        id: 569094,
        title: 'Homem-Aranha no Aranhaverso',
        overview: 'Miles Morales viaja pelo multiverso ao lado de Gwen Stacy para enfrentar o temido Mancha.',
        posterPath: '/dB6Krk806zeqd0YNp2ngQ9zXteH.jpg',
        backdropPath: '/4HodYYKEIsGOdinkGi2Ucz6X9i0.jpg',
        voteAverage: 8.9,
        releaseDate: '2023',
        genres: ['Animação', 'Ação'],
      ),
      Movie(
        id: 940721,
        title: 'Godzilla e Kong: O Novo Império',
        overview: 'Uma jornada colossal onde duas forças lendárias se unem contra o temível Rei Cicatriz.',
        posterPath: '/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg',
        backdropPath: '/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg',
        voteAverage: 7.8,
        releaseDate: '2024',
        genres: ['Ação', 'Ficção'],
      ),
      Movie(
        id: 414906,
        title: 'The Batman',
        overview: 'Nos dois anos em que perseguiu as ruas como o Batman, Bruce Wayne encontrou o submundo corrupto de Gotham.',
        posterPath: '/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg',
        backdropPath: '/b0PlSFdDwbyK0cf5RxwDpaOJQvQ.jpg',
        voteAverage: 8.1,
        releaseDate: '2022',
        genres: ['Crime', 'Mistério', 'Ação'],
      ),
      Movie(
        id: 447365,
        title: 'Guardiões da Galáxia Vol. 3',
        overview: 'Peter Quill e sua equipe embarcam em uma perigosa missão contra o Alto Evolucionário para salvar Rocket.',
        posterPath: '/fiVW06jE7z9YnO4trhaMEdclSiC.jpg',
        backdropPath: '/5YZbUmjbMa3ClvSW1Wj3D6XGolb.jpg',
        voteAverage: 8.3,
        releaseDate: '2023',
        genres: ['Aventura', 'Sci-Fi'],
      ),
      Movie(
        id: 385687,
        title: 'Velozes e Furiosos 10',
        overview: 'Dom Toretto e sua família enfrentam o filho de Hernan Reyes em uma vingança implacável por Roma.',
        posterPath: '/1E5baAaEse26fej7uHcjOgEE2t2.jpg',
        backdropPath: '/4XM8DUTQb3lhLemJC51Jx4a2EuA.jpg',
        voteAverage: 7.9,
        releaseDate: '2023',
        genres: ['Ação', 'Crime'],
      ),
    ];
  }

  List<Movie> _getTop10Mock() {
    return [
      Movie(
        id: 155,
        title: 'Batman: O Cavaleiro das Trevas',
        overview: 'Com a ajuda do tenente Jim Gordon e Harvey Dent, Batman combate a onda de caos criada pelo Coringa.',
        posterPath: '/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
        backdropPath: '/dqK9Hag1054tghRQSqLSfrkvQnA.jpg',
        voteAverage: 9.0,
        releaseDate: '2008',
        genres: ['Ação', 'Drama'],
      ),
      Movie(
        id: 299536,
        title: 'Vingadores: Guerra Infinita',
        overview: 'Os Vingadores e os Guardiões da Galáxia unem forças para tentar impedir que Thanos colete as Joias do Infinito.',
        posterPath: '/7WsyChQLEftFiDOVTGkv3hFpyyt.jpg',
        backdropPath: '/mDfJG3LC3Dqb67AZ52x3Z0jU0uB.jpg',
        voteAverage: 8.8,
        releaseDate: '2018',
        genres: ['Ação', 'Aventura'],
      ),
      Movie(
        id: 76600,
        title: 'Avatar: O Caminho da Água',
        overview: 'Jake Sully e Neytiri exploram as regiões oceânicas de Pandora ao lado dos Metkayina.',
        posterPath: '/6KErczPBROQty7QoIsaa6wJYXZi.jpg',
        backdropPath: '/s16H6tpK2utvwDtzZ8Qy4qm5Emw.jpg',
        voteAverage: 8.6,
        releaseDate: '2022',
        genres: ['Sci-Fi', 'Ação'],
      ),
      Movie(
        id: 298618,
        title: 'The Flash',
        overview: 'Barry Allen usa seus superpoderes para viajar no tempo e acaba colidindo com uma linha do tempo alternativa sem meta-humanos.',
        posterPath: '/rktDFPbfHfUbArZ6OOOKsXcv0Bm.jpg',
        backdropPath: '/yF1eOkaYvwiORauRCPWznV9xVvi.jpg',
        voteAverage: 8.4,
        releaseDate: '2023',
        genres: ['Ação', 'Aventura'],
      ),
      Movie(
        id: 438631,
        title: 'Duna: Parte Um',
        overview: 'Paul Atreides viaja para o planeta desértico Arrakis para proteger a especiaria mais valiosa do universo.',
        posterPath: '/ctMserH8g2SeOAnCw5gFjdQF8mo.jpg',
        backdropPath: '/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg',
        voteAverage: 8.5,
        releaseDate: '2021',
        genres: ['Ficção Científica', 'Aventura'],
      ),
    ];
  }

  List<Movie> _getActionMock() {
    return [
      Movie(
        id: 298618,
        title: 'The Flash',
        overview: 'Barry Allen corre contra o tempo para salvar o multiverso ao lado do Batman de Michael Keaton.',
        posterPath: '/rktDFPbfHfUbArZ6OOOKsXcv0Bm.jpg',
        backdropPath: '/yF1eOkaYvwiORauRCPWznV9xVvi.jpg',
        voteAverage: 8.4,
        releaseDate: '2023',
        genres: ['Ação', 'Aventura'],
      ),
      Movie(
        id: 385687,
        title: 'Velozes e Furiosos 10',
        overview: 'Dom Toretto acelera nas ruas de Roma para proteger seu filho e sua equipe.',
        posterPath: '/1E5baAaEse26fej7uHcjOgEE2t2.jpg',
        backdropPath: '/4XM8DUTQb3lhLemJC51Jx4a2EuA.jpg',
        voteAverage: 7.9,
        releaseDate: '2023',
        genres: ['Ação', 'Suspense'],
      ),
      Movie(
        id: 414906,
        title: 'The Batman',
        overview: 'Investigação e pancadaria sombria nas ruas chuvosas de Gotham contra o Charada.',
        posterPath: '/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg',
        backdropPath: '/b0PlSFdDwbyK0cf5RxwDpaOJQvQ.jpg',
        voteAverage: 8.1,
        releaseDate: '2022',
        genres: ['Ação', 'Crime'],
      ),
    ];
  }

  List<Movie> _getSciFiMock() {
    return [
      Movie(
        id: 438631,
        title: 'Duna: Parte Um',
        overview: 'A jornada épica e espiritual de Paul Atreides nas dunas de Arrakis.',
        posterPath: '/ctMserH8g2SeOAnCw5gFjdQF8mo.jpg',
        backdropPath: '/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg',
        voteAverage: 8.5,
        releaseDate: '2021',
        genres: ['Ficção Científica', 'Aventura'],
      ),
      Movie(
        id: 76600,
        title: 'Avatar: O Caminho da Água',
        overview: 'O espetáculo visual inigualável das criaturas marinhas de Pandora.',
        posterPath: '/6KErczPBROQty7QoIsaa6wJYXZi.jpg',
        backdropPath: '/s16H6tpK2utvwDtzZ8Qy4qm5Emw.jpg',
        voteAverage: 8.6,
        releaseDate: '2022',
        genres: ['Sci-Fi', 'Fantasia'],
      ),
      Movie(
        id: 447365,
        title: 'Guardiões da Galáxia Vol. 3',
        overview: 'A despedida emocionante da tripulação de Peter Quill pelo espaço.',
        posterPath: '/fiVW06jE7z9YnO4trhaMEdclSiC.jpg',
        backdropPath: '/5YZbUmjbMa3ClvSW1Wj3D6XGolb.jpg',
        voteAverage: 8.3,
        releaseDate: '2023',
        genres: ['Sci-Fi', 'Comédia'],
      ),
      Movie(
        id: 507089,
        title: 'Five Nights at Freddy\'s',
        overview: 'Animatrônicos ganham vida em um mistério sobrenatural na Pizzaria Freddy Fazbear.',
        posterPath: '/t5zCBSB5xMDKcDqe91qahCOUYVV.jpg',
        backdropPath: '/t5zCBSB5xMDKcDqe91qahCOUYVV.jpg',
        voteAverage: 7.9,
        releaseDate: '2023',
        genres: ['Terror', 'Ficção'],
      ),
    ];
  }

  List<Movie> _getTrendingTvMock() {
    return [
      Movie(
        id: 1396,
        title: 'Breaking Bad',
        overview: 'Ao saber que tem câncer terminal, um modesto professor de química decide produzir metanfetamina para garantir o futuro da família.',
        posterPath: '/30erzlzIOtYJu3LJ4LJ8k4WqmFI.jpg',
        backdropPath: '/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg',
        voteAverage: 8.9,
        releaseDate: '2008',
        genres: ['Drama', 'Crime'],
        duration: '5 Temporadas',
        isTvShow: true,
        numberOfSeasons: 5,
        numberOfEpisodes: 62,
      ),
      Movie(
        id: 66732,
        title: 'Stranger Things',
        overview: 'Um garoto desaparece sem deixar vestígios em uma pacata cidade. Segredos do governo e forças sobrenaturais começam a se revelar.',
        posterPath: '/49WJfeN0moxb9IPfGn8AIqMGskD.jpg',
        backdropPath: '/56v2KjBlU4XaOv9rVYEQypROD7P.jpg',
        voteAverage: 8.6,
        releaseDate: '2016',
        genres: ['Ficção Científica', 'Mistério', 'Drama'],
        duration: '4 Temporadas',
        isTvShow: true,
        numberOfSeasons: 4,
        numberOfEpisodes: 34,
      ),
      Movie(
        id: 76479,
        title: 'The Boys',
        overview: 'Um grupo de justiceiros parte para uma missão audaciosa: derrubar super-heróis corruptos que abusam de seus poderes.',
        posterPath: '/2zm7q4tzmFF8qU7u6HvVPnvIROT.jpg',
        backdropPath: '/nxxCPRGTzxUGqlMr4Q947HG3WUp.jpg',
        voteAverage: 8.5,
        releaseDate: '2019',
        genres: ['Ação', 'Ficção Científica'],
        duration: '4 Temporadas',
        isTvShow: true,
        numberOfSeasons: 4,
        numberOfEpisodes: 32,
      ),
      Movie(
        id: 100088,
        title: 'The Last of Us',
        overview: 'Joel e Ellie precisam atravessar os Estados Unidos pós-apocalíptico após uma pandemia devastadora.',
        posterPath: '/uKvVjHNqB5VmOrdxqAt2V7JMrqi.jpg',
        backdropPath: '/uDgy6hyPd82kOHh6I95FLtLnj6p.jpg',
        voteAverage: 8.6,
        releaseDate: '2023',
        genres: ['Drama', 'Ficção Científica'],
        duration: '1 Temporada',
        isTvShow: true,
        numberOfSeasons: 1,
        numberOfEpisodes: 9,
      ),
      Movie(
        id: 94997,
        title: 'A Casa do Dragão',
        overview: 'A guerra civil da Casa Targaryen pelo Trono de Ferro quase duzentos anos antes de Game of Thrones.',
        posterPath: '/1X4h40fcB4WWUmIBK0auT4zRBAV.jpg',
        backdropPath: '/etj5CuMuam3hD9MfW2bgji52wKf.jpg',
        voteAverage: 8.4,
        releaseDate: '2022',
        genres: ['Drama', 'Ação & Aventura', 'Fantasia'],
        duration: '2 Temporadas',
        isTvShow: true,
        numberOfSeasons: 2,
        numberOfEpisodes: 18,
      ),
    ];
  }
}
