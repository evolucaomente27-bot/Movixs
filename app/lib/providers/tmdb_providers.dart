import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/tmdb_repository.dart';
import '../data/models/movie.dart';
import '../data/models/tv_models.dart';

final tmdbRepositoryProvider = Provider<TMDBRepository>((ref) {
  return TMDBRepository();
});

// Banner Principal Hero
final heroMoviesProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getFeaturedHeroMovies();
});

// Em Alta
final trendingMoviesProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getTrendingMovies();
});

// Top 10 Hoje
final top10MoviesProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getTop10Movies();
});

// Ação
final actionMoviesProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getActionMovies();
});

// Ficção Científica
final sciFiMoviesProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getSciFiMovies();
});

// --- PROVEDORES DE SÉRIES DE TV ---

// Séries em Alta (Trending TV)
final trendingTvShowsProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getTrendingTvShows();
});

// Séries Mais Populares
final popularTvShowsProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getPopularTvShows();
});

// Séries Mais Bem Avaliadas (Top Rated)
final topRatedTvShowsProvider = FutureProvider<List<Movie>>((ref) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getTopRatedTvShows();
});

// Temporadas de uma Série
final tvShowSeasonsProvider = FutureProvider.family<List<TvSeason>, int>((ref, tvId) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getTvShowSeasons(tvId);
});

// Episódios de uma Temporada
final tvSeasonEpisodesProvider = FutureProvider.family<List<TvEpisode>, ({int tvId, int seasonNumber})>((ref, params) async {
  final repository = ref.read(tmdbRepositoryProvider);
  return repository.getTvSeasonEpisodes(params.tvId, params.seasonNumber);
});

// Estado da Lista de Favoritos (Minha Lista)
class FavoritesNotifier extends StateNotifier<List<Movie>> {
  FavoritesNotifier() : super([]);

  void toggleFavorite(Movie movie) {
    if (state.any((m) => m.id == movie.id)) {
      state = state.where((m) => m.id != movie.id).toList();
    } else {
      state = [...state, movie];
    }
  }

  bool isFavorite(int movieId) {
    return state.any((m) => m.id == movieId);
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<Movie>>((ref) {
  return FavoritesNotifier();
});

// Filtro de Categoria Selecionada no Topo (Todos, Filmes, Séries, Top 10)
final selectedCategoryProvider = StateProvider<String>((ref) => 'Todos');
