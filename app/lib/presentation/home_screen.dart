import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tmdb_providers.dart';
import '../data/models/movie.dart';
import 'widgets/movie_card.dart';
import 'widgets/top10_movie_card.dart';
import 'widgets/movie_details_sheet.dart';
import 'search_screen.dart';
import 'favorites_screen.dart';
import 'player/video_player_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    FavoritesScreen(),
    ProfileTabPlaceholder(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildFloatingBottomNav(),
    );
  }

  Widget _buildFloatingBottomNav() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161622).withOpacity(0.92),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.7),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Início'),
          _buildNavItem(1, Icons.search_rounded, Icons.search_outlined, 'Buscar'),
          _buildNavItem(2, Icons.bookmark_rounded, Icons.bookmark_border_rounded, 'Minha Lista'),
          _buildNavItem(3, Icons.person_rounded, Icons.person_outline_rounded, 'Perfil'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE50914).withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? const Color(0xFFE50914) : Colors.white54,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileTabPlaceholder extends StatelessWidget {
  const ProfileTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Meu Perfil',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const CircleAvatar(
                    radius: 46,
                    backgroundColor: Color(0xFF161622),
                    child: Icon(Icons.play_arrow_rounded, size: 50, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Usuário Movixs',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Plano Premium 4K Ultra HD',
              style: GoogleFonts.inter(color: const Color(0xFFE50914), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _heroPageController = PageController();
  int _currentHeroPage = 0;
  Timer? _heroAutoScrollTimer;

  final List<String> _categories = const [
    'Todos',
    'Filmes',
    'Séries',
    'Ação',
    'Ficção',
    'Em Alta',
  ];

  @override
  void initState() {
    super.initState();
    _startHeroAutoScroll();
  }

  void _startHeroAutoScroll() {
    _heroAutoScrollTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (_heroPageController.hasClients) {
        final nextPage = (_currentHeroPage + 1) % 3;
        _heroPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _heroAutoScrollTimer?.cancel();
    _heroPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0C0C12);

    final heroAsync = ref.watch(heroMoviesProvider);
    final trendingAsync = ref.watch(trendingMoviesProvider);
    final top10Async = ref.watch(top10MoviesProvider);
    final actionAsync = ref.watch(actionMoviesProvider);
    final sciFiAsync = ref.watch(sciFiMoviesProvider);
    final trendingTvAsync = ref.watch(trendingTvShowsProvider);
    final popularTvAsync = ref.watch(popularTvShowsProvider);
    final topRatedTvAsync = ref.watch(topRatedTvShowsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    final heroContent = selectedCategory == 'Séries' ? trendingTvAsync : heroAsync;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Billboard Hero Carousel
            _buildHeroCarousel(heroContent),

            // Pílulas de Categoria Flutuantes
            _buildCategoryPills(selectedCategory),
            const SizedBox(height: 24),

            if (selectedCategory == 'Séries') ...[
              // Seção Séries em Alta
              _buildSectionHeader('Séries em Alta Hoje', 'Ver mais'),
              _buildHorizontalMovieList(trendingTvAsync),
              const SizedBox(height: 32),

              // Seção Top 10 Séries
              _buildSectionHeader('Top 10 Séries no Brasil', null),
              _buildTop10List(topRatedTvAsync),
              const SizedBox(height: 32),

              // Seção Séries Populares
              _buildSectionHeader('Séries Populares no Streaming', 'Ver mais'),
              _buildHorizontalMovieList(popularTvAsync),
            ] else if (selectedCategory == 'Filmes') ...[
              // Seção Filmes em Alta
              _buildSectionHeader('Filmes em Alta Hoje', 'Ver mais'),
              _buildHorizontalMovieList(trendingAsync),
              const SizedBox(height: 32),

              // Seção Top 10 Filmes
              _buildSectionHeader('Top 10 Filmes no Brasil', null),
              _buildTop10List(top10Async),
              const SizedBox(height: 32),

              // Seção Ação
              _buildSectionHeader('Ação & Adrenalina', 'Ver mais'),
              _buildHorizontalMovieList(actionAsync),
              const SizedBox(height: 32),

              // Seção Ficção
              _buildSectionHeader('Ficção Científica & Fantasia', 'Ver mais'),
              _buildHorizontalMovieList(sciFiAsync),
            ] else ...[
              // Modo "Todos": Catálogo Híbrido com Filmes e Séries
              _buildSectionHeader('Em Alta Hoje', 'Ver mais'),
              _buildHorizontalMovieList(trendingAsync),
              const SizedBox(height: 32),

              // Seção Especial: Séries em Alta no Streaming
              _buildSectionHeader('Séries em Alta no Streaming', 'Ver mais'),
              _buildHorizontalMovieList(trendingTvAsync),
              const SizedBox(height: 32),

              // Top 10 Brasil
              _buildSectionHeader('Top 10 Hoje no Brasil', null),
              _buildTop10List(top10Async),
              const SizedBox(height: 32),

              // Séries Populares
              _buildSectionHeader('Séries Populares e Aclamadas', 'Ver mais'),
              _buildHorizontalMovieList(popularTvAsync),
              const SizedBox(height: 32),

              // Seção: Ação e Adrenalina
              _buildSectionHeader('Ação & Adrenalina', 'Ver mais'),
              _buildHorizontalMovieList(actionAsync),
              const SizedBox(height: 32),

              // Seção: Ficção Científica & Multiverso
              _buildSectionHeader('Ficção Científica & Fantasia', 'Ver mais'),
              _buildHorizontalMovieList(sciFiAsync),
            ],

            const SizedBox(height: 120), // Espaço para não cobrir a bottom bar
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(65),
      child: Container(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logo Movixs com gradiente
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE50914).withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'MOVIXS',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontSize: 26,
                      letterSpacing: -0.8,
                    ),
                  ),
                ],
              ),

              // Botões de Ação no Topo
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white, size: 26),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFFFF8A00)],
                      ),
                      border: Border.all(color: Colors.white38, width: 1),
                    ),
                    child: const Center(
                      child: Text(
                        'M',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryPills(String selectedCategory) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == selectedCategory;
          return GestureDetector(
            onTap: () => ref.read(selectedCategoryProvider.notifier).state = cat,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE50914) : const Color(0xFF1B1B26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFFE50914) : Colors.white.withOpacity(0.08),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFE50914).withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  cat,
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroCarousel(AsyncValue<List<Movie>> heroAsync) {
    return heroAsync.when(
      data: (movies) {
        if (movies.isEmpty) return const SizedBox(height: 480);
        final displayMovies = movies.take(3).toList();

        final heroHeight = (MediaQuery.of(context).size.height * 0.65).clamp(480.0, 650.0);
        return SizedBox(
          height: heroHeight,
          child: Stack(
            children: [
              PageView.builder(
                controller: _heroPageController,
                onPageChanged: (index) => setState(() => _currentHeroPage = index),
                itemCount: displayMovies.length,
                itemBuilder: (context, index) {
                  return _buildHeroItem(displayMovies[index]);
                },
              ),

              // Indicadores de Página (Dots)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(displayMovies.length, (i) {
                    final isActive = _currentHeroPage == i;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 24 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFE50914) : Colors.white30,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 480,
        child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
      ),
      error: (_, __) => const SizedBox(height: 480),
    );
  }

  Widget _buildHeroItem(Movie movie) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop Image com transição suave
        Image.network(
          movie.fullBackdropUrl,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.movie_creation_outlined, size: 80, color: Colors.white24),
          ),
        ),

        // Degradês multicamadas cinematográficos
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                const Color(0xFF0C0C12),
                const Color(0xFF0C0C12).withOpacity(0.85),
                const Color(0xFF0C0C12).withOpacity(0.0),
                const Color(0xFF0C0C12).withOpacity(0.7),
              ],
              stops: const [0.0, 0.22, 0.55, 1.0],
            ),
          ),
        ),

        // Informações e Botões do Filme em Destaque
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 36.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Badge de Top / Destaque
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE50914).withOpacity(0.6), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: Color(0xFFE50914), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'DESTAQUE DA SEMANA',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Título
              Text(
                movie.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  letterSpacing: -1,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.9), blurRadius: 20, offset: const Offset(0, 3)),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Gêneros e Duração
              Text(
                '${movie.genres.join(" • ")}  |  ${movie.duration}  |  ★ ${movie.voteAverage.toStringAsFixed(1)}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // Botões de Ação
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => VideoPlayerScreen.navigate(context, movie),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      elevation: 10,
                      shadowColor: const Color(0xFFE50914).withOpacity(0.6),
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: Text(
                      'Assistir',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => MovieDetailsSheet.show(context, movie),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF1E1E2A).withOpacity(0.8),
                      side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 22),
                    label: Text(
                      'Detalhes',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String? actionText) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          if (actionText != null)
            Text(
              actionText,
              style: GoogleFonts.inter(
                color: const Color(0xFFE50914),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalMovieList(AsyncValue<List<Movie>> moviesAsync) {
    return SizedBox(
      height: 240,
      child: moviesAsync.when(
        data: (movies) {
          if (movies.isEmpty) return const Center(child: Text('Nenhum filme disponível.'));
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              return MovieCard(
                movie: movies[index],
                showTitle: true,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
        error: (err, _) => const Center(child: Text('Erro ao carregar filmes', style: TextStyle(color: Colors.white38))),
      ),
    );
  }

  Widget _buildTop10List(AsyncValue<List<Movie>> top10Async) {
    return SizedBox(
      height: 220,
      child: top10Async.when(
        data: (movies) {
          if (movies.isEmpty) return const SizedBox();
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              return Top10MovieCard(
                movie: movies[index],
                rank: index + 1,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
        error: (_, __) => const SizedBox(),
      ),
    );
  }
}
