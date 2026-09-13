import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/models/movie.dart';

void main() {
  group('Filtro e Classificacao de Filmes Reais', () {
    test('Movie.isReleased detecta corretamente filmes lancados vs futuros', () {
      final releasedMovie = Movie(
        id: 1,
        title: 'Homem-Aranha: De Volta ao Lar',
        posterPath: '/path.jpg',
        backdropPath: '/back.jpg',
        overview: 'Peter Parker volta para casa.',
        releaseDate: '2017-07-07',
        voteAverage: 7.4,
        voteCount: 20000,
        popularity: 85.0,
      );

      final futureDate = DateTime.now().add(const Duration(days: 365)).toIso8601String().substring(0, 10);
      final futureMovie = Movie(
        id: 2,
        title: 'Homem-Aranha: Futuro Distante',
        posterPath: '/future.jpg',
        backdropPath: '/back2.jpg',
        overview: 'Anunciado para o futuro.',
        releaseDate: futureDate,
        voteAverage: 0.0,
        voteCount: 0,
        popularity: 500.0,
      );

      final emptyDateMovie = Movie(
        id: 3,
        title: 'Filme Sem Data',
        posterPath: '/nodate.jpg',
        backdropPath: '/back3.jpg',
        overview: 'Sem data de lancamento.',
        releaseDate: '',
        voteAverage: 5.0,
      );

      expect(releasedMovie.isReleased, isTrue);
      expect(futureMovie.isReleased, isFalse);
      expect(emptyDateMovie.isReleased, isFalse);
    });

    test('Movie.isRealWatchableMovie filtra filmes falsos, sem poster ou nao lancados', () {
      final validMovie = Movie(
        id: 10,
        title: 'Moana: Um Mar de Aventuras',
        posterPath: '/moana.jpg',
        backdropPath: '/moanaback.jpg',
        overview: 'Moana embarca em uma missao audaciosa.',
        releaseDate: '2016-11-23',
        voteAverage: 7.6,
        voteCount: 12000,
        popularity: 65.0,
      );

      final futureDate = DateTime.now().add(const Duration(days: 300)).toIso8601String().substring(0, 10);
      final unreleasedMovie = Movie(
        id: 11,
        title: 'Moana (Live Action Futuro)',
        posterPath: '/moanalive.jpg',
        backdropPath: '/moanaback2.jpg',
        overview: 'Adaptacao live action futura.',
        releaseDate: futureDate,
        voteAverage: 0.0,
        voteCount: 0,
        popularity: 120.0,
      );

      final noPosterMovie = Movie(
        id: 12,
        title: 'Filme Fantasma',
        posterPath: '',
        backdropPath: '',
        overview: 'Filme sem cartaz.',
        releaseDate: '2020-01-01',
        voteAverage: 8.0,
        voteCount: 50,
        popularity: 10.0,
      );

      expect(validMovie.isRealWatchableMovie, isTrue);
      expect(unreleasedMovie.isRealWatchableMovie, isFalse);
      expect(noPosterMovie.isRealWatchableMovie, isFalse);
    });

    test('Algoritmo de pontuacao ponderada prioriza filmes reais e classicos consagrados', () {
      final spiderman2002 = Movie(
        id: 557,
        title: 'Homem-Aranha',
        posterPath: '/sm1.jpg',
        backdropPath: '/sm1_b.jpg',
        overview: 'Tobey Maguire como Homem-Aranha.',
        releaseDate: '2002-05-01',
        voteAverage: 7.3,
        voteCount: 18500,
        popularity: 50.0,
      );

      final spidermanHomecoming = Movie(
        id: 315635,
        title: 'Homem-Aranha: De Volta ao Lar',
        posterPath: '/smh.jpg',
        backdropPath: '/smh_b.jpg',
        overview: 'Tom Holland no MCU.',
        releaseDate: '2017-07-05',
        voteAverage: 7.4,
        voteCount: 22000,
        popularity: 80.0,
      );

      final futureAnnouncement = Movie(
        id: 999999,
        title: 'Homem-Aranha: Alem do Multiverso Fanmade',
        posterPath: '/fan.jpg',
        backdropPath: '/fan_b.jpg',
        overview: 'Apenas especulacao.',
        releaseDate: DateTime.now().add(const Duration(days: 400)).toIso8601String().substring(0, 10),
        voteAverage: 0.0,
        voteCount: 1,
        popularity: 900.0,
      );

      final candidates = [futureAnnouncement, spiderman2002, spidermanHomecoming];

      final realMovies = candidates.where((m) => m.isRealWatchableMovie).toList();

      expect(realMovies.contains(futureAnnouncement), isFalse);
      expect(realMovies.length, equals(2));

      realMovies.sort((a, b) {
        final scoreA = (a.voteCount * 1.5) + (a.popularity * 3.0);
        final scoreB = (b.voteCount * 1.5) + (b.popularity * 3.0);
        return scoreB.compareTo(scoreA);
      });

      expect(realMovies.first.title, equals('Homem-Aranha: De Volta ao Lar'));
      expect(realMovies[1].title, equals('Homem-Aranha'));
    });
  });
}
