import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/superflix_stream.dart';

class SuperFlixService {
  static const String baseUrl = 'https://superflixapi.top';
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static final SuperFlixService instance = SuperFlixService();

  final http.Client _client;

  SuperFlixService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get defaultHeaders => {
        'User-Agent': desktopUserAgent,
        'Referer': '$baseUrl/',
        'Origin': baseUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
      };

  /// Gera a URL oficial correspondente na SuperFlix
  String buildPlayerUrl({
    required int tmdbId,
    int? season,
    int? episode,
  }) {
    if (season != null && episode != null) {
      return '$baseUrl/serie/$tmdbId/$season/$episode';
    }
    return '$baseUrl/filme/$tmdbId';
  }

  /// Extrai fontes de stream a partir da URL do player da SuperFlix
  Future<List<SuperFlixStreamResult>> extractStreamSources(String playerUrl) async {
    final List<SuperFlixStreamResult> results = [];
    final safeUrl = playerUrl.trim();

    debugPrint('[SuperFlixService] 🔍 Extraindo streams de: $safeUrl');

    String htmlBody = '';
    try {
      final response = await _client
          .get(
            Uri.parse(safeUrl),
            headers: defaultHeaders,
          )
          .timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        htmlBody = response.body;
      } else {
        debugPrint(
            '[SuperFlixService] ⚠️ Resposta com status ${response.statusCode} para $safeUrl');
      }
    } catch (e) {
      debugPrint('[SuperFlixService] ⚠️ Erro na requisição HTTP: $e');
    }

    if (htmlBody.isNotEmpty) {
      final document = html_parser.parse(htmlBody);

      // 1. Procurar abas / botões de áudio (Dublado vs Legendado)
      final audioBlocks = _extractAudioSections(document);

      for (final block in audioBlocks) {
        final audioType = block.audioType;
        final directStreams = _findDirectStreamsInHtml(block.htmlContent);

        for (final streamUrl in directStreams) {
          results.add(
            SuperFlixStreamResult(
              url: streamUrl,
              audioType: audioType,
              isDirectStream: true,
              headers: defaultHeaders,
              serverName: 'SuperFlix Direto ($audioType)',
            ),
          );
        }

        for (final embedUrl in block.embedUrls) {
          // Tenta extrair stream direto do iframe interno
          final innerStream = await _resolveInnerEmbed(embedUrl);
          if (innerStream != null) {
            results.add(
              SuperFlixStreamResult(
                url: innerStream,
                audioType: audioType,
                isDirectStream: true,
                headers: {
                  ...defaultHeaders,
                  'Referer': embedUrl,
                },
                serverName: 'SuperFlix Stream ($audioType)',
              ),
            );
          }

          results.add(
            SuperFlixStreamResult(
              url: embedUrl,
              audioType: audioType,
              isDirectStream: false,
              headers: defaultHeaders,
              serverName: 'SuperFlix Embed ($audioType)',
            ),
          );
        }
      }

      // 2. Busca global no documento caso as seções não tenham retornado tudo
      final globalDirects = _findDirectStreamsInHtml(htmlBody);
      for (final directUrl in globalDirects) {
        if (!results.any((r) => r.url == directUrl)) {
          final audioType = _inferAudioType(directUrl, htmlBody);
          results.add(
            SuperFlixStreamResult(
              url: directUrl,
              audioType: audioType,
              isDirectStream: true,
              headers: defaultHeaders,
              serverName: 'SuperFlix Direto ($audioType)',
            ),
          );
        }
      }

      // 3. Procura iframes gerais no documento
      final iframes = document.querySelectorAll('iframe');
      for (final iframe in iframes) {
        final src = iframe.attributes['src'] ??
            iframe.attributes['data-src'] ??
            iframe.attributes['data-video'];
        if (src != null && src.trim().isNotEmpty) {
          final absoluteSrc = _normalizeUrl(src.trim(), safeUrl);
          if (!results.any((r) => r.url == absoluteSrc)) {
            final audioType = _inferAudioType(absoluteSrc, iframe.outerHtml);
            results.add(
              SuperFlixStreamResult(
                url: absoluteSrc,
                audioType: audioType,
                isDirectStream: false,
                headers: defaultHeaders,
                serverName: 'SuperFlix Player Embed ($audioType)',
              ),
            );
          }
        }
      }
    }

    // 4. Garantir fallbacks caso a extração direta seja bloqueada por proteções dinâmicas
    if (!results.any((r) => r.audioType == 'Dublado')) {
      results.add(
        SuperFlixStreamResult(
          url: safeUrl,
          audioType: 'Dublado',
          isDirectStream: false,
          headers: defaultHeaders,
          serverName: 'SuperFlix Player Oficial (Dublado)',
        ),
      );
    }

    if (!results.any((r) => r.audioType == 'Legendado')) {
      results.add(
        SuperFlixStreamResult(
          url: safeUrl.contains('?')
              ? '$safeUrl&audio=legendado'
              : '$safeUrl?audio=legendado',
          audioType: 'Legendado',
          isDirectStream: false,
          headers: defaultHeaders,
          serverName: 'SuperFlix Player Oficial (Legendado)',
        ),
      );
    }

    debugPrint(
        '[SuperFlixService] ✅ Extração concluída. Total de streams: ${results.length} (${results.where((r) => r.isDirectStream).length} diretos, ${results.where((r) => !r.isDirectStream).length} embeds)');

    return results;
  }

  /// Extrai seções específicas de Dublado / Legendado do HTML
  List<_AudioSection> _extractAudioSections(Document document) {
    final List<_AudioSection> sections = [];

    // Procura botões, abas ou contêineres com indicação de áudio
    final elements = document.querySelectorAll(
      '[data-audio], .audio-tab, .tab-pane, .player-option, [class*="dublado"], [class*="legendado"]',
    );

    for (final el in elements) {
      final audioAttr = el.attributes['data-audio'] ?? '';
      final text = '${el.text} $audioAttr'.toLowerCase();
      String audioType = 'Dublado';
      if (text.contains('legendad') || text.contains('leg')) {
        audioType = 'Legendado';
      }

      final embedUrls = <String>[];
      for (final ifr in el.querySelectorAll('iframe')) {
        final src = ifr.attributes['src'] ?? ifr.attributes['data-src'];
        if (src != null && src.isNotEmpty) {
          embedUrls.add(_normalizeUrl(src, baseUrl));
        }
      }

      sections.add(
        _AudioSection(
          audioType: audioType,
          htmlContent: el.innerHtml,
          embedUrls: embedUrls,
        ),
      );
    }

    return sections;
  }

  /// Detecta URLs diretas de stream com extensões .m3u8 ou .mp4
  List<String> _findDirectStreamsInHtml(String html) {
    final streams = <String>{};

    // 1. Regex para .m3u8 (HLS)
    final m3u8Regex = RegExp(
      r'''https?://[^\s<>"'\\]+?\.(?:m3u8)(?:\?[^\s<>"'\\]*)?''',
      caseSensitive: false,
    );
    for (final match in m3u8Regex.allMatches(html)) {
      final url = match.group(0);
      if (url != null && !url.contains('test-streams.mux.dev')) {
        streams.add(url.replaceAll(r'\/', '/'));
      }
    }

    // 2. Regex para .mp4
    final mp4Regex = RegExp(
      r'''https?://[^\s<>"'\\]+?\.(?:mp4)(?:\?[^\s<>"'\\]*)?''',
      caseSensitive: false,
    );
    for (final match in mp4Regex.allMatches(html)) {
      final url = match.group(0);
      if (url != null) {
        streams.add(url.replaceAll(r'\/', '/'));
      }
    }

    // 3. Atributos em tags <video> e <source>
    final document = html_parser.parse(html);
    for (final video in document.querySelectorAll('video, source')) {
      final src = video.attributes['src'] ??
          video.attributes['data-src'] ??
          video.attributes['data-video'];
      if (src != null &&
          (src.contains('.m3u8') || src.contains('.mp4'))) {
        streams.add(_normalizeUrl(src, baseUrl));
      }
    }

    // 4. JSONs embutidos em <script> (file: "...", sources: [...])
    final jsonMediaRegex = RegExp(
      r'''(?:file|src|source|play_url|stream_url)\s*[:=]\s*["'](https?:\\?/\\?/[^"']+\.(?:m3u8|mp4)[^"']*)["']''',
      caseSensitive: false,
    );
    for (final match in jsonMediaRegex.allMatches(html)) {
      final url = match.group(1);
      if (url != null) {
        streams.add(url.replaceAll(r'\/', '/'));
      }
    }

    return streams.toList();
  }

  /// Tenta resolver a página de um iframe interno para extrair o stream .m3u8/.mp4
  Future<String?> _resolveInnerEmbed(String embedUrl) async {
    try {
      final response = await _client
          .get(
            Uri.parse(embedUrl),
            headers: {
              ...defaultHeaders,
              'Referer': baseUrl,
            },
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final streams = _findDirectStreamsInHtml(response.body);
        if (streams.isNotEmpty) {
          return streams.first;
        }
      }
    } catch (_) {}
    return null;
  }

  String _inferAudioType(String url, String context) {
    final combined = '$url $context'.toLowerCase();
    if (combined.contains('leg') ||
        combined.contains('legendad') ||
        combined.contains('sub')) {
      return 'Legendado';
    }
    return 'Dublado';
  }

  String _normalizeUrl(String url, String base) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    try {
      final baseUri = Uri.parse(base);
      return baseUri.resolve(url).toString();
    } catch (_) {
      return url;
    }
  }
}

class _AudioSection {
  final String audioType;
  final String htmlContent;
  final List<String> embedUrls;

  _AudioSection({
    required this.audioType,
    required this.htmlContent,
    required this.embedUrls,
  });
}
