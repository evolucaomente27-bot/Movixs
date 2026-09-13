class TvSeason {
  final int id;
  final int seasonNumber;
  final String name;
  final String overview;
  final int episodeCount;
  final String? posterPath;
  final String? airDate;

  TvSeason({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    required this.episodeCount,
    this.posterPath,
    this.airDate,
  });

  factory TvSeason.fromJson(Map<String, dynamic> json) {
    return TvSeason(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      seasonNumber: json['season_number'] is int
          ? json['season_number']
          : int.tryParse(json['season_number']?.toString() ?? '1') ?? 1,
      name: json['name'] ?? 'Temporada ${json['season_number'] ?? 1}',
      overview: json['overview'] ?? '',
      episodeCount: json['episode_count'] is int
          ? json['episode_count']
          : int.tryParse(json['episode_count']?.toString() ?? '0') ?? 0,
      posterPath: json['poster_path'],
      airDate: json['air_date'],
    );
  }

  String get fullPosterUrl => posterPath != null && posterPath!.startsWith('http')
      ? posterPath!
      : posterPath != null
          ? 'https://image.tmdb.org/t/p/w500$posterPath'
          : 'https://image.tmdb.org/t/p/w500/x0nvYzQpyJc5pdT9lMnkMuYAg0O.jpg';
}

class TvEpisode {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final String? airDate;
  final double voteAverage;
  final int? runtime;

  TvEpisode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    this.stillPath,
    this.airDate,
    required this.voteAverage,
    this.runtime,
  });

  factory TvEpisode.fromJson(Map<String, dynamic> json) {
    return TvEpisode(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      episodeNumber: json['episode_number'] is int
          ? json['episode_number']
          : int.tryParse(json['episode_number']?.toString() ?? '1') ?? 1,
      seasonNumber: json['season_number'] is int
          ? json['season_number']
          : int.tryParse(json['season_number']?.toString() ?? '1') ?? 1,
      name: json['name'] != null && json['name'].toString().trim().isNotEmpty
          ? json['name'].toString()
          : 'Episódio ${json['episode_number'] ?? 1}',
      overview: json['overview'] != null && json['overview'].toString().trim().isNotEmpty
          ? json['overview'].toString()
          : 'Sinopse do episódio disponível em breve.',
      stillPath: json['still_path'],
      airDate: json['air_date'],
      voteAverage: (json['vote_average'] is num)
          ? (json['vote_average'] as num).toDouble()
          : 0.0,
      runtime: json['runtime'] is int
          ? json['runtime']
          : int.tryParse(json['runtime']?.toString() ?? ''),
    );
  }

  String get fullStillUrl => stillPath != null && stillPath!.startsWith('http')
      ? stillPath!
      : stillPath != null
          ? 'https://image.tmdb.org/t/p/w500$stillPath'
          : 'https://image.tmdb.org/t/p/w500/x0nvYzQpyJc5pdT9lMnkMuYAg0O.jpg';

  String get durationFormatted {
    if (runtime != null && runtime! > 0) {
      return '${runtime}m';
    }
    return '45m';
  }
}
