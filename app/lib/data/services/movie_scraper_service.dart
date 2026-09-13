import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import '../models/scraper_models.dart';
import '../repositories/streaming_repository.dart';

/// Camada de Serviço de Scraping e Extração Profunda de Mídia
class MovieScraperService {
  static final MovieScraperService instance = MovieScraperService();

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const Map<String, String> defaultHeaders = {
    'User-Agent': defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  /// Provedores de busca configuráveis (com API ou HTML Scraping)
  final List<String> searchEndpoints = [
    'https://embedflix.top/search?q=',
  ];

  // =========================================================================
  // 1. BUSCA (searchMovies) COM NORMALIZAÇÃO E SELETORES DEFENSIVOS
  // =========================================================================

  /// Normalização de títulos: remove acentos, pontuações, caracteres especiais e espaços extras
  static String normalizeQuery(String query) {
    if (query.isEmpty) return '';
    var str = query.trim().toLowerCase();

    // Mapeamento de acentos e diacríticos latinos
    const withDiacritics = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const withoutDiacritics = 'aaaaaaeeeeiiiiooooouuuucn';
    for (int i = 0; i < withDiacritics.length; i++) {
      str = str.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }

    // Remove caracteres especiais exceto alfanuméricos e espaços
    str = str.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

    // Colapsa múltiplos espaços em um só
    return str.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Busca filmes tentando primeiro catálogo oficial TMDB PT-BR e acionando fallback para HTML
  Future<List<ScrapedMovieItem>> searchMovies(String query) async {
    final cleanQuery = normalizeQuery(query);
    if (cleanQuery.isEmpty) return [];

    debugPrint('[MovieScraper] 🔎 Buscando filmes para: "$cleanQuery" (original: "$query")');

    final results = <ScrapedMovieItem>[];

    // 1. Catálogo Oficial TMDB API em Português (Filmes reais com capas HD e ordenação por relevância)
    try {
      final tmdbUrl = Uri.parse(
        'https://api.themoviedb.org/3/search/movie?api_key=4e44d9029b1270a757cddc766a1bcb63&query=${Uri.encodeComponent(cleanQuery)}&language=pt-BR&include_adult=false',
      );
      final response = await _withTimeout(
        http.get(tmdbUrl, headers: {'Accept': 'application/json'}),
        timeout: const Duration(seconds: 4),
      );

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawResults = data['results'] as List<dynamic>? ?? [];
        final now = DateTime.now();

        // Filtra filmes reais (já lançados, com capa e votos)
        final filtered = rawResults.where((item) {
          final posterPath = item['poster_path'];
          if (posterPath == null || posterPath.toString().trim().isEmpty) return false;

          final releaseDateStr = item['release_date']?.toString() ?? '';
          if (releaseDateStr.isEmpty) return false;
          final relDate = DateTime.tryParse(releaseDateStr);
          if (relDate != null && relDate.isAfter(now)) {
            // Descarta filmes não lançados (futuro)
            return false;
          }

          final votes = (item['vote_count'] is num) ? (item['vote_count'] as num).toInt() : 0;
          final pop = (item['popularity'] is num) ? (item['popularity'] as num).toDouble() : 0.0;
          if (votes < 3 && pop < 3.0) return false;

          return true;
        }).toList();

        // Ordena por votos + popularidade
        final lowerQuery = cleanQuery.toLowerCase();
        filtered.sort((a, b) {
          final aTitle = (a['title'] ?? a['original_title'] ?? '').toString().toLowerCase();
          final bTitle = (b['title'] ?? b['original_title'] ?? '').toString().toLowerCase();
          final aExact = aTitle == lowerQuery;
          final bExact = bTitle == lowerQuery;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;

          final aVotes = (a['vote_count'] is num) ? (a['vote_count'] as num).toDouble() : 0.0;
          final bVotes = (b['vote_count'] is num) ? (b['vote_count'] as num).toDouble() : 0.0;
          final aPop = (a['popularity'] is num) ? (a['popularity'] as num).toDouble() : 0.0;
          final bPop = (b['popularity'] is num) ? (b['popularity'] as num).toDouble() : 0.0;
          return ((bVotes * 1.5) + (bPop * 3.0)).compareTo((aVotes * 1.5) + (aPop * 3.0));
        });

        final targetList = filtered.isNotEmpty ? filtered : rawResults;
        for (final item in targetList) {
          final id = item['id'];
          final title = item['title'] ?? item['original_title'] ?? '';
          final posterPath = item['poster_path'];
          final posterUrl = posterPath != null
              ? 'https://image.tmdb.org/t/p/w500$posterPath'
              : 'https://image.tmdb.org/t/p/w500/x0nvYzQpyJc5pdT9lMnkMuYAg0O.jpg';
          final releaseDate = item['release_date']?.toString() ?? '';
          final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;

          if (id != null && title.isNotEmpty) {
            results.add(
              ScrapedMovieItem(
                title: title,
                pageUrl: 'https://vidsrc.to/embed/movie/$id',
                posterUrl: posterUrl,
                audioType: 'Dublado',
                year: year,
                quality: '4K Ultra HD',
              ),
            );
          }
        }
        if (results.isNotEmpty) {
          debugPrint('[MovieScraper] ✅ Encontrados ${results.length} filmes reais via catálogo TMDB PT-BR');
          return results;
        }
      }
    } catch (_) {}

    // 2. Fallback para HTML Scraping defensivo
    for (final baseSearchUrl in searchEndpoints) {
      try {
        final targetUrl = '$baseSearchUrl${Uri.encodeComponent(cleanQuery)}';
        final response = await _withTimeout(
          http.get(
            Uri.parse(targetUrl),
            headers: {
              ...defaultHeaders,
              'Referer': targetUrl,
            },
          ),
          timeout: const Duration(seconds: 4),
        );

        if (response != null && response.statusCode == 200 && response.body.isNotEmpty) {
          final items = _parseMovieCardsFromHtml(response.body, targetUrl);
          if (items.isNotEmpty) {
            results.addAll(items);
            break;
          }
        }
      } catch (_) {}
    }

    debugPrint('[MovieScraper] 📊 Total de itens encontrados na busca: ${results.length}');
    return results;
  }

  /// Parser defensivo de cards HTML com múltiplos seletores CSS
  List<ScrapedMovieItem> _parseMovieCardsFromHtml(String html, String baseUrl) {
    final list = <ScrapedMovieItem>[];
    final doc = html_parser.parse(html);

    // Múltiplos seletores CSS defensivos para acomodar temas comuns de CMS de filmes
    const selectors = [
      'article.item',
      '.movie-item',
      '.film-item',
      '.card-filme',
      '.item-filme',
      '.movies-list .item',
      'article',
      '.poster',
      '.fl-item',
    ];

    List<Element> cards = [];
    for (final sel in selectors) {
      final found = doc.querySelectorAll(sel);
      if (found.isNotEmpty) {
        cards = found;
        break;
      }
    }

    final baseUri = Uri.parse(baseUrl);

    for (final card in cards) {
      try {
        // Extrai Link
        final aTag = card.querySelector('a[href]') ?? (card.localName == 'a' ? card : null);
        final rawHref = aTag?.attributes['href'];
        if (rawHref == null || rawHref.isEmpty) continue;
        final pageUrl = baseUri.resolve(rawHref).toString();

        // Extrai Título
        final titleElem = card.querySelector('.title, .entry-title, h2, h3, .movie-title, .film-name') ?? aTag;
        String title = titleElem?.attributes['title'] ?? titleElem?.text.trim() ?? '';
        if (title.isEmpty) {
          final img = card.querySelector('img');
          title = img?.attributes['alt'] ?? img?.attributes['title'] ?? '';
        }

        // Extrai Imagem/Capa
        final imgTag = card.querySelector('img');
        String posterUrl = imgTag?.attributes['src'] ??
            imgTag?.attributes['data-src'] ??
            imgTag?.attributes['data-lazy-src'] ??
            imgTag?.attributes['data-original'] ??
            '';
        if (posterUrl.isNotEmpty) {
          posterUrl = baseUri.resolve(posterUrl).toString();
        }

        // Extrai Áudio (Dublado / Legendado)
        String audioType = 'Dublado';
        final textBlock = card.text.toLowerCase();
        final badge = card.querySelector('.audio, .badge, .quality, .lang, .dub, .leg')?.text.toLowerCase() ?? '';
        if (badge.contains('leg') || textBlock.contains('legendado')) {
          audioType = 'Legendado';
        } else if (badge.contains('dub') || textBlock.contains('dublado')) {
          audioType = 'Dublado';
        } else if (textBlock.contains('nacional')) {
          audioType = 'Nacional';
        }

        // Extrai Ano
        final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(card.text);
        final year = yearMatch?.group(1);

        if (title.isNotEmpty && pageUrl.isNotEmpty) {
          list.add(
            ScrapedMovieItem(
              title: title,
              pageUrl: pageUrl,
              posterUrl: posterUrl,
              audioType: audioType,
              year: year,
            ),
          );
        }
      } catch (_) {}
    }

    return list;
  }

  // =========================================================================
  // 2. DETALHES E PLAYERS/VERSÕES (getMovieDetails)
  // =========================================================================

  /// Carrega a página do filme e extrai sinopse, ano, gêneros e os servidores disponíveis
  Future<ScrapedMovieDetails?> getMovieDetails(String movieUrl) async {
    try {
      final response = await _withTimeout(
        http.get(
          Uri.parse(movieUrl),
          headers: {
            ...defaultHeaders,
            'Referer': movieUrl,
          },
        ),
        timeout: const Duration(seconds: 6),
      );

      if (response == null || response.statusCode != 200 || response.body.isEmpty) {
        return null;
      }

      final doc = html_parser.parse(response.body);
      final baseUri = Uri.parse(movieUrl);

      // Título
      final title = doc.querySelector('h1, .entry-title, .movie-title, meta[property="og:title"]')?.text.trim() ??
          doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
          '';

      // Sinopse
      final synopsis = doc.querySelector('.sinopse, .synopsis, .description, .entry-content p, #sinopse, meta[name="description"]')?.text.trim() ??
          doc.querySelector('meta[property="og:description"]')?.attributes['content'] ??
          '';

      // Ano
      final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(doc.body?.text ?? '');
      final year = yearMatch?.group(1);

      // Gêneros
      final genres = <String>[];
      final genreElements = doc.querySelectorAll('.genres a, .generos a, a[rel="category tag"], .tags a');
      for (final g in genreElements) {
        final name = g.text.trim();
        if (name.isNotEmpty && !genres.contains(name)) {
          genres.add(name);
        }
      }

      // Poster
      final posterImg = doc.querySelector('.poster img, .cover img, meta[property="og:image"]');
      String posterUrl = posterImg?.attributes['src'] ??
          posterImg?.attributes['data-src'] ??
          posterImg?.attributes['content'] ??
          '';
      if (posterUrl.isNotEmpty) {
        posterUrl = baseUri.resolve(posterUrl).toString();
      }

      // Identificação dos players e servidores (Embeds, Streamtape, Mixdrop, Blogger, Filemoon)
      final players = <ScrapedPlayerSource>[];

      // 1. Procurar iframes
      final iframes = doc.querySelectorAll('iframe[src], iframe[data-src]');
      for (final iframe in iframes) {
        final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
        if (src != null && src.isNotEmpty && !src.contains('about:blank')) {
          final playerUri = baseUri.resolve(src).toString();
          final serverType = _categorizeServerType(playerUri);
          final audioType = _detectAudioContext(iframe, 'Dublado');

          players.add(
            ScrapedPlayerSource(
              name: '$serverType ($audioType)',
              playerUrl: playerUri,
              audioType: audioType,
              serverType: serverType,
              headers: {'Referer': movieUrl},
            ),
          );
        }
      }

      // 2. Procurar abas e botões com links de players (ex: data-url, data-player, data-embed)
      final buttons = doc.querySelectorAll('[data-url], [data-player], [data-embed], .play-btn[href]');
      for (final btn in buttons) {
        final target = btn.attributes['data-url'] ??
            btn.attributes['data-player'] ??
            btn.attributes['data-embed'] ??
            btn.attributes['href'];
        if (target != null && target.isNotEmpty && target.startsWith('http')) {
          final serverType = _categorizeServerType(target);
          final audioType = _detectAudioContext(btn, 'Dublado');

          players.add(
            ScrapedPlayerSource(
              name: '$serverType ($audioType)',
              playerUrl: target,
              audioType: audioType,
              serverType: serverType,
              headers: {'Referer': movieUrl},
            ),
          );
        }
      }

      return ScrapedMovieDetails(
        title: title,
        pageUrl: movieUrl,
        synopsis: synopsis,
        year: year,
        genres: genres,
        posterUrl: posterUrl,
        players: players,
      );
    } catch (e) {
      debugPrint('[MovieScraper] ⚠️ Erro ao obter detalhes de $movieUrl: $e');
      return null;
    }
  }

  /// Classifica o provedor de vídeo com base no domínio
  static String _categorizeServerType(String url) {
    final u = url.toLowerCase();
    if (u.contains('streamtape')) return 'Streamtape';
    if (u.contains('mixdrop')) return 'Mixdrop';
    if (u.contains('filemoon')) return 'Filemoon';
    if (u.contains('blogger.com') || u.contains('google.com')) return 'Blogger / Google';
    if (u.contains('warez')) return 'WarezCDN';
    if (u.contains('vidsrc')) return 'VidSrc';
    if (u.contains('vidlink')) return 'VidLink';
    if (u.contains('2embed')) return '2Embed';
    if (u.contains('smashystream')) return 'SmashyStream';
    if (u.contains('.m3u8')) return 'Direct HLS';
    if (u.contains('.mp4')) return 'Direct MP4';
    return 'Embed Player';
  }

  /// Detecta se o elemento pai ou texto próximo indica "Dublado" ou "Legendado"
  static String _detectAudioContext(Element elem, String defaultAudio) {
    var parent = elem.parent;
    int depth = 0;
    while (parent != null && depth < 4) {
      final text = parent.text.toLowerCase();
      if (text.contains('legendado') || text.contains('leg')) return 'Legendado';
      if (text.contains('dublado') || text.contains('dub')) return 'Dublado';
      parent = parent.parent;
      depth++;
    }
    return defaultAudio;
  }

  // =========================================================================
  // 3. EXTRAÇÃO PROFUNDA DE STREAMS (extractVideoStream)
  // =========================================================================

  /// Analisa página ou iframe de player procurando m3u8/mp4/mpd direto,
  /// analisando tags video, configs JavaScript e seguindo redirecionamentos mantendo cookies.
  Future<ExtractedVideoStream?> extractVideoStream(String playerUrl) async {
    final safeUrl = playerUrl.trim();
    if (safeUrl.isEmpty) return null;

    debugPrint('[MovieScraper] 🕵️ Extração profunda de vídeo iniciada para: $safeUrl');

    // Se a URL já for um link direto de streaming
    if (safeUrl.contains('.m3u8')) {
      return ExtractedVideoStream(
        streamUrl: safeUrl,
        format: 'hls',
        headers: {'Referer': safeUrl, 'User-Agent': defaultUserAgent},
        quality: '1080p',
      );
    }
    if (safeUrl.contains('.mp4')) {
      return ExtractedVideoStream(
        streamUrl: safeUrl,
        format: 'mp4',
        headers: {'Referer': safeUrl, 'User-Agent': defaultUserAgent},
        quality: '1080p',
      );
    }

    // Requisição HTTP com resolução de redirecionamentos e captura de cookies
    final cookieJar = <String, String>{};
    String currentUrl = safeUrl;
    String htmlBody = '';

    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.userAgent = defaultUserAgent;

      int redirectCount = 0;
      while (redirectCount < 5) {
        final req = await client.getUrl(Uri.parse(currentUrl));
        req.followRedirects = false;
        req.headers.set('User-Agent', defaultUserAgent);
        req.headers.set('Referer', currentUrl);
        req.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');

        // Enviar cookies acumulados
        if (cookieJar.isNotEmpty) {
          final cookieHeader = cookieJar.entries.map((e) => '${e.key}=${e.value}').join('; ');
          req.headers.set('Cookie', cookieHeader);
        }

        final res = await req.close().timeout(const Duration(seconds: 5));

        // Armazenar cookies recebidos
        for (final cookie in res.cookies) {
          cookieJar[cookie.name] = cookie.value;
        }

        if (res.isRedirect) {
          final location = res.headers.value(HttpHeaders.locationHeader);
          if (location != null && location.isNotEmpty) {
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            await res.drain();
            redirectCount++;
            continue;
          }
        }

        if (res.statusCode == 200) {
          final rawBytes = await res.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
          htmlBody = utf8.decode(rawBytes, allowMalformed: true);
        }
        break;
      }
      client.close();
    } catch (e) {
      debugPrint('[MovieScraper] ⚠️ Erro na requisição HTTP ao player: $e');
    }

    if (htmlBody.isEmpty) return null;

    final requestHeaders = <String, String>{
      'User-Agent': defaultUserAgent,
      'Referer': currentUrl,
      'Origin': Uri.parse(currentUrl).origin,
    };
    if (cookieJar.isNotEmpty) {
      requestHeaders['Cookie'] = cookieJar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }

    // 3.1 Busca por tags <video src="..."> e atributos data-src, data-video-src, data-url
    final doc = html_parser.parse(htmlBody);
    final videoElement = doc.querySelector('video');
    if (videoElement != null) {
      final src = videoElement.attributes['src'] ??
          videoElement.attributes['data-src'] ??
          videoElement.attributes['data-video-src'] ??
          videoElement.attributes['data-url'];
      if (src != null && src.isNotEmpty && (src.contains('.m3u8') || src.contains('.mp4') || src.contains('.mpd'))) {
        final resolved = Uri.parse(currentUrl).resolve(src).toString();
        return ExtractedVideoStream(
          streamUrl: resolved,
          format: resolved.contains('.m3u8') ? 'hls' : (resolved.contains('.mpd') ? 'dash' : 'mp4'),
          headers: requestHeaders,
        );
      }

      final sourceElem = videoElement.querySelector('source');
      if (sourceElem != null) {
        final sSrc = sourceElem.attributes['src'];
        if (sSrc != null && sSrc.isNotEmpty) {
          final resolved = Uri.parse(currentUrl).resolve(sSrc).toString();
          return ExtractedVideoStream(
            streamUrl: resolved,
            format: resolved.contains('.m3u8') ? 'hls' : 'mp4',
            headers: requestHeaders,
          );
        }
      }
    }

    // 3.2 Busca por variáveis de configuração JavaScript (sources: [...], file: "...", VIDEO_CONFIG)
    final scriptConfigPattern = RegExp(
      r'''(?:sources|file|src|stream_url|play_url)\s*[:=]\s*["'](https?://[^"']+\.(?:m3u8|mp4|mpd)[^"']*)["']''',
      caseSensitive: false,
    );
    final scriptMatch = scriptConfigPattern.firstMatch(htmlBody);
    if (scriptMatch != null) {
      final direct = scriptMatch.group(1)!;
      return ExtractedVideoStream(
        streamUrl: direct,
        format: direct.contains('.m3u8') ? 'hls' : (direct.contains('.mpd') ? 'dash' : 'mp4'),
        headers: requestHeaders,
      );
    }

    // 3.3 Expressões regulares diretas para capturar URLs .m3u8 / .mp4 / .mpd
    final m3u8Regex = RegExp(
      r'''https?://[^\s<>"']+?\.(?:m3u8)(?:\?[^\s<>"']*)?''',
      caseSensitive: false,
    );
    final m3u8Match = m3u8Regex.firstMatch(htmlBody);
    if (m3u8Match != null) {
      return ExtractedVideoStream(
        streamUrl: m3u8Match.group(0)!,
        format: 'hls',
        headers: requestHeaders,
      );
    }

    final mp4Regex = RegExp(
      r'''https?://[^\s<>"']+?\.(?:mp4)(?:\?[^\s<>"']*)?''',
      caseSensitive: false,
    );
    final mp4Match = mp4Regex.firstMatch(htmlBody);
    if (mp4Match != null) {
      return ExtractedVideoStream(
        streamUrl: mp4Match.group(0)!,
        format: 'mp4',
        headers: requestHeaders,
      );
    }

    // 3.4 Suporte a links Blogger / GoogleVideo
    final bloggerPattern = RegExp(r'https://www\.blogger\.com/video\.g\?token=([A-Za-z0-9_-]+)');
    final bloggerMatch = bloggerPattern.firstMatch(htmlBody);
    if (bloggerMatch != null) {
      return ExtractedVideoStream(
        streamUrl: bloggerMatch.group(0)!,
        format: 'mp4',
        headers: requestHeaders,
      );
    }

    // Se não encontrou link direto de vídeo mas é um player embed navegável
    return ExtractedVideoStream(
      streamUrl: currentUrl,
      format: 'embed',
      headers: requestHeaders,
      isDirect: false,
    );
  }

  // =========================================================================
  // 4. RESOLUÇÃO COMPLETA DE FONTES (Usada pelo StreamingRepository)
  // =========================================================================

  /// Resolve todos os streams disponíveis diretamente no aparelho usando
  /// os provedores ativos e testados (Torrentio, VidSrc.to, VidLink, 2Embed, etc.)
  Future<VideoSourceResult> resolveMovieStreams({
    required String title,
    required int tmdbId,
    String? imdbId,
    String? releaseYear,
  }) async {
    String? effectiveImdbId = imdbId;

    // Se o IMDB ID não foi fornecido, busca no TMDB
    if (effectiveImdbId == null ||
        effectiveImdbId.trim().isEmpty ||
        effectiveImdbId.trim().toLowerCase() == 'n/a' ||
        effectiveImdbId.trim().toLowerCase() == 'null') {
      try {
        final res = await _withTimeout(
          http.get(
            Uri.parse('https://api.themoviedb.org/3/movie/$tmdbId/external_ids?api_key=4e44d9029b1270a757cddc766a1bcb63'),
            headers: {'Accept': 'application/json'},
          ),
          timeout: const Duration(seconds: 2),
        );
        if (res != null && res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data['imdb_id'] != null && data['imdb_id'].toString().isNotEmpty) {
            effectiveImdbId = data['imdb_id'].toString();
          }
        }
      } catch (_) {}
    }

    debugPrint('[MovieScraper] 🎬 Resolvendo streams para "$title" (TMDB: $tmdbId, IMDB: ${effectiveImdbId ?? "N/A"})');

    final results = await Future.wait([
      _getStremioStreams(effectiveImdbId, tmdbId),
      _getResolvedEmbedStreams(tmdbId, effectiveImdbId),
    ]);

    final stremioStreams = results[0];
    final embedStreams = results[1];

    final allServers = <StreamingServer>[
      ...stremioStreams,
      ...embedStreams,
    ];

    final directServers = allServers.where((s) => s.type == 'direct').toList();
    final embedOnlyServers = allServers.where((s) => s.type == 'embed').toList();

    // Servidores diretos (.m3u8/.mp4) primeiro, depois embeds como fallback
    final sortedServers = [...directServers, ...embedOnlyServers];

    debugPrint('[MovieScraper] 📊 Total de servidores encontrados: ${sortedServers.length} (${directServers.length} diretos, ${embedOnlyServers.length} embeds)');

    final defaultPlayUrl = sortedServers.isNotEmpty ? sortedServers.first.url : null;
    final defaultType = sortedServers.isNotEmpty ? sortedServers.first.type : 'direct';

    return VideoSourceResult(
      success: sortedServers.isNotEmpty,
      title: title,
      videoUrl: defaultPlayUrl,
      quality: '1080p Ultra HD',
      type: defaultType,
      provider: 'Movixs Native Scraper',
      servers: sortedServers,
    );
  }

  /// Resolve streams para Séries de TV por temporada e episódio
  /// VidSrc.to (#1), VidLink, 2Embed, Rivestream, MultiEmbed, SmashyStream, etc.
  Future<VideoSourceResult> resolveSeriesStreams({
    required String title,
    required int tmdbId,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    String? effectiveImdbId = imdbId;

    if (effectiveImdbId == null ||
        effectiveImdbId.trim().isEmpty ||
        effectiveImdbId.trim().toLowerCase() == 'n/a' ||
        effectiveImdbId.trim().toLowerCase() == 'null') {
      try {
        final res = await _withTimeout(
          http.get(
            Uri.parse('https://api.themoviedb.org/3/tv/$tmdbId/external_ids?api_key=4e44d9029b1270a757cddc766a1bcb63'),
            headers: {'Accept': 'application/json'},
          ),
          timeout: const Duration(seconds: 2),
        );
        if (res != null && res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data['imdb_id'] != null && data['imdb_id'].toString().isNotEmpty) {
            effectiveImdbId = data['imdb_id'].toString();
          }
        }
      } catch (_) {}
    }

    debugPrint('[MovieScraper] 🎬 Resolvendo streams para Série "$title" S${season}E$episode (TMDB: $tmdbId, IMDB: ${effectiveImdbId ?? "N/A"})');

    final results = await Future.wait([
      _getSeriesStremioStreams(effectiveImdbId, tmdbId, season, episode),
      _getSeriesEmbedStreams(tmdbId, effectiveImdbId, season, episode),
    ]);

    final stremioStreams = results[0];
    final embedStreams = results[1];

    final allServers = <StreamingServer>[
      ...stremioStreams,
      ...embedStreams,
    ];

    final directServers = allServers.where((s) => s.type == 'direct').toList();
    final embedOnlyServers = allServers.where((s) => s.type == 'embed').toList();

    // Servidores diretos (.m3u8/.mp4) primeiro, depois embeds
    final sortedServers = [...directServers, ...embedOnlyServers];

    debugPrint('[MovieScraper] 📊 Total de servidores de série encontrados: ${sortedServers.length} (${directServers.length} diretos, ${embedOnlyServers.length} embeds)');

    final defaultPlayUrl = sortedServers.isNotEmpty ? sortedServers.first.url : null;
    final defaultType = sortedServers.isNotEmpty ? sortedServers.first.type : 'direct';

    return VideoSourceResult(
      success: sortedServers.isNotEmpty,
      title: '$title - T$season:E$episode',
      videoUrl: defaultPlayUrl,
      quality: '1080p Ultra HD',
      type: defaultType,
      provider: 'Movixs Series Resolver',
      servers: sortedServers,
    );
  }

  Future<List<StreamingServer>> _getSeriesStremioStreams(String? imdbId, int tmdbId, int season, int episode) async {
    final streams = <StreamingServer>[];
    if (imdbId == null || imdbId.isEmpty) return streams;

    final endpoints = [
      {
        'name': '🌐 Torrentio Stream',
        'lang': 'Multi',
        'url': 'https://torrentio.strem.fun/stream/series/$imdbId:$season:$episode.json',
      },
    ];

    await Future.wait(
      endpoints.map((ep) async {
        try {
          final res = await _withTimeout(
            http.get(
              Uri.parse(ep['url']!),
              headers: defaultHeaders,
            ),
            timeout: const Duration(seconds: 4),
          );

          if (res != null && res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data['streams'] is List) {
              for (final s in data['streams']) {
                final streamUrl = s['url']?.toString();
                if (streamUrl != null && streamUrl.startsWith('http')) {
                  final isHls = streamUrl.contains('.m3u8');
                  final isMp4 = streamUrl.contains('.mp4');

                  final rawTitle = s['title']?.toString() ?? '';
                  final lowerTitle = rawTitle.toLowerCase();
                  final isPt = lowerTitle.contains('dublado') ||
                      lowerTitle.contains('pt-br') ||
                      lowerTitle.contains('pt_br') ||
                      lowerTitle.contains('portug') ||
                      lowerTitle.contains('dual audio') ||
                      lowerTitle.contains('dual áudio') ||
                      lowerTitle.contains('nacional');

                  final displayName = isPt
                      ? '🇧🇷 ${ep['name']} [Dublado] (${rawTitle.isNotEmpty ? rawTitle.split('\n').first : 'Stream'})'
                      : '${ep['name']} (${rawTitle.isNotEmpty ? rawTitle.split('\n').first : 'Stream'})';
                  final streamLang = isPt ? 'Dublado' : ep['lang']!;

                  streams.add(
                    StreamingServer(
                      name: displayName,
                      url: streamUrl,
                      type: 'direct',
                      lang: streamLang,
                      format: isHls ? 'hls' : (isMp4 ? 'mp4' : 'direct'),
                      quality: s['name']?.toString() ?? '1080p HD',
                      source: 'stremio',
                    ),
                  );
                }
              }
            }
          }
        } catch (_) {}
      }),
    );

    return streams;
  }

  Future<List<StreamingServer>> _getSeriesEmbedStreams(int tmdbId, String? imdbId, int season, int episode) async {
    final streams = <StreamingServer>[];
    final imdb = (imdbId != null && imdbId.isNotEmpty) ? imdbId : null;

    final embedCandidates = [
      {
        'name': '🌐 VidSrc.to (Ultra HD)',
        'url': 'https://vidsrc.to/embed/tv/$tmdbId/$season/$episode',
        'lang': 'Multi',
      },
      if (imdb != null) ...[
        {
          'name': '🌐 VidSrc.me (Multi-Server)',
          'url': 'https://vidsrc.me/embed/tv?imdb=$imdb&season=$season&episode=$episode',
          'lang': 'Multi',
        },
        {
          'name': '🌐 VidSrc.pm (HD)',
          'url': 'https://vidsrc.pm/embed/tv?imdb=$imdb&season=$season&episode=$episode',
          'lang': 'Multi',
        },
      ],
      {
        'name': '🌐 VidLink Player (Áudio PT-BR / Multi)',
        'url': 'https://vidlink.pro/tv/$tmdbId/$season/$episode?multiLang=true&selectedLanguage=portuguese&sub_lang=pt',
        'lang': 'Dublado / Multi',
      },
      {
        'name': '🌐 2Embed Fast',
        'url': 'https://www.2embed.cc/embedtv/$tmdbId&s=$season&e=$episode',
        'lang': 'Multi',
      },
      {
        'name': '🌐 Rivestream Player',
        'url': 'https://rivestream.live/embed?type=series&id=$tmdbId&season=$season&episode=$episode',
        'lang': 'Multi',
      },
      {
        'name': '🌐 MultiEmbed (Legendas PT-BR)',
        'url': 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1&s=$season&e=$episode&sub_lang=pt',
        'lang': 'Multi',
      },
      {
        'name': '🌐 SmashyStream HD',
        'url': 'https://player.smashystream.com/tv/$tmdbId?s=$season&e=$episode',
        'lang': 'Multi',
      },
    ];

    for (final cand in embedCandidates) {
      streams.add(
        StreamingServer(
          name: cand['name']!,
          url: cand['url']!,
          type: 'embed',
          lang: cand['lang']!,
          quality: cand['name']!.contains('Ultra HD') ? '1080p Ultra HD' : '1080p HD',
          source: 'embed-series',
        ),
      );
    }

    return streams;
  }

  /// Addon Stremio Torrentio HTTP
  Future<List<StreamingServer>> _getStremioStreams(String? imdbId, int tmdbId) async {
    final streams = <StreamingServer>[];
    final id = (imdbId != null && imdbId.isNotEmpty) ? imdbId : 'tmdb:$tmdbId';

    final endpoints = [
      {
        'name': '🌐 Torrentio Stream',
        'lang': 'Multi',
        'url': 'https://torrentio.strem.fun/stream/movie/$id.json',
      },
    ];

    await Future.wait(
      endpoints.map((ep) async {
        try {
          final res = await _withTimeout(
            http.get(
              Uri.parse(ep['url']!),
              headers: defaultHeaders,
            ),
            timeout: const Duration(seconds: 4),
          );

          if (res != null && res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data['streams'] is List) {
              for (final s in data['streams']) {
                final streamUrl = s['url']?.toString();
                if (streamUrl != null && streamUrl.startsWith('http')) {
                  final isHls = streamUrl.contains('.m3u8');
                  final isMp4 = streamUrl.contains('.mp4');

                  final rawTitle = s['title']?.toString() ?? '';
                  final lowerTitle = rawTitle.toLowerCase();
                  final isPt = lowerTitle.contains('dublado') ||
                      lowerTitle.contains('pt-br') ||
                      lowerTitle.contains('pt_br') ||
                      lowerTitle.contains('portug') ||
                      lowerTitle.contains('dual audio') ||
                      lowerTitle.contains('dual áudio') ||
                      lowerTitle.contains('nacional');

                  final displayName = isPt
                      ? '🇧🇷 ${ep['name']} [Dublado] (${rawTitle.isNotEmpty ? rawTitle.split('\n').first : 'Stream'})'
                      : '${ep['name']} (${rawTitle.isNotEmpty ? rawTitle.split('\n').first : 'Stream'})';
                  final streamLang = isPt ? 'Dublado' : ep['lang']!;

                  streams.add(
                    StreamingServer(
                      name: displayName,
                      url: streamUrl,
                      type: 'direct',
                      lang: streamLang,
                      format: isHls ? 'hls' : (isMp4 ? 'mp4' : 'direct'),
                      quality: s['name']?.toString() ?? '1080p HD',
                      source: 'stremio',
                    ),
                  );
                }
              }
            }
          }
        } catch (_) {}
      }),
    );

    return streams;
  }

  /// Provedores de embed ativos e verificados em tempo real
  Future<List<StreamingServer>> _getResolvedEmbedStreams(int tmdbId, String? imdbId) async {
    final streams = <StreamingServer>[];
    final imdb = (imdbId != null && imdbId.isNotEmpty) ? imdbId : null;

    final embedCandidates = [
      {
        'name': '🌐 VidSrc.to (Ultra HD)',
        'url': 'https://vidsrc.to/embed/movie/$tmdbId',
        'lang': 'Multi',
      },
      if (imdb != null) ...[
        {
          'name': '🌐 VidSrc.me (Multi-Server)',
          'url': 'https://vidsrc.me/embed/movie?imdb=$imdb',
          'lang': 'Multi',
        },
        {
          'name': '🌐 VidSrc.pm (HD)',
          'url': 'https://vidsrc.pm/embed/movie?imdb=$imdb',
          'lang': 'Multi',
        },
      ],
      {
        'name': '🌐 VidLink Player (Áudio PT-BR / Multi)',
        'url': 'https://vidlink.pro/movie/$tmdbId?multiLang=true&selectedLanguage=portuguese&sub_lang=pt',
        'lang': 'Dublado / Multi',
      },
      {
        'name': '🌐 2Embed Fast',
        'url': 'https://www.2embed.cc/embed/$tmdbId',
        'lang': 'Multi',
      },
      {
        'name': '🌐 Rivestream Player',
        'url': 'https://rivestream.live/embed?type=movie&id=$tmdbId',
        'lang': 'Multi',
      },
      {
        'name': '🌐 MultiEmbed (Legendas PT-BR)',
        'url': 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1&sub_lang=pt',
        'lang': 'Multi',
      },
      {
        'name': '🌐 SmashyStream HD',
        'url': 'https://player.smashystream.com/movie/$tmdbId',
        'lang': 'Multi',
      },
    ];

    await Future.wait(
      embedCandidates.map((embed) async {
        final embedUrl = embed['url']!;
        final name = embed['name']!;
        final lang = embed['lang']!;

        // Tenta extração profunda do stream
        final extracted = await extractVideoStream(embedUrl);

        if (extracted != null && extracted.isDirect) {
          streams.add(
            StreamingServer(
              name: '$name ✅',
              url: extracted.streamUrl,
              type: 'direct',
              format: extracted.format,
              lang: lang,
              quality: extracted.quality,
              source: 'embed-resolved',
            ),
          );
        } else {
          // Mantém como embed caso precise de WebView
          streams.add(
            StreamingServer(
              name: name,
              url: embedUrl,
              type: 'embed',
              format: 'embed',
              lang: lang,
              quality: '1080p HD',
              source: 'embed-webview',
            ),
          );
        }
      }),
    );

    // Prioriza estritamente o VidSrc.to no topo da lista
    streams.sort((a, b) {
      final aIsVidSrcTo = a.url.contains('vidsrc.to');
      final bIsVidSrcTo = b.url.contains('vidsrc.to');
      if (aIsVidSrcTo && !bIsVidSrcTo) return -1;
      if (!aIsVidSrcTo && bIsVidSrcTo) return 1;
      return 0;
    });

    return streams;
  }

  Future<T?> _withTimeout<T>(Future<T> future, {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      return await future.timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}
