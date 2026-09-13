import 'package:flutter/foundation.dart';
import '../services/movie_scraper_service.dart';

class StreamingServer {
  final String name;
  final String url;
  final String type; // sempre 'direct' agora (backend resolve .m3u8)
  final String lang; // 'PT-BR' ou 'Multi'
  final String? format; // 'hls' ou 'mp4'
  final String? quality;
  final String? source; // 'movie-web', 'consumet', 'stremio', 'embed-resolved'

  StreamingServer({
    required this.name,
    required this.url,
    required this.type,
    this.lang = 'Multi',
    this.format,
    this.quality,
    this.source,
  });

  factory StreamingServer.fromJson(Map<String, dynamic> json) {
    return StreamingServer(
      name: json['name'] ?? 'Servidor',
      url: json['url'] ?? '',
      type: json['type'] ?? 'direct',
      lang: json['lang'] ?? 'Multi',
      format: json['format'],
      quality: json['quality'],
      source: json['source'],
    );
  }

  /// Verifica se a URL é válida para reprodução
  bool get isPlayable {
    return url.isNotEmpty;
  }
}

class VideoSourceResult {
  final bool success;
  final String title;
  final String? videoUrl;
  final String quality;
  final String type;
  final String provider;
  final List<StreamingServer> servers;
  final List<dynamic> subtitles;

  VideoSourceResult({
    required this.success,
    required this.title,
    this.videoUrl,
    required this.quality,
    required this.type,
    required this.provider,
    this.servers = const [],
    this.subtitles = const [],
  });

  factory VideoSourceResult.fromJson(Map<String, dynamic> json, int tmdbId) {
    List<StreamingServer> parsedServers = [];
    if (json['servers'] != null && json['servers'] is List) {
      parsedServers = (json['servers'] as List)
          .map((s) => StreamingServer.fromJson(Map<String, dynamic>.from(s)))
          .where((s) => s.url.isNotEmpty && !s.url.contains('test-streams.mux.dev'))
          .toList();
    }

    // Subtitles
    List<dynamic> subs = [];
    if (json['subtitles'] != null && json['subtitles'] is List) {
      subs = json['subtitles'] as List;
    }

    // URL principal — o backend já retorna .m3u8/.mp4 direto
    final rawVideoUrl = json['videoUrl']?.toString() ?? '';
    final validVideoUrl = rawVideoUrl.isNotEmpty && !rawVideoUrl.contains('test-streams.mux.dev')
        ? rawVideoUrl
        : (parsedServers.isNotEmpty ? parsedServers.first.url : null);

    return VideoSourceResult(
      success: json['success'] ?? false,
      title: json['title'] ?? '',
      videoUrl: validVideoUrl,
      quality: json['quality'] ?? '1080p',
      type: json['type'] ?? 'direct',
      provider: json['provider'] ?? 'Movixs M3U8 Resolver',
      servers: parsedServers,
      subtitles: subs,
    );
  }

  /// Retorna true se temos pelo menos um stream disponível
  bool get hasPlayableStreams =>
      (videoUrl != null && videoUrl!.isNotEmpty) || servers.isNotEmpty;
}

class StreamingRepository {
  /// Extrai streams diretamente através do resolvedor nativo com VidSrc.to e servidores verificados
  Future<VideoSourceResult> extractStream({
    required String title,
    required int tmdbId,
    String? imdbId,
  }) async {
    try {
      final result = await MovieScraperService.instance.resolveMovieStreams(
        title: title,
        tmdbId: tmdbId,
        imdbId: imdbId,
      );

      if (result.hasPlayableStreams || result.servers.isNotEmpty) {
        return result;
      }
    } catch (e) {
      debugPrint('Erro no scraper nativo de streams: $e');
    }

    // Fallback vazio
    return VideoSourceResult(
      success: false,
      title: title,
      videoUrl: null,
      quality: '1080p',
      type: 'direct',
      provider: 'Movixs (Offline)',
    );
  }

  /// Extrai streams para Séries de TV por temporada e episódio
  Future<VideoSourceResult> extractSeriesStream({
    required String title,
    required int tmdbId,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    try {
      final result = await MovieScraperService.instance.resolveSeriesStreams(
        title: title,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        imdbId: imdbId,
      );

      if (result.hasPlayableStreams || result.servers.isNotEmpty) {
        return result;
      }
    } catch (e) {
      debugPrint('Erro no scraper nativo de séries: $e');
    }

    // Fallback vazio
    return VideoSourceResult(
      success: false,
      title: '$title - T$season:E$episode',
      videoUrl: null,
      quality: '1080p',
      type: 'direct',
      provider: 'Movixs (Offline)',
    );
  }
}
