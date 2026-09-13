import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/services/movie_scraper_service.dart';

void main() {
  group('1. Configuracao de Parametros PT-BR nas Fontes de Streaming', () {
    test('VidLink e MultiEmbed geram URLs com parametros para audio dublado e legendas PT-BR em filmes', () async {
      final scraper = MovieScraperService.instance;
      final result = await scraper.resolveMovieStreams(
        title: 'Deadpool & Wolverine',
        tmdbId: 533535,
        imdbId: 'tt6263850',
      );

      expect(result.success, isTrue);

      final vidlink = result.servers.firstWhere((s) => s.url.contains('vidlink.pro'));
      expect(vidlink.url, contains('multiLang=true'));
      expect(vidlink.url, contains('selectedLanguage=portuguese'));
      expect(vidlink.url, contains('sub_lang=pt'));
      expect(vidlink.lang, contains('Dublado'));

      final multiembed = result.servers.firstWhere((s) => s.url.contains('multiembed.mov'));
      expect(multiembed.url, contains('sub_lang=pt'));
      expect(multiembed.name, contains('Legendas PT-BR'));
    });

    test('VidLink e MultiEmbed geram URLs com parametros para audio dublado e legendas PT-BR em series', () async {
      final scraper = MovieScraperService.instance;
      final result = await scraper.resolveSeriesStreams(
        title: 'Breaking Bad',
        tmdbId: 1396,
        season: 1,
        episode: 1,
        imdbId: 'tt0903747',
      );

      expect(result.success, isTrue);

      final vidlink = result.servers.firstWhere((s) => s.url.contains('vidlink.pro'));
      expect(vidlink.url, contains('multiLang=true'));
      expect(vidlink.url, contains('selectedLanguage=portuguese'));
      expect(vidlink.url, contains('sub_lang=pt'));
      expect(vidlink.url, contains('/tv/1396/1/1'));

      final multiembed = result.servers.firstWhere((s) => s.url.contains('multiembed.mov'));
      expect(multiembed.url, contains('sub_lang=pt'));
      expect(multiembed.url, contains('s=1&e=1'));
    });
  });

  group('2. Deteccao e Priorizacao de Idioma PT-BR', () {
    int getPtScore(String? str) {
      if (str == null || str.isEmpty) return 0;
      final s = str.toLowerCase().trim();
      if (s.contains('brasil') || s.contains('brazil') || s.contains('pt-br') || s.contains('pt_br') || s.contains('ptbr')) return 100;
      if (s.contains('dublado')) return 95;
      if (s.contains('portugu') || s.contains('portugues') || s.contains('portuguese')) return 90;
      if (s.contains('pob')) return 80;
      if (s == 'pt' || s.startsWith('pt-')) return 70;
      return 0;
    }

    test('getPtScore pontua corretamente variacoes com prioridade para PT-BR/Brasil/Dublado', () {
      expect(getPtScore('Português (Brasil)'), equals(100));
      expect(getPtScore('pt-BR'), equals(100));
      expect(getPtScore('Filme Dublado 1080p'), equals(95));
      expect(getPtScore('Portuguese'), equals(90));
      expect(getPtScore('Português'), equals(90));
      expect(getPtScore('pob'), equals(80));
      expect(getPtScore('pt'), equals(70));
      expect(getPtScore('English'), equals(0));
      expect(getPtScore('Spanish (Latino)'), equals(0));
    });

    test('Selecao entre multiplas trilhas escolhe a melhor opcao PT-BR', () {
      final tracks = [
        {'label': 'English', 'lang': 'en'},
        {'label': 'Spanish', 'lang': 'es'},
        {'label': 'Portuguese', 'lang': 'pt'},
        {'label': 'Português (Brasil)', 'lang': 'pt-BR'},
      ];

      Map<String, String>? bestTrack;
      int maxScore = 0;

      for (final t in tracks) {
        final score = [getPtScore(t['label']), getPtScore(t['lang'])].reduce((a, b) => a > b ? a : b);
        if (score > maxScore) {
          maxScore = score;
          bestTrack = t;
        }
      }

      expect(bestTrack, isNotNull);
      expect(bestTrack!['label'], equals('Português (Brasil)'));
      expect(bestTrack['lang'], equals('pt-BR'));
      expect(maxScore, equals(100));
    });
  });
}
