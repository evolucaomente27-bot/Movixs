/// Item de filme retornado pela busca do scraper
class ScrapedMovieItem {
  final String title;
  final String pageUrl;
  final String posterUrl;
  final String audioType; // 'Dublado', 'Legendado', 'Nacional', 'Multi'
  final String? year;
  final String? quality;

  const ScrapedMovieItem({
    required this.title,
    required this.pageUrl,
    required this.posterUrl,
    this.audioType = 'Dublado',
    this.year,
    this.quality = 'HD',
  });

  bool get isDublado => audioType.toLowerCase().contains('dublado');
  bool get isLegendado => audioType.toLowerCase().contains('legendado');

  factory ScrapedMovieItem.fromJson(Map<String, dynamic> json) {
    return ScrapedMovieItem(
      title: json['title'] ?? '',
      pageUrl: json['pageUrl'] ?? json['url'] ?? '',
      posterUrl: json['posterUrl'] ?? json['poster'] ?? json['image'] ?? '',
      audioType: json['audioType'] ?? json['audio'] ?? 'Dublado',
      year: json['year']?.toString(),
      quality: json['quality']?.toString() ?? 'HD',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'pageUrl': pageUrl,
        'posterUrl': posterUrl,
        'audioType': audioType,
        'year': year,
        'quality': quality,
      };

  @override
  String toString() => 'ScrapedMovieItem(title: $title, audio: $audioType, year: $year)';
}

/// Fonte de player/servidor associada ao filme
class ScrapedPlayerSource {
  final String name;
  final String playerUrl;
  final String audioType; // 'Dublado' ou 'Legendado'
  final String serverType; // 'Streamtape', 'Mixdrop', 'Filemoon', 'Blogger', 'Warez', 'Embed', 'Direct'
  final Map<String, String> headers;

  const ScrapedPlayerSource({
    required this.name,
    required this.playerUrl,
    required this.audioType,
    required this.serverType,
    this.headers = const {},
  });

  bool get isDublado => audioType.toLowerCase().contains('dublado');
  bool get isLegendado => audioType.toLowerCase().contains('legendado');

  factory ScrapedPlayerSource.fromJson(Map<String, dynamic> json) {
    return ScrapedPlayerSource(
      name: json['name'] ?? 'Servidor',
      playerUrl: json['playerUrl'] ?? json['url'] ?? '',
      audioType: json['audioType'] ?? 'Dublado',
      serverType: json['serverType'] ?? 'Embed',
      headers: Map<String, String>.from(json['headers'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'playerUrl': playerUrl,
        'audioType': audioType,
        'serverType': serverType,
        'headers': headers,
      };

  @override
  String toString() => 'ScrapedPlayerSource(name: $name, type: $serverType, audio: $audioType)';
}

/// Detalhes do filme extraídos da página de origem
class ScrapedMovieDetails {
  final String title;
  final String pageUrl;
  final String synopsis;
  final String? year;
  final List<String> genres;
  final String? posterUrl;
  final List<ScrapedPlayerSource> players;

  const ScrapedMovieDetails({
    required this.title,
    required this.pageUrl,
    required this.synopsis,
    this.year,
    this.genres = const [],
    this.posterUrl,
    this.players = const [],
  });

  List<ScrapedPlayerSource> get dubladoPlayers =>
      players.where((p) => p.isDublado).toList();

  List<ScrapedPlayerSource> get legendadoPlayers =>
      players.where((p) => p.isLegendado).toList();

  factory ScrapedMovieDetails.fromJson(Map<String, dynamic> json) {
    return ScrapedMovieDetails(
      title: json['title'] ?? '',
      pageUrl: json['pageUrl'] ?? '',
      synopsis: json['synopsis'] ?? '',
      year: json['year']?.toString(),
      genres: List<String>.from(json['genres'] ?? []),
      posterUrl: json['posterUrl'],
      players: (json['players'] as List<dynamic>? ?? [])
          .map((p) => ScrapedPlayerSource.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'pageUrl': pageUrl,
        'synopsis': synopsis,
        'year': year,
        'genres': genres,
        'posterUrl': posterUrl,
        'players': players.map((p) => p.toJson()).toList(),
      };
}

/// Representação de stream de vídeo extraído pronto para o player
class ExtractedVideoStream {
  final String streamUrl;
  final String format; // 'hls', 'mp4', 'dash', 'embed'
  final Map<String, String> headers;
  final String quality;
  final bool isDirect;

  const ExtractedVideoStream({
    required this.streamUrl,
    required this.format,
    this.headers = const {},
    this.quality = '1080p',
    this.isDirect = true,
  });

  bool get isHls => format == 'hls' || streamUrl.contains('.m3u8');
  bool get isMp4 => format == 'mp4' || streamUrl.contains('.mp4');
  bool get isDash => format == 'dash' || streamUrl.contains('.mpd');

  Map<String, dynamic> toJson() => {
        'streamUrl': streamUrl,
        'format': format,
        'headers': headers,
        'quality': quality,
        'isDirect': isDirect,
      };

  @override
  String toString() => 'ExtractedVideoStream(url: $streamUrl, format: $format, quality: $quality)';
}
