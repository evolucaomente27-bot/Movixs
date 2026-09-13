import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/movie.dart';
import '../../data/models/tv_models.dart';
import '../../providers/tmdb_providers.dart';
import '../player/video_player_screen.dart';

class MovieDetailsSheet extends ConsumerStatefulWidget {
  final Movie movie;

  const MovieDetailsSheet({super.key, required this.movie});

  static void show(BuildContext context, Movie movie) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MovieDetailsSheet(movie: movie),
    );
  }

  @override
  ConsumerState<MovieDetailsSheet> createState() => _MovieDetailsSheetState();
}

class _MovieDetailsSheetState extends ConsumerState<MovieDetailsSheet> {
  int _selectedSeasonNumber = 1;

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final isFav = ref.watch(favoritesProvider).any((m) => m.id == movie.id);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: const Color(0xFF14141B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.9),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Backdrop Header com Play Button
                _buildBackdropHeader(context),

                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge Série / Filme
                      if (movie.isTvShow) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SÉRIE DE TV',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Título
                      Text(
                        movie.title,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Metadados (Nota, Ano, Duração / Temporadas, Classificação, Qualidade)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE50914), width: 1),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    movie.voteAverage.toStringAsFixed(1),
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildBadge(movie.releaseYear),
                            const SizedBox(width: 8),
                            _buildBadge(movie.duration),
                            const SizedBox(width: 8),
                            _buildBadge(movie.ageRating, isAccent: true),
                            const SizedBox(width: 8),
                            _buildBadge(movie.quality),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Gêneros
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: movie.genres.map((genre) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22222E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.06)),
                            ),
                            child: Text(
                              genre,
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // Botão Principal de Reprodução
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            VideoPlayerScreen.navigate(
                              context,
                              movie,
                              seasonNumber: movie.isTvShow ? _selectedSeasonNumber : null,
                              episodeNumber: movie.isTvShow ? 1 : null,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor: const Color(0xFFE50914).withOpacity(0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 28),
                          label: Text(
                            movie.isTvShow
                                ? 'Assistir 1º Episódio (T$_selectedSeasonNumber:E1)'
                                : 'Assistir Agora (4K Ultra HD)',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Botões Secundários (Minha Lista & Trailer)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref.read(favoritesProvider.notifier).toggleFavorite(movie);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: const Color(0xFF1E1E28),
                                side: BorderSide(
                                  color: isFav ? const Color(0xFFE50914) : Colors.white24,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: Icon(
                                isFav ? Icons.check_circle_rounded : Icons.bookmark_add_outlined,
                                color: isFav ? const Color(0xFFE50914) : Colors.white,
                                size: 22,
                              ),
                              label: Text(
                                isFav ? 'Salvo' : 'Minha Lista',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isFav ? const Color(0xFFE50914) : Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Carregando trailer...')),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: const Color(0xFF1E1E28),
                                side: const BorderSide(color: Colors.white24, width: 1.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.movie_creation_outlined, size: 22),
                              label: Text(
                                'Trailer',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Sinopse
                      Text(
                        'Sinopse',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        movie.overview,
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // --- SEÇÃO DE SÉRIES: TEMPORADAS & EPISÓDIOS ---
                      if (movie.isTvShow) ...[
                        _buildSeriesEpisodesSection(context, movie),
                        const SizedBox(height: 40),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Pílula / Handle superior para fechar
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // Botão Fechar no canto superior direito
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesEpisodesSection(BuildContext context, Movie movie) {
    final seasonsAsync = ref.watch(tvShowSeasonsProvider(movie.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Episódios',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            seasonsAsync.when(
              data: (seasons) {
                if (seasons.isEmpty) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: seasons.any((s) => s.seasonNumber == _selectedSeasonNumber)
                          ? _selectedSeasonNumber
                          : seasons.first.seasonNumber,
                      dropdownColor: const Color(0xFF1E1E28),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedSeasonNumber = val);
                        }
                      },
                      items: seasons.map((s) {
                        return DropdownMenuItem<int>(
                          value: s.seasonNumber,
                          child: Text(s.name),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Lista de Episódios da Temporada Selecionada
        Consumer(
          builder: (context, ref, _) {
            final episodesAsync = ref.watch(
              tvSeasonEpisodesProvider((tvId: movie.id, seasonNumber: _selectedSeasonNumber)),
            );

            return episodesAsync.when(
              data: (episodes) {
                if (episodes.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B26),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Nenhum episódio encontrado para esta temporada.',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: episodes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final ep = episodes[index];
                    return _buildEpisodeCard(context, movie, ep);
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 3),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Erro ao carregar episódios: $err',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEpisodeCard(BuildContext context, Movie movie, TvEpisode ep) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        VideoPlayerScreen.navigate(
          context,
          movie,
          seasonNumber: _selectedSeasonNumber,
          episodeNumber: ep.episodeNumber,
          episodeTitle: ep.name,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail do Episódio com Play Overlay
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Image.network(
                    ep.fullStillUrl,
                    width: 110,
                    height: 68,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 110,
                      height: 68,
                      color: const Color(0xFF222230),
                      child: const Icon(Icons.tv_rounded, color: Colors.white24, size: 28),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      color: Colors.black38,
                      child: const Center(
                        child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Informações do Episódio
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${ep.episodeNumber}. ',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFE50914),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          ep.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        ep.durationFormatted,
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      if (ep.voteAverage > 0) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 13),
                        const SizedBox(width: 2),
                        Text(
                          ep.voteAverage.toStringAsFixed(1),
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ep.overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAccent ? const Color(0xFF2E2430) : const Color(0xFF22222E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAccent ? const Color(0xFFE50914).withOpacity(0.5) : Colors.white12,
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: isAccent ? const Color(0xFFFF5252) : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBackdropHeader(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        color: Color(0xFF1C1C28),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              widget.movie.fullBackdropUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.movie_filter_rounded, size: 64, color: Colors.white24),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF14141B),
                    const Color(0xFF14141B).withOpacity(0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  VideoPlayerScreen.navigate(
                    context,
                    widget.movie,
                    seasonNumber: widget.movie.isTvShow ? _selectedSeasonNumber : null,
                    episodeNumber: widget.movie.isTvShow ? 1 : null,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914).withOpacity(0.85),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE50914).withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
