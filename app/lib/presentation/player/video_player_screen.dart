import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/models/movie.dart';
import '../../data/repositories/streaming_repository.dart';
import '../../services/local_stream_proxy.dart';
import 'in_app_embed_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Movie movie;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final int? totalEpisodesInSeason;

  const VideoPlayerScreen({
    super.key,
    required this.movie,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.totalEpisodesInSeason,
  });

  static void navigate(
    BuildContext context,
    Movie movie, {
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    int? totalEpisodesInSeason,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          movie: movie,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          episodeTitle: episodeTitle,
          totalEpisodesInSeason: totalEpisodesInSeason,
        ),
      ),
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  final StreamingRepository _streamingRepo = StreamingRepository();
  final LocalStreamProxy _localProxy = LocalStreamProxy.instance;
  bool _isLoading = true;
  StreamingServer? _selectedServer;
  List<StreamingServer> _availableServers = [];

  // Controle de Episódios para Séries
  late int _currentSeason;
  late int _currentEpisode;
  String? _currentEpisodeTitle;

  // MediaKit Controls
  double _playbackSpeed = 1.0;
  BoxFit _videoFit = BoxFit.contain;
  bool _controlsLocked = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _bufSub;
  StreamSubscription? _tracksSub;

  @override
  void initState() {
    super.initState();

    _currentSeason = widget.seasonNumber ?? 1;
    _currentEpisode = widget.episodeNumber ?? 1;
    _currentEpisodeTitle = widget.episodeTitle;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    _player = Player();
    _controller = VideoController(_player);

    _listenToPlayerEvents();
    _fetchAndPlayStream();
    _startHideControlsTimer();
  }

  void _listenToPlayerEvents() {
    _posSub = _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _durSub = _player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _playSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _bufSub = _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _tracksSub = _player.stream.tracks.listen((tracks) {
      _autoSelectMediaKitPtBrTracks(tracks);
    });
  }

  void _autoSelectMediaKitPtBrTracks(Tracks tracks) {
    bool isPt(String? str) {
      if (str == null || str.isEmpty) return false;
      final s = str.toLowerCase().trim();
      return s.contains('portug') ||
          s.contains('pt-br') ||
          s.contains('pt_br') ||
          s.contains('ptbr') ||
          s == 'pt' ||
          s.contains('por') ||
          s.contains('pob') ||
          s.contains('brasil') ||
          s.contains('brazil') ||
          s.contains('dublado');
    }

    // 1. Auto-selecionar Áudio Dublado / PT-BR se disponível
    try {
      final ptAudio = tracks.audio.cast<AudioTrack?>().firstWhere(
        (a) => a != null && (isPt(a.title) || isPt(a.language)),
        orElse: () => null,
      );
      if (ptAudio != null) {
        debugPrint('[VideoPlayerScreen] 🇧🇷 Auto-selecionando áudio dublado: ${ptAudio.title ?? ptAudio.language}');
        _player.setAudioTrack(ptAudio);
      }
    } catch (_) {}

    // 2. Auto-selecionar Legendas PT-BR se disponíveis
    try {
      final ptSub = tracks.subtitle.cast<SubtitleTrack?>().firstWhere(
        (s) => s != null && (isPt(s.title) || isPt(s.language)),
        orElse: () => null,
      );
      if (ptSub != null) {
        debugPrint('[VideoPlayerScreen] 🇧🇷 Auto-selecionando legenda PT-BR: ${ptSub.title ?? ptSub.language}');
        _player.setSubtitleTrack(ptSub);
      }
    } catch (_) {}
  }

  void _playNextEpisode() {
    setState(() {
      _currentEpisode += 1;
      _currentEpisodeTitle = 'Episódio $_currentEpisode';
    });
    _fetchAndPlayStream();
  }

  Future<void> _fetchAndPlayStream() async {
    setState(() => _isLoading = true);

    final streamResult = widget.movie.isTvShow
        ? await _streamingRepo.extractSeriesStream(
            title: widget.movie.title,
            tmdbId: widget.movie.id,
            season: _currentSeason,
            episode: _currentEpisode,
            imdbId: widget.movie.imdbId,
          )
        : await _streamingRepo.extractStream(
            title: widget.movie.title,
            tmdbId: widget.movie.id,
            imdbId: widget.movie.imdbId,
          );

    if (mounted) {
      final servers = streamResult.servers;

      if (!streamResult.hasPlayableStreams || servers.isEmpty) {
        // Nenhum stream .m3u8/.mp4 encontrado
        setState(() {
          _availableServers = [];
          _selectedServer = null;
          _isLoading = false;
        });
        return;
      }

      // Prioriza estritamente o VidSrc.to no topo da lista
      servers.sort((a, b) {
        final aIsVidSrcTo = a.url.contains('vidsrc.to');
        final bIsVidSrcTo = b.url.contains('vidsrc.to');
        if (aIsVidSrcTo && !bIsVidSrcTo) return -1;
        if (!aIsVidSrcTo && bIsVidSrcTo) return 1;
        return 0;
      });

      final initialServer = servers.firstWhere(
        (s) => s.url.contains('vidsrc.to'),
        orElse: () => servers.first,
      );

      setState(() {
        _availableServers = servers;
        _selectedServer = initialServer;
        _isLoading = false;
      });

      // Se for stream direto (.m3u8/.mp4) toca no MediaKit com LocalStreamProxy, caso contrário pausa e renderiza o WebView
      if (initialServer.type == 'direct' && initialServer.isPlayable) {
        await _playDirectStream(initialServer.url);
      } else {
        await _localProxy.stop();
        _player.pause();
      }
    }
  }

  Future<void> _playDirectStream(String streamUrl, {Map<String, String>? headers}) async {
    try {
      final uri = Uri.parse(streamUrl);
      final forwardHeaders = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': streamUrl,
        ...?headers,
      };

      // Inicia o LocalStreamProxy
      final proxiedUri = await _localProxy.startProxy(
        targetUri: uri,
        forwardHeaders: forwardHeaders,
      );

      debugPrint('[VideoPlayerScreen] 📡 Reproduzindo via LocalStreamProxy: $proxiedUri');
      await _player.open(Media(proxiedUri.toString()));
      await _player.play();
    } catch (e) {
      debugPrint('[VideoPlayerScreen] ⚠️ Falha ao iniciar proxy, fallback para URL direta: $e');
      // Fallback de segurança: URL direta
      await _player.open(Media(streamUrl));
      await _player.play();
    }
  }

  void _onServerChanged(StreamingServer newServer) async {
    setState(() {
      _selectedServer = newServer;
    });

    // Se direto (.m3u8/.mp4) → toca no MediaKit com LocalStreamProxy
    if (newServer.isPlayable && newServer.type == 'direct') {
      await _playDirectStream(newServer.url);
    } else {
      // Se embed → para o MediaKit e libera o proxy (a UI vai reconstruir com InAppEmbedPlayer)
      await _localProxy.stop();
      _player.pause();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_showControls || _controlsLocked) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _bufSub?.cancel();
    _tracksSub?.cancel();
    _localProxy.stop();
    _player.dispose();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 3.5),
              const SizedBox(height: 16),
              Text(
                'Resolvendo stream .m3u8 para ${widget.movie.title}...',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Nenhum stream encontrado — mostra tela de erro com retry
    if (_selectedServer == null || _availableServers.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              Text(
                'Nenhum stream disponível',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Não foi possível encontrar streams para\n"${widget.movie.title}"',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchAndPlayStream,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar Novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Voltar', style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
              ),
            ],
          ),
        ),
      );
    }

    // Se o servidor é embed (backend não conseguiu extrair .m3u8) → WebView
    if (_selectedServer!.type == 'embed') {
      return InAppEmbedPlayer(
        movie: widget.movie,
        server: _selectedServer!,
        allServers: _availableServers,
        onServerSelected: _onServerChanged,
        seasonNumber: widget.movie.isTvShow ? _currentSeason : null,
        episodeNumber: widget.movie.isTvShow ? _currentEpisode : null,
        episodeTitle: widget.movie.isTvShow ? _currentEpisodeTitle : null,
        onNextEpisode: widget.movie.isTvShow ? _playNextEpisode : null,
      );
    }

    // Servidor direto (.m3u8 / .mp4) → MediaKit nativo
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Video(
                controller: _controller,
                fit: _videoFit,
                controls: NoVideoControls,
              ),
            ),

            if (_isBuffering)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 3.5),
                ),
              ),

            if (_showControls) _buildNativeControlsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeControlsOverlay() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.85),
              Colors.black.withOpacity(0.2),
              Colors.black.withOpacity(0.2),
              Colors.black.withOpacity(0.9),
            ],
            stops: const [0.0, 0.25, 0.75, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTopBar(),
              if (!_controlsLocked) _buildCenterControls() else const Spacer(),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  _selectedServer?.name ?? 'Transmissão',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _showServersMenu,
            icon: const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
            label: Text(
              'Servidores',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF1F1F2C),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.white12)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _controlsLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: _controlsLocked ? const Color(0xFFE50914) : Colors.white70,
              size: 22,
            ),
            onPressed: () {
              setState(() => _controlsLocked = !_controlsLocked);
              _startHideControlsTimer();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 42),
          onPressed: () {
            _player.seek(_position - const Duration(seconds: 10));
            _startHideControlsTimer();
          },
        ),
        const SizedBox(width: 36),
        GestureDetector(
          onTap: () {
            _player.playOrPause();
            _startHideControlsTimer();
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withOpacity(0.55),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
        const SizedBox(width: 36),
        IconButton(
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 42),
          onPressed: () {
            _player.seek(_position + const Duration(seconds: 10));
            _startHideControlsTimer();
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final maxDuration = _duration.inMilliseconds.toDouble();
    final currentPos = _position.inMilliseconds.toDouble().clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_controlsLocked)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFE50914),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFE50914),
                overlayColor: const Color(0xFFE50914).withOpacity(0.3),
              ),
              child: Slider(
                value: currentPos,
                max: maxDuration > 0 ? maxDuration : 1.0,
                onChanged: (val) {
                  _player.seek(Duration(milliseconds: val.toInt()));
                  _startHideControlsTimer();
                },
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (!_controlsLocked)
                Row(
                  children: [
                    TextButton(
                      onPressed: _showSpeedMenu,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F2C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 22),
                      onPressed: () {
                        setState(() {
                          if (_videoFit == BoxFit.contain) {
                            _videoFit = BoxFit.cover;
                          } else if (_videoFit == BoxFit.cover) {
                            _videoFit = BoxFit.fill;
                          } else {
                            _videoFit = BoxFit.contain;
                          }
                        });
                        _startHideControlsTimer();
                      },
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showServersMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Servidores de Reprodução',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _availableServers.length,
                    itemBuilder: (context, index) {
                      final server = _availableServers[index];
                      final isCurrent = _selectedServer?.url == server.url;
                      final isPtBr = server.lang == 'PT-BR';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isCurrent ? const Color(0xFFE50914).withOpacity(0.15) : const Color(0xFF1E1E2A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent ? const Color(0xFFE50914) : (isPtBr ? const Color(0xFF009C3B).withOpacity(0.4) : Colors.white12),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isPtBr ? Icons.translate_rounded : Icons.play_circle_fill_rounded,
                            color: isCurrent ? const Color(0xFFE50914) : (isPtBr ? const Color(0xFF009C3B) : Colors.white70),
                          ),
                          title: Text(
                            server.name,
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500),
                          ),
                          subtitle: Text(
                            isPtBr ? 'Áudio Dublado / Legendas PT-BR' : 'Servidor Web Ultra HD',
                            style: GoogleFonts.inter(color: isPtBr ? const Color(0xFF009C3B) : Colors.white38, fontSize: 12),
                          ),
                          trailing: isCurrent ? const Icon(Icons.check_circle_rounded, color: Color(0xFFE50914)) : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                          onTap: () {
                            Navigator.pop(context);
                            _onServerChanged(server);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Velocidade de Reprodução', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: speeds.length,
                    itemBuilder: (context, index) {
                      final s = speeds[index];
                      final isSelected = _playbackSpeed == s;
                      return ListTile(
                        title: Text('${s}x ${s == 1.0 ? "(Normal)" : ""}', style: GoogleFonts.inter(color: isSelected ? const Color(0xFFE50914) : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFFE50914)) : null,
                        onTap: () {
                          _player.setRate(s);
                          setState(() => _playbackSpeed = s);
                          Navigator.pop(context);
                          _startHideControlsTimer();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

