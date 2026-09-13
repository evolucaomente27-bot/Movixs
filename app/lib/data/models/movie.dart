class Movie {
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final String? releaseDate;
  final List<String> genres;
  final String duration;
  final String quality;
  final String ageRating;
  final String? videoUrl;
  final String? imdbId;
  final int voteCount;
  final double popularity;
  final String? originalTitle;
  final bool isTvShow;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    this.posterPath,
    this.backdropPath,
    required this.voteAverage,
    this.releaseDate,
    this.genres = const ['Cinema', 'Popular'],
    this.duration = '2h 15m',
    this.quality = '4K Ultra HD',
    this.ageRating = '14+',
    this.videoUrl,
    this.imdbId,
    this.voteCount = 1000,
    this.popularity = 20.0,
    this.originalTitle,
    this.isTvShow = false,
    this.numberOfSeasons,
    this.numberOfEpisodes,
  });

  static const Map<int, String> _genreMap = {
    28: 'Ação',
    12: 'Aventura',
    16: 'Animação',
    35: 'Comédia',
    80: 'Crime',
    99: 'Documentário',
    18: 'Drama',
    10751: 'Família',
    14: 'Fantasia',
    36: 'História',
    27: 'Terror',
    10402: 'Música',
    9648: 'Mistério',
    10749: 'Romance',
    878: 'Ficção Científica',
    10770: 'Cinema TV',
    53: 'Suspense',
    10752: 'Guerra',
    37: 'Faroeste',
  };

  factory Movie.fromJson(Map<String, dynamic> json) {
    List<String> parsedGenres = [];
    if (json['genres'] != null && json['genres'] is List) {
      parsedGenres = (json['genres'] as List)
          .map((g) => g is Map ? g['name'].toString() : g.toString())
          .toList();
    } else if (json['genre_ids'] != null && json['genre_ids'] is List) {
      parsedGenres = (json['genre_ids'] as List)
          .map((id) => _genreMap[id] ?? 'Cinema')
          .take(3)
          .toList();
    }

    if (parsedGenres.isEmpty) {
      parsedGenres = ['Cinema', 'Popular'];
    }

    final double rating = (json['vote_average'] is num)
        ? (json['vote_average'] as num).toDouble()
        : 7.5;

    final String rawDate = json['release_date'] ?? json['first_air_date'] ?? '2024';
    final int movieId = json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0;

    final int votes = (json['vote_count'] is num)
        ? (json['vote_count'] as num).toInt()
        : 1000;

    final double pop = (json['popularity'] is num)
        ? (json['popularity'] as num).toDouble()
        : 20.0;

    final String? origTitle = json['original_title']?.toString() ?? json['original_name']?.toString();

    final bool isTv = json['media_type'] == 'tv' ||
        json['first_air_date'] != null ||
        (json['name'] != null && json['title'] == null) ||
        (json['number_of_seasons'] != null);

    final int? seasons = json['number_of_seasons'] is int
        ? json['number_of_seasons']
        : int.tryParse(json['number_of_seasons']?.toString() ?? '');

    final int? episodes = json['number_of_episodes'] is int
        ? json['number_of_episodes']
        : int.tryParse(json['number_of_episodes']?.toString() ?? '');

    final String durationString = isTv
        ? (seasons != null && seasons > 1
            ? '$seasons Temporadas'
            : (seasons == 1 ? '1 Temporada' : 'Série'))
        : (json['runtime'] != null && json['runtime'] is num && (json['runtime'] as num) > 0
            ? '${((json['runtime'] as num) / 60).floor()}h ${((json['runtime'] as num) % 60).toInt()}m'
            : '2h ${(movieId % 25 + 5)}m');

    return Movie(
      id: movieId,
      title: json['title'] ?? json['name'] ?? 'Título',
      overview: (json['overview'] != null && json['overview'].toString().trim().isNotEmpty)
          ? json['overview'].toString()
          : 'Sinopse oficial disponível em breve na plataforma.',
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      voteAverage: rating,
      releaseDate: rawDate,
      genres: parsedGenres,
      duration: durationString,
      quality: rating >= 8.0 ? '4K IMAX' : '4K HDR',
      ageRating: rating >= 8.0 ? '16+' : '12+',
      videoUrl: json['video_url'],
      imdbId: json['imdb_id']?.toString() ?? json['imdbId']?.toString(),
      voteCount: votes,
      popularity: pop,
      originalTitle: origTitle,
      isTvShow: isTv,
      numberOfSeasons: seasons,
      numberOfEpisodes: episodes,
    );
  }

  /// Retorna true se o filme já foi oficialmente lançado no cinema/streaming
  bool get isReleased {
    if (releaseDate == null || releaseDate!.trim().isEmpty) return false;
    final parsed = DateTime.tryParse(releaseDate!);
    if (parsed == null) return true;
    return !parsed.isAfter(DateTime.now());
  }

  /// Retorna true se é um filme real, lançado e com material de reprodução
  bool get isRealWatchableMovie {
    if (posterPath == null || posterPath!.trim().isEmpty) return false;
    if (!isReleased) return false;
    return voteCount >= 5 || popularity >= 4.0;
  }

  String get releaseYear {
    if (releaseDate != null && releaseDate!.length >= 4) {
      return releaseDate!.substring(0, 4);
    }
    return '2024';
  }

  String get fullPosterUrl => posterPath != null && posterPath!.startsWith('http')
      ? posterPath!
      : posterPath != null
          ? 'https://image.tmdb.org/t/p/w500$posterPath'
          : 'https://image.tmdb.org/t/p/w500/x0nvYzQpyJc5pdT9lMnkMuYAg0O.jpg';

  String get fullBackdropUrl => backdropPath != null && backdropPath!.startsWith('http')
      ? backdropPath!
      : backdropPath != null
          ? 'https://image.tmdb.org/t/p/original$backdropPath'
          : (posterPath != null
              ? 'https://image.tmdb.org/t/p/original$posterPath'
              : 'https://image.tmdb.org/t/p/original/qeQJx07rK2xm8SD2sJxFKhE7gs0.jpg');
}
