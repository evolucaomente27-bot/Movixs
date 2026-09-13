import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/movie.dart';
import 'movie_details_sheet.dart';

class Top10MovieCard extends StatelessWidget {
  final Movie movie;
  final int rank;

  const Top10MovieCard({
    super.key,
    required this.movie,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => MovieDetailsSheet.show(context, movie),
      child: Container(
        width: 190,
        margin: const EdgeInsets.symmetric(horizontal: 6.0),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            // Grande número estilizado no fundo esquerdo
            Positioned(
              left: 0,
              bottom: -15,
              child: Text(
                '$rank',
                style: GoogleFonts.outfit(
                  fontSize: 110,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF262635),
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.8),
                      offset: const Offset(3, 3),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),

            // Card do Filme deslocado à direita
            Positioned(
              right: 0,
              top: 8,
              bottom: 8,
              child: Container(
                width: 135,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFF1B1B26),
                  border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        movie.fullPosterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.movie_outlined, color: Colors.white24),
                        ),
                      ),
                      // Top 10 Ribbon
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'TOP 10',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      // Rating
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                              const SizedBox(width: 3),
                              Text(
                                movie.voteAverage.toStringAsFixed(1),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
