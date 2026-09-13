import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tmdb_providers.dart';
import '../data/models/movie.dart';
import 'widgets/movie_card.dart';
import 'widgets/movie_details_sheet.dart';
import 'player/video_player_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';
  String _selectedGenre = 'Todos';
  bool _isListView = false;
  bool _isSearching = false;
  List<Movie> _liveSearchResults = [];
  Timer? _debounceTimer;

  // Histórico de Buscas
  final List<String> _recentSearches = [
    'Deadpool & Wolverine',
    'Homem-Aranha',
    'Batman',
    'Godzilla',
    'Duna',
  ];

  final List<String> _genreFilters = [
    'Todos',
    '🔥 Em Alta',
    '💥 Ação',
    '🚀 Ficção',
    '🦇 Aventura',
    '⭐ Mais Votados',
    '🎬 4K HDR',
  ];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String val) {
    setState(() => _query = val);
    _debounceTimer?.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _liveSearchResults = [];
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      final repo = ref.read(tmdbRepositoryProvider);
      final results = await repo.searchMovies(val);
      if (mounted) {
        setState(() {
          _liveSearchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _onSearchSubmit(String term) {
    if (term.trim().isEmpty) return;
    _searchController.text = term;
    _onQueryChanged(term);
    if (!_recentSearches.contains(term)) {
      setState(() => _recentSearches.insert(0, term));
    }
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final trendingAsync = ref.watch(trendingMoviesProvider);
    final actionAsync = ref.watch(actionMoviesProvider);
    final sciFiAsync = ref.watch(sciFiMoviesProvider);
    final top10Async = ref.watch(top10MoviesProvider);

    // Concatena todos os filmes do catálogo
    List<Movie> allMovies = [];
    trendingAsync.whenData((list) => allMovies.addAll(list));
    actionAsync.whenData((list) => allMovies.addAll(list));
    sciFiAsync.whenData((list) => allMovies.addAll(list));
    top10Async.whenData((list) => allMovies.addAll(list));

    // Remove duplicatas
    final seen = <int>{};
    allMovies = allMovies.where((m) => seen.add(m.id)).toList();

    // Determina os resultados a exibir
    List<Movie> displayResults;
    if (_query.trim().isNotEmpty) {
      if (_liveSearchResults.isNotEmpty) {
        displayResults = _liveSearchResults;
      } else {
        final q = _query.toLowerCase();
        displayResults = allMovies.where((m) =>
          m.title.toLowerCase().contains(q) ||
          m.overview.toLowerCase().contains(q) ||
          m.genres.any((g) => g.toLowerCase().contains(q))
        ).toList();
      }
    } else {
      displayResults = allMovies;
    }

    // Filtra por chip de gênero
    if (_selectedGenre != 'Todos') {
      if (_selectedGenre.contains('Em Alta')) {
        displayResults = [...displayResults]..sort((a, b) => b.popularity.compareTo(a.popularity));
      } else if (_selectedGenre.contains('Mais Votados')) {
        displayResults = [...displayResults]..sort((a, b) => b.voteCount.compareTo(a.voteCount));
      } else if (_selectedGenre.contains('Ação')) {
        displayResults = displayResults.where((m) => m.genres.any((g) => g.contains('Ação'))).toList();
      } else if (_selectedGenre.contains('Ficção')) {
        displayResults = displayResults.where((m) => m.genres.any((g) => g.contains('Ficção') || g.contains('Sci-Fi'))).toList();
      } else if (_selectedGenre.contains('Aventura')) {
        displayResults = displayResults.where((m) => m.genres.any((g) => g.contains('Aventura') || g.contains('Crime'))).toList();
      } else if (_selectedGenre.contains('4K HDR')) {
        displayResults = displayResults.where((m) => m.quality.contains('4K') || m.voteAverage >= 7.5).toList();
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar com Título e Alternador de Visualização
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explorar',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Catálogo Oficial ao Vivo TMDB',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  // Botão Alternar Grid / Lista
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B26),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      tooltip: _isListView ? 'Ver em Grade' : 'Ver em Lista',
                      onPressed: () => setState(() => _isListView = !_isListView),
                    ),
                  ),
                ],
              ),
            ),

            // Barra de Busca Dinâmica
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF181824),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _focusNode.hasFocus ? const Color(0xFFE50914) : Colors.white12,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  onChanged: _onQueryChanged,
                  onSubmitted: _onSearchSubmit,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Digite o nome do filme, ator ou gênero...',
                    hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
                    prefixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.5),
                            ),
                          )
                        : const Icon(Icons.search_rounded, color: Color(0xFFE50914), size: 24),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  ),
                ),
              ),
            ),

            // Chips de Filtro por Gênero
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _genreFilters.length,
                itemBuilder: (context, index) {
                  final genre = _genreFilters[index];
                  final isSelected = _selectedGenre == genre;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(genre),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() => _selectedGenre = val ? genre : 'Todos');
                      },
                      labelStyle: GoogleFonts.inter(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      selectedColor: const Color(0xFFE50914),
                      backgroundColor: const Color(0xFF161622),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFFE50914) : Colors.white12,
                        ),
                      ),
                      showCheckmark: false,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Conteúdo Principal
            Expanded(
              child: _query.isEmpty && _selectedGenre == 'Todos'
                  ? _buildDefaultExploreView(allMovies)
                  : _buildResultsView(displayResults),
            ),
          ],
        ),
      ),
    );
  }

  // Visão padrão com Histórico de Buscas e Filmes em Destaque
  Widget _buildDefaultExploreView(List<Movie> allMovies) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      children: [
        // Buscas Recentes
        if (_recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Buscas Recentes',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _recentSearches.clear()),
                child: Text(
                  'Limpar',
                  style: GoogleFonts.inter(color: const Color(0xFFE50914), fontSize: 13),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches.map((term) {
              return ActionChip(
                avatar: const Icon(Icons.history_rounded, size: 16, color: Colors.white54),
                label: Text(term),
                labelStyle: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                backgroundColor: const Color(0xFF191925),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.white12),
                ),
                onPressed: () => _onSearchSubmit(term),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Mais Pesquisados Hoje
        Text(
          'Mais Populares Hoje',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...allMovies.take(6).map((movie) => _buildTopSearchItem(movie)),
      ],
    );
  }

  // Item de filme estilizado com botão rápido de assistir
  Widget _buildTopSearchItem(Movie movie) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        onTap: () => MovieDetailsSheet.show(context, movie),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            // Pôster Pequeno
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 60,
                height: 85,
                child: Image.network(
                  movie.fullPosterUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Informações do Filme
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      // Badge do Ano de Lançamento
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          movie.releaseYear,
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                      const SizedBox(width: 2),
                      Text(
                        movie.voteAverage.toStringAsFixed(1),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      // Badge de Qualidade
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          movie.quality.contains('IMAX') ? 'IMAX' : '4K HDR',
                          style: GoogleFonts.inter(color: const Color(0xFFE50914), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    movie.genres.take(3).join(" • "),
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

            // Botão Play Rápido
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFE50914), size: 20),
              ),
              onPressed: () => VideoPlayerScreen.navigate(context, movie),
            ),
          ],
        ),
      ),
    );
  }

  // Visão dos Resultados Filtrados
  Widget _buildResultsView(List<Movie> results) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 64, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              'Nenhum título encontrado para "$_query"',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Tente buscar por "Deadpool", "Batman" ou "Homem-Aranha"',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contador de Resultados com Badge de Filmes Reais Lançados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${results.length} filmes reais encontrados',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF009C3B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF009C3B).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF009C3B), size: 11),
                    const SizedBox(width: 4),
                    Text(
                      'Apenas Lançados',
                      style: GoogleFonts.inter(color: const Color(0xFF009C3B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Exibição em Lista ou Grade
        Expanded(
          child: _isListView
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  physics: const BouncingScrollPhysics(),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final movie = results[index];
                    return _buildTopSearchItem(movie);
                  },
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final movie = results[index];
                    return MovieCard(
                      movie: movie,
                      showRating: true,
                      showTitle: true,
                      isGrid: true,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
