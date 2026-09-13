import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/services/movie_scraper_service.dart';
import 'package:app/services/local_stream_proxy.dart';

void main() {
  test('Teste de busca de filmes ao vivo (searchMovies)', () async {
    final scraper = MovieScraperService.instance;
    final results = await scraper.searchMovies('Deadpool');
    print('\n========================================');
    print('🔎 TESTE DE BUSCA: "Deadpool"');
    print('========================================');
    print('Total de filmes retornados: ${results.length}');
    for (final item in results.take(3)) {
      print('  🎬 ${item.title} (${item.year}) - Áudio: ${item.audioType}');
      print('     Capa: ${item.posterUrl}');
      print('     Link: ${item.pageUrl}');
    }
    expect(results.isNotEmpty, isTrue, reason: 'Deve retornar resultados para Deadpool');
  });

  test('Teste de resolução e status de servidores ativos', () async {
    final scraper = MovieScraperService.instance;

    final moviesToTest = [
      {'title': 'Deadpool & Wolverine', 'tmdbId': 533535, 'imdbId': 'tt6263850'},
      {'title': 'Oppenheimer', 'tmdbId': 872585, 'imdbId': 'tt15398776'},
      {'title': 'Duna: Parte 2', 'tmdbId': 693134, 'imdbId': 'tt15239678'},
    ];

    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    for (final movie in moviesToTest) {
      final title = movie['title'] as String;
      final tmdbId = movie['tmdbId'] as int;
      final imdbId = movie['imdbId'] as String;

      print('\n========================================');
      print('🎬 TESTANDO FILME: $title (TMDB: $tmdbId, IMDB: $imdbId)');
      print('========================================');

      final result = await scraper.resolveMovieStreams(
        title: title,
        tmdbId: tmdbId,
        imdbId: imdbId,
      );

      print('Status: ${result.success ? "SUCESSO" : "FALHA"}');
      print('Total de servidores encontrados: ${result.servers.length}');

      expect(result.servers.isNotEmpty, isTrue, reason: 'Deve encontrar servidores para $title');

      // Garante que VidSrc.to é o primeiro servidor preferencial
      expect(result.servers.first.url, contains('vidsrc.to'), reason: 'VidSrc.to deve ser o primeiro servidor preferencial');
      expect(result.servers.first.name, contains('VidSrc.to'), reason: 'Nome do servidor preferencial deve ser VidSrc.to');

      // Garante que WarezCDN e SuperFlix foram completamente removidos
      final hasWarez = result.servers.any((s) => s.name.toLowerCase().contains('warez') || s.url.toLowerCase().contains('warez'));
      expect(hasWarez, isFalse, reason: 'WarezCDN deve ter sido removido');

      final hasSuperFlix = result.servers.any((s) => s.name.toLowerCase().contains('superflix') || s.url.toLowerCase().contains('superflix'));
      expect(hasSuperFlix, isFalse, reason: 'SuperFlix deve ter sido removido');

      int workingServers = 0;

      for (final server in result.servers) {
        final url = server.url;
        final name = server.name;
        final type = server.type;

        // Testa se a URL do servidor responde HTTP 200/302
        try {
          final uri = Uri.parse(url);
          final req = await client.getUrl(uri).timeout(const Duration(seconds: 4));
          req.headers.set('User-Agent', MovieScraperService.defaultUserAgent);
          req.headers.set('Referer', url);
          final res = await req.close().timeout(const Duration(seconds: 4));
          await res.drain();

          final isAlive = res.statusCode >= 200 && res.statusCode < 400;
          if (isAlive) {
            workingServers++;
            print('  ✅ [$type] $name -> HTTP ${res.statusCode} (Ativo)');
          } else {
            print('  ⚠️ [$type] $name -> HTTP ${res.statusCode}');
          }
        } catch (e) {
          print('  ❌ [$type] $name -> Erro: $e');
        }
      }

      print('📊 Servidores respondendo OK para "$title": $workingServers / ${result.servers.length}');
      expect(workingServers, greaterThan(0), reason: 'Pelo menos um servidor deve responder com sucesso');
    }

    client.close();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
