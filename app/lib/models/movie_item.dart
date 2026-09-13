class MovieItem {
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final String? releaseDate;
  final String mediaType; // 'movie' ou 'tv'
  final List<String> genres;
  final String duration;
  final String quality;
  final String ageRating;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;

  MovieItem({
    required this.id,
    required this.title,
    required this.overview,
    this.posterPath,
    this.backdropPath,
    required this.voteAverage,
    this.releaseDate,
    this.mediaType = 'movie',
    this.genres = const ['Cinema', 'Popular'],
    this.duration = '2h 15m',
    this.quality = '4K Ultra HD',
    this.ageRating = '14+',
    this.numberOfSeasons,
    this.numberOfEpisodes,
  });

  bool get isSeries => mediaType == 'tv';

  String get releaseYear {
    if (releaseDate != null && releaseDate!.length >= 4) {
      return releaseDate!.substring(0, 4);
    }
    return '2024';
  }

  String get fullPosterUrl {
    if (posterPath != null && posterPath!.startsWith('http')) {
      return posterPath!;
    }
    if (posterPath != null && posterPath!.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w500$posterPath';
    }
    return 'https://image.tmdb.org/t/p/w500/x0nvYzQpyJc5pdT9lMnkMuYAg0O.jpg';
  }

  String get fullBackdropUrl {
    if (backdropPath != null && backdropPath!.startsWith('http')) {
      return backdropPath!;
    }
    if (backdropPath != null && backdropPath!.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/original$backdropPath';
    }
    if (posterPath != null && posterPath!.isNotEmpty) {
      return fullPosterUrl;
    }
    return 'https://image.tmdb.org/t/p/original/qeQJx07rK2xm8SD2sJxFKhE7gs0.jpg';
  }

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
    10759: 'Ação & Aventura',
    10762: 'Kids',
    10763: 'Notícias',
    10764: 'Reality',
    10765: 'Ficção Científica & Fantasia',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'Guerra & Política',
  };

  factory MovieItem.fromTmdb(Map<String, dynamic> json, {String? defaultType}) {
    final type = json['media_type']?.toString() ??
        defaultType ??
        (json['first_air_date'] != null || json['name'] != null ? 'tv' : 'movie');

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
      parsedGenres = type == 'tv' ? ['Série', 'Drama'] : ['Cinema', 'Popular'];
    }

    final double rating = (json['vote_average'] is num)
        ? (json['vote_average'] as num).toDouble()
        : 7.5;

    final String rawDate = json['release_date'] ?? json['first_air_date'] ?? '2024';
    final int mediaId = json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0;
    final String title = json['title'] ?? json['name'] ?? 'Título Indisponível';

    return MovieItem(
      id: mediaId,
      title: title,
      overview: (json['overview'] != null && json['overview'].toString().trim().isNotEmpty)
          ? json['overview'].toString()
          : 'Sinopse oficial disponível em breve na plataforma.',
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      voteAverage: rating,
      releaseDate: rawDate,
      mediaType: type,
      genres: parsedGenres,
      duration: type == 'tv'
          ? '${json['number_of_seasons'] ?? 1} Temp.'
          : '2h ${(mediaId % 25 + 5)}m',
      quality: rating >= 8.0 ? '4K IMAX' : '4K HDR',
      ageRating: rating >= 8.0 ? '16+' : '12+',
      numberOfSeasons: json['number_of_seasons'] is int ? json['number_of_seasons'] : null,
      numberOfEpisodes: json['number_of_episodes'] is int ? json['number_of_episodes'] : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'overview': overview,
      'posterPath': posterPath,
      'backdropPath': backdropPath,
      'voteAverage': voteAverage,
      'releaseDate': releaseDate,
      'mediaType': mediaType,
      'genres': genres,
      'duration': duration,
      'quality': quality,
      'ageRating': ageRating,
      'numberOfSeasons': numberOfSeasons,
      'numberOfEpisodes': numberOfEpisodes,
    };
  }
}

class EpisodeItem {
  final int id;
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final String? airDate;
  final double voteAverage;

  EpisodeItem({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    required this.overview,
    this.stillPath,
    this.airDate,
    this.voteAverage = 7.5,
  });

  String get fullStillUrl {
    if (stillPath != null && stillPath!.startsWith('http')) {
      return stillPath!;
    }
    if (stillPath != null && stillPath!.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w500$stillPath';
    }
    return 'https://image.tmdb.org/t/p/w500/qeQJx07rK2xm8SD2sJxFKhE7gs0.jpg';
  }

  String get titleLabel => 'Ep. $episodeNumber - $name';

  factory EpisodeItem.fromJson(Map<String, dynamic> json) {
    return EpisodeItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      seasonNumber: json['season_number'] ?? 1,
      episodeNumber: json['episode_number'] ?? 1,
      name: (json['name'] != null && json['name'].toString().trim().isNotEmpty)
          ? json['name'].toString()
          : 'Episódio ${json['episode_number'] ?? 1}',
      overview: (json['overview'] != null && json['overview'].toString().trim().isNotEmpty)
          ? json['overview'].toString()
          : 'Sinopse deste episódio não disponível.',
      stillPath: json['still_path'],
      airDate: json['air_date'],
      voteAverage: (json['vote_average'] is num) ? (json['vote_average'] as num).toDouble() : 7.5,
    );
  }
}
