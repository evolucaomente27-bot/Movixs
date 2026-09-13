import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import '../models/movie_item.dart';
import '../models/superflix_stream.dart';
import '../services/tmdb_service.dart';
import '../services/superflix_service.dart';
import '../services/local_stream_proxy.dart';

enum PlayerDisplayMode {
  native,
  webView,
}

class SuperFlixPlayerScreen extends StatefulWidget {
  final MovieItem movie;
  final int? initialSeason;
  final int? initialEpisode;

  const SuperFlixPlayerScreen({
    super.key,
    required this.movie,
    this.initialSeason,
    this.initialEpisode,
  });

  static void navigate(
    BuildContext context,
    MovieItem movie, {
    int? season,
    int? episode,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SuperFlixPlayerScreen(
          movie: movie,
          initialSeason: season,
          initialEpisode: episode,
        ),
      ),
    );
  }

  @override
  State<SuperFlixPlayerScreen> createState() => _SuperFlixPlayerScreenState();
}

class _SuperFlixPlayerScreenState extends State<SuperFlixPlayerScreen> {
  // Serviços
  final SuperFlixService _superFlixService = SuperFlixService.instance;
  final LocalStreamProxy _localProxy = LocalStreamProxy.instance;
  final TMDBService _tmdbService = TMDBService.instance;

  // MediaKit (Player Nativo)
  late final Player _player;
  late final VideoController _videoController;

  // InAppWebView (Mobile / macOS)
  InAppWebViewController? _webViewController;

  // Windows WebView Controller
  final win.WebviewController _winWebviewController = win.WebviewController();
  bool _isWinWebViewInitialized = false;

  // Estado da Reprodução
  bool _isLoading = true;
  String _loadingMessage = 'Conectando à SuperFlix API...';
  PlayerDisplayMode _displayMode = PlayerDisplayMode.native;

  // Streams & Servidores
  List<SuperFlixStreamResult> _allStreams = [];
  SuperFlixStreamResult? _selectedStream;
  String _selectedAudioFilter = 'Dublado'; // 'Dublado' ou 'Legendado'

  // Controle de Episódios (se for série)
  late int _currentSeason;
  late int _currentEpisode;
  List<EpisodeItem> _episodesList = [];
  bool _isLoadingEpisodes = false;

  // Controles do Player Nativo
  bool _showControls = true;
  bool _controlsLocked = false;
  Timer? _hideControlsTimer;
  double _playbackSpeed = 1.0;
  BoxFit _videoFit = BoxFit.contain;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _bufSub;

  // Lista de domínios conhecidos de anúncios e popunders a serem bloqueados
  static const List<String> _blockedAdDomains = [
    'adsterra',
    'popcash',
    'popads',
    'propellerads',
    'exoclick',
    'juicyads',
    'onclick',
    'adkeeper',
    'bet365',
    '1xbet',
    'blaze',
    'betano',
    'doubleclick',
    'google-analytics',
    'googlesyndication',
    'track',
    'redirect',
    'northwavepoint',
    'cheq',
    'adnxs',
    'trafficjunky',
    'syndication',
  ];

  @override
  void initState() {
    super.initState();

    _currentSeason = widget.initialSeason ?? 1;
    _currentEpisode = widget.initialEpisode ?? 1;

    // Configuração de tela cheia imersiva e orientação horizontal
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    // Inicialização do MediaKit Player
    _player = Player();
    _videoController = VideoController(_player);

    _setupPlayerListeners();
    _initMediaAndResolveStreams();

    if (widget.movie.isSeries) {
      _loadEpisodesForSeason(_currentSeason);
    }
  }

  void _setupPlayerListeners() {
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
  }

  /// Inicializa e extrai streams da SuperFlix API
  Future<void> _initMediaAndResolveStreams() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Resolvendo streams na SuperFlix...';
    });

    final playerUrl = _superFlixService.buildPlayerUrl(
      tmdbId: widget.movie.id,
      season: widget.movie.isSeries ? _currentSeason : null,
      episode: widget.movie.isSeries ? _currentEpisode : null,
    );

    debugPrint('[SuperFlixPlayer] 🎬 Resolvendo URL: $playerUrl');

    final streams = await _superFlixService.extractStreamSources(playerUrl);

    if (!mounted) return;

    if (streams.isEmpty) {
      setState(() {
        _allStreams = [];
        _selectedStream = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _allStreams = streams;
    });

    // Filtra preferencialmente pelo áudio selecionado ('Dublado')
    final filtered = _getFilteredStreams();
    final preferred = filtered.isNotEmpty ? filtered.first : streams.first;

    await _playStream(preferred);
  }

  List<SuperFlixStreamResult> _getFilteredStreams() {
    final matchingAudio = _allStreams
        .where((s) => s.audioType.toLowerCase() == _selectedAudioFilter.toLowerCase())
        .toList();

    // Prioriza streams diretos primeiro, depois embeds
    final direct = matchingAudio.where((s) => s.isDirectStream).toList();
    final embeds = matchingAudio.where((s) => !s.isDirectStream).toList();

    return [...direct, ...embeds];
  }

  /// Inicia a reprodução do stream selecionado (Nativo via Proxy ou WebView)
  Future<void> _playStream(SuperFlixStreamResult stream) async {
    setState(() {
      _selectedStream = stream;
      _isLoading = true;
      _loadingMessage = stream.isDirectStream
          ? 'Iniciando LocalStreamProxy...'
          : 'Preparando WebView Anti-Ad...';
    });

    if (stream.isDirectStream) {
      // 1. TENTATIVA PRIMÁRIA: Player Nativo com LocalStreamProxy
      try {
        final targetUri = Uri.parse(stream.url);
        final localUri = await _localProxy.startProxy(
          targetUri: targetUri,
          forwardHeaders: stream.headers,
        );

        debugPrint('[SuperFlixPlayer] 🎯 Reproduzindo nativamente via Proxy: $localUri');

        _displayMode = PlayerDisplayMode.native;
        await _player.open(Media(localUri.toString()));
        await _player.play();

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          _startHideControlsTimer();
        }
      } catch (e) {
        debugPrint('[SuperFlixPlayer] ⚠️ Falha ao tocar stream nativo: $e. Ativando fallback WebView...');
        _switchToWebViewFallback(stream);
      }
    } else {
      // 2. FALLBACK INTELIGENTE: WebView com Bloqueador de Anúncios
      _switchToWebViewFallback(stream);
    }
  }

  void _switchToWebViewFallback(SuperFlixStreamResult stream) {
    _player.pause();
    _localProxy.stop();

    setState(() {
      _displayMode = PlayerDisplayMode.webView;
      _isLoading = true;
      _loadingMessage = 'Carregando player seguro...';
    });

    if (!kIsWeb && Platform.isWindows) {
      _initWindowsWebView(stream.url);
    } else {
      _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(stream.url)),
      );
    }
  }

  Future<void> _initWindowsWebView(String url) async {
    try {
      if (!_isWinWebViewInitialized) {
        await _winWebviewController.initialize();
        await _winWebviewController.setBackgroundColor(Colors.black);
        await _winWebviewController.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
        _isWinWebViewInitialized = true;
      }
      await _winWebviewController.loadUrl(url);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[SuperFlixPlayer] Erro WebView Windows: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEpisodesForSeason(int season) async {
    setState(() => _isLoadingEpisodes = true);
    final episodes = await _tmdbService.getSeriesEpisodes(widget.movie.id, season);
    if (mounted) {
      setState(() {
        _episodesList = episodes;
        _isLoadingEpisodes = false;
      });
    }
  }

  void _onEpisodeSelected(EpisodeItem episode) {
    setState(() {
      _currentSeason = episode.seasonNumber;
      _currentEpisode = episode.episodeNumber;
    });
    _initMediaAndResolveStreams();
  }

  void _onAudioFilterChanged(String audioType) {
    setState(() {
      _selectedAudioFilter = audioType;
    });
    final filtered = _getFilteredStreams();
    if (filtered.isNotEmpty) {
      _playStream(filtered.first);
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

    _player.dispose();
    _localProxy.stop();

    if (!kIsWeb && Platform.isWindows) {
      _winWebviewController.dispose();
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camada de Reprodução (Nativa ou WebView)
          if (_displayMode == PlayerDisplayMode.native)
            _buildNativePlayer()
          else
            _buildWebViewPlayer(),

          // 2. Indicador de Carregamento
          if (_isLoading)
            _buildLoadingOverlay(),

          // 3. Controles Sobrepostos (No modo Nativo)
          if (_displayMode == PlayerDisplayMode.native && _showControls)
            _buildNativeControlsOverlay(),

          // 4. Barra Superior Flutuante Minimalista (No modo WebView)
          if (_displayMode == PlayerDisplayMode.webView)
            _buildWebViewFloatingHeader(),
        ],
      ),
    );
  }

  Widget _buildNativePlayer() {
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(
              controller: _videoController,
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
                child: const CircularProgressIndicator(
                  color: Color(0xFFE50914),
                  strokeWidth: 3.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebViewPlayer() {
    final streamUrl = _selectedStream?.url ?? _superFlixService.buildPlayerUrl(tmdbId: widget.movie.id);

    // No Windows utiliza webview_windows
    if (!kIsWeb && Platform.isWindows && _isWinWebViewInitialized) {
      return win.Webview(_winWebviewController);
    }

    // No Android, iOS, macOS utiliza flutter_inappwebview
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(streamUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        isElementFullscreenEnabled: true,
        allowsInlineMediaPlayback: true,
        transparentBackground: false,
      ),
      onCreateWindow: (controller, createWindowAction) async {
        // BLOQUEIO TOTAL DE POPUPS: Bloqueia abertura de novas janelas/anúncios
        debugPrint('[SuperFlixWebView] 🚫 Popup bloqueado: ${createWindowAction.request.url}');
        return false;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri == null) return NavigationActionPolicy.CANCEL;

        final urlStr = uri.toString().toLowerCase();

        // Bloqueia redes de anúncios conhecidas
        for (final blocked in _blockedAdDomains) {
          if (urlStr.contains(blocked)) {
            debugPrint('[SuperFlixWebView] 🚫 URL de anúncio bloqueada: $urlStr');
            return NavigationActionPolicy.CANCEL;
          }
        }

        // Permite navegação apenas dentro da SuperFlix ou CDNs legítimas
        if (urlStr.contains('superflix') ||
            urlStr.contains('embed') ||
            urlStr.contains('warez') ||
            urlStr.contains('player') ||
            urlStr.contains('m3u8')) {
          return NavigationActionPolicy.ALLOW;
        }

        debugPrint('[SuperFlixWebView] 🚫 Redirecionamento externo cancelado: $urlStr');
        return NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (controller, url) async {
        if (mounted) setState(() => _isLoading = false);

        // INJEÇÃO DE CSS/JS ANTI-AD: Remove sobreposições e força 100% da tela
        await controller.injectCSSCode(source: '''
          html, body {
            width: 100vw !important;
            height: 100vh !important;
            margin: 0 !important;
            padding: 0 !important;
            overflow: hidden !important;
            background-color: #000 !important;
          }
          iframe, video, .player, #player, .video-js {
            width: 100vw !important;
            height: 100vh !important;
            max-width: 100vw !important;
            max-height: 100vh !important;
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            z-index: 9999 !important;
          }
          .ad, .ads, [class*="ad-"], [id*="ad-"], [class*="banner"], .popup, [id*="pop"] {
            display: none !important;
            visibility: hidden !important;
            pointer-events: none !important;
          }
        ''');

        // Dispara reprodução automática no player embutido se existir tag <video>
        await controller.evaluateJavascript(source: '''
          try {
            var vids = document.getElementsByTagName('video');
            if (vids.length > 0) {
              vids[0].play();
            }
          } catch(e) {}
        ''');
      },
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFFE50914),
              strokeWidth: 3.5,
            ),
            const SizedBox(height: 16),
            Text(
              _loadingMessage,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              widget.movie.isSeries
                  ? '${widget.movie.title} • S${_currentSeason}E$_currentEpisode'
                  : widget.movie.title,
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebViewFloatingHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
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
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Player Seguro Anti-Ad (${_selectedStream?.audioType ?? _selectedAudioFilter})',
                      style: GoogleFonts.inter(color: const Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              _buildAudioSelectorChips(),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _showServersBottomSheet,
                icon: const Icon(Icons.dns_rounded, color: Colors.white, size: 16),
                label: Text(
                  'Servidores',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF1F1F2C),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
            ],
          ),
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
              Colors.black.withOpacity(0.25),
              Colors.black.withOpacity(0.25),
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
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
                  widget.movie.isSeries
                      ? 'Temporada $_currentSeason • Episódio $_currentEpisode (${_selectedStream?.audioType ?? _selectedAudioFilter})'
                      : '${_selectedStream?.serverName ?? "SuperFlix Nativo"} • ${_selectedStream?.audioType ?? _selectedAudioFilter}',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          _buildAudioSelectorChips(),
          const SizedBox(width: 8),
          if (widget.movie.isSeries) ...[
            TextButton.icon(
              onPressed: _showEpisodesModal,
              icon: const Icon(Icons.video_library_rounded, color: Colors.white, size: 16),
              label: Text(
                'Episódios',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF1F1F2C),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          TextButton.icon(
            onPressed: _showServersBottomSheet,
            icon: const Icon(Icons.dns_rounded, color: Colors.white, size: 16),
            label: Text(
              'Servidores',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF1F1F2C),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.white12),
              ),
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

  Widget _buildAudioSelectorChips() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAudioChip('Dublado'),
          _buildAudioChip('Legendado'),
        ],
      ),
    );
  }

  Widget _buildAudioChip(String label) {
    final isSelected = _selectedAudioFilter.toLowerCase() == label.toLowerCase();
    return GestureDetector(
      onTap: () => _onAudioFilterChanged(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE50914) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
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
    final currentPos = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
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
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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

  void _showServersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Servidores SuperFlix',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _allStreams.length,
                    itemBuilder: (context, index) {
                      final stream = _allStreams[index];
                      final isCurrent = _selectedStream?.url == stream.url;
                      final isDub = stream.isDublado;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFFE50914).withOpacity(0.15)
                              : const Color(0xFF1E1E2A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFFE50914)
                                : (isDub
                                    ? const Color(0xFF009C3B).withOpacity(0.4)
                                    : Colors.white12),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            stream.isDirectStream
                                ? Icons.flash_on_rounded
                                : Icons.web_asset_rounded,
                            color: isCurrent
                                ? const Color(0xFFE50914)
                                : (stream.isDirectStream
                                    ? const Color(0xFFFFB800)
                                    : Colors.white70),
                          ),
                          title: Text(
                            stream.serverName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            '${stream.audioType} • ${stream.isDirectStream ? "Nativo (Proxy Local)" : "Player Web Anti-Ad"} • ${stream.quality}',
                            style: GoogleFonts.inter(
                              color: isDub ? const Color(0xFF00C853) : Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFFE50914))
                              : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                          onTap: () {
                            Navigator.pop(context);
                            _playStream(stream);
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

  void _showEpisodesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Temporada $_currentSeason - Episódios',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoadingEpisodes)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFE50914)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _episodesList.length,
                      itemBuilder: (context, index) {
                        final ep = _episodesList[index];
                        final isCurrent = ep.episodeNumber == _currentEpisode;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0xFFE50914).withOpacity(0.15)
                                : const Color(0xFF1E1E2A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCurrent ? const Color(0xFFE50914) : Colors.white12,
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isCurrent ? const Color(0xFFE50914) : const Color(0xFF2B2B3B),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  'E${ep.episodeNumber}',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              ep.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              ep.overview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                            ),
                            trailing: isCurrent
                                ? const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFE50914))
                                : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                            onTap: () {
                              Navigator.pop(context);
                              _onEpisodeSelected(ep);
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                Text(
                  'Velocidade de Reprodução',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
                        title: Text(
                          '${s}x ${s == 1.0 ? "(Normal)" : ""}',
                          style: GoogleFonts.inter(
                            color: isSelected ? const Color(0xFFE50914) : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: Color(0xFFE50914))
                            : null,
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
