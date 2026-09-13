import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/services/doh_service.dart';
import '../../data/models/movie.dart';
import '../../data/repositories/streaming_repository.dart';
import '../../main.dart';

/// Player WebView protegido em Sandbox com NextDNS DoH,
/// aceleração por hardware GPU, controles nativos avançados e atalhos de teclado.
class InAppEmbedPlayer extends StatefulWidget {
  final Movie movie;
  final StreamingServer server;
  final List<StreamingServer> allServers;
  final Function(StreamingServer) onServerSelected;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final VoidCallback? onNextEpisode;

  const InAppEmbedPlayer({
    super.key,
    required this.movie,
    required this.server,
    required this.allServers,
    required this.onServerSelected,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.onNextEpisode,
  });

  @override
  State<InAppEmbedPlayer> createState() => _InAppEmbedPlayerState();
}

class _InAppEmbedPlayerState extends State<InAppEmbedPlayer> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _loadingTimeoutTimer;
  int _blockedPopupsCount = 0;

  // Estados dos controles nativos do player
  bool _isPlaying = true;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  String _aspectRatioMode = 'contain'; // 'contain' (Original), 'cover' (Preencher), 'fill' (Esticar)
  bool _isFullscreen = false;

  final FocusNode _keyboardFocusNode = FocusNode();

  // Script JS injetado em AT_DOCUMENT_START em todas as frames e iframes
  static const String _antiAdSandboxJs = '''
    (function() {
      'use strict';
      
      // 1. Neutraliza window.open (impede abertura de abas externas/popunders)
      try {
        Object.defineProperty(window, 'open', {
          configurable: false,
          writable: false,
          value: function(url, target, features) {
            console.warn('[Movixs Sandbox] 🛡️ window.open bloqueado:', url);
            return null;
          }
        });
      } catch(e) {
        window.open = function() { return null; };
      }

      // 2. Neutraliza caixas de diálogo abusivas
      window.alert = function() { console.warn('[Movixs Sandbox] alert suprimido'); };
      window.confirm = function() { return false; };
      window.prompt = function() { return null; };

      // 3. Impede páginas de bloquear fechamento ou navegação
      try {
        Object.defineProperty(window, 'onbeforeunload', {
          configurable: false,
          get: function() { return null; },
          set: function(val) {}
        });
      } catch(e) {}

      // 4. Interceptador de cliques em links maliciosos e popunders (capture phase)
      document.addEventListener('click', function(e) {
        let el = e.target;
        while (el && el !== document.body && el !== document.documentElement) {
          if (el.tagName === 'A') {
            const href = el.getAttribute('href') || '';
            const target = el.getAttribute('target');
            if (target === '_blank') {
              el.removeAttribute('target');
            }
            if (href.startsWith('http://') || href.startsWith('https://') || href.startsWith('//')) {
              try {
                const destHost = new URL(href, window.location.href).hostname.toLowerCase();
                const currHost = window.location.hostname.toLowerCase();
                const allowed = destHost === currHost ||
                                destHost.includes('vidsrc') ||
                                destHost.includes('vidlink') ||
                                destHost.includes('embed') ||
                                destHost.includes('stream') ||
                                destHost.includes('google') ||
                                destHost.includes('tmdb');
                if (!allowed) {
                  console.warn('[Movixs Sandbox] 🛡️ Clique externo bloqueado:', href);
                  e.preventDefault();
                  e.stopPropagation();
                  return false;
                }
              } catch(err) {}
            }
          }
          el = el.parentElement;
        }
      }, true);

      // 5. Removedor contínuo de overlays invisíveis e botões falsos de play
      function neutralizeClickJackingOverlays() {
        try {
          const elements = document.querySelectorAll('div, a, span, section');
          for (let i = 0; i < elements.length; i++) {
            const el = elements[i];
            const style = window.getComputedStyle(el);
            const zIndex = parseInt(style.zIndex, 10);
            if (zIndex >= 999 && (style.position === 'fixed' || style.position === 'absolute')) {
              const rect = el.getBoundingClientRect();
              if (rect.width >= window.innerWidth * 0.75 && rect.height >= window.innerHeight * 0.75) {
                if (!el.querySelector('video') && !el.querySelector('iframe') && el.tagName !== 'VIDEO') {
                  console.warn('[Movixs Sandbox] 🛡️ Overlay de anúncio removido:', el);
                  el.remove();
                }
              }
            }
          }

          // Remove botões falsos de play e traps de clique
          const fakePlays = document.querySelectorAll(
            '.jw-preview, .vjs-big-play-button, .play-overlay, #play-button, .play-wrapper, [class*="fake-play"], [id*="fake-play"], [class*="click-trap"]'
          );
          for (let f = 0; f < fakePlays.length; f++) {
            fakePlays[f].remove();
          }

          const iframes = document.querySelectorAll('iframe');
          for (let j = 0; j < iframes.length; j++) {
            const src = (iframes[j].src || '').toLowerCase();
            if (src.includes('pop') || src.includes('banner') || src.includes('doubleclick') ||
                src.includes('adservice') || src.includes('propeller') || src.includes('syndication')) {
              iframes[j].remove();
            }
          }
        } catch(e) {}
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
          neutralizeClickJackingOverlays();
          setInterval(neutralizeClickJackingOverlays, 1000);
        });
      } else {
        neutralizeClickJackingOverlays();
        setInterval(neutralizeClickJackingOverlays, 1000);
      }
    })();
  ''';

  // CSS defensivo para ocultar anúncios e garantir tema escuro de cinema
  static const String _antiAdCss = '''
    iframe[src*="ad"], iframe[src*="pop"], iframe[src*="banner"],
    div[class*="ad-"], div[id*="ad-"], div[class*="banner"],
    div[class*="sponsor"], div[id*="pop"],
    a[href*="whomeeto"], a[href*="jireea"], a[href*="bblaa"], a[href*="bet365"] {
      display: none !important;
      visibility: hidden !important;
      pointer-events: none !important;
      width: 0 !important;
      height: 0 !important;
    }
    body, html {
      background-color: #000 !important;
      margin: 0 !important;
      padding: 0 !important;
    }
  ''';

  // Script JS para auto-selecionar Áudio Dublado e Legendas em PT-BR
  static const String _autoSelectPtBrJs = '''
    (function() {
      'use strict';

      // 1. Pre-seed de preferências no localStorage e sessionStorage
      function applyStoragePrefs() {
        try {
          var keys = {
            'selectedLanguage': 'portuguese',
            'subtitles_language': 'Portuguese',
            'subtitle_language': 'pt-BR',
            'subtitle_lang': 'pt',
            'sub_lang': 'pt',
            'subtitles': 'pt-BR',
            'caption_language': 'Portuguese',
            'captions_lang': 'pt-BR',
            'jwplayer.captionLabel': 'Portuguese',
            'vjs_subtitle': 'pt',
            'preferred_language': 'pt-BR',
            'player_language': 'pt-BR',
            'audio_language': 'Portuguese',
            'audio_lang': 'pt-BR',
            'audioTrack': 'Portuguese',
            'vidsrc_subtitles': 'pt-BR',
            'vidsrc_audio': 'pt-BR',
            'vidlink_language': 'pt',
            'vidlink_subtitles': 'Portuguese',
            'preferredAudio': 'Portuguese',
            'preferredSubtitles': 'Portuguese'
          };
          for (var k in keys) {
            if (Object.prototype.hasOwnProperty.call(keys, k)) {
              try {
                if (!localStorage.getItem(k)) localStorage.setItem(k, keys[k]);
                if (!sessionStorage.getItem(k)) sessionStorage.setItem(k, keys[k]);
              } catch(err) {}
            }
          }
        } catch(e) {}
      }
      applyStoragePrefs();

      // 2. Classificador e pontuação de idioma PT-BR
      function getPtScore(str) {
        if (!str || typeof str !== 'string') return 0;
        var s = str.toLowerCase().trim();
        if (s.includes('brasil') || s.includes('brazil') || s.includes('pt-br') || s.includes('pt_br') || s.includes('ptbr')) return 100;
        if (s.includes('dublado')) return 95;
        if (s.includes('portugu') || s.includes('portugues') || s.includes('portuguese')) return 90;
        if (s.includes('pob')) return 80;
        if (s === 'pt' || s.startsWith('pt-')) return 70;
        return 0;
      }
      function isPt(str) { return getPtScore(str) > 0; }

      // 3. Configuração de elemento <video> (HTML5 TextTracks e AudioTracks)
      function autoConfigureVideo(v) {
        if (!v) return;

        // Subtítulos / Legendas
        try {
          if (v.textTracks && v.textTracks.length > 0) {
            var bestTrack = null;
            var highestScore = 0;
            for (var i = 0; i < v.textTracks.length; i++) {
              var t = v.textTracks[i];
              var score = Math.max(getPtScore(t.label), getPtScore(t.language));
              if (score > highestScore) {
                highestScore = score;
                bestTrack = t;
              }
            }
            if (bestTrack && bestTrack.mode !== 'showing') {
              console.log('[Movixs Auto-PT-BR] 🇧🇷 Ativando legenda PT-BR:', bestTrack.label || bestTrack.language);
              for (var j = 0; j < v.textTracks.length; j++) {
                if (v.textTracks[j] !== bestTrack) {
                  v.textTracks[j].mode = 'disabled';
                }
              }
              bestTrack.mode = 'showing';
            }
          }
        } catch(e) {}

        // Áudio Dublado
        try {
          if (v.audioTracks && v.audioTracks.length > 0) {
            var bestAudio = null;
            var highestAudioScore = 0;
            for (var k = 0; k < v.audioTracks.length; k++) {
              var a = v.audioTracks[k];
              var aScore = Math.max(getPtScore(a.label), getPtScore(a.language));
              if (aScore > highestAudioScore) {
                highestAudioScore = aScore;
                bestAudio = a;
              }
            }
            if (bestAudio && !bestAudio.enabled) {
              console.log('[Movixs Auto-PT-BR] 🇧🇷 Ativando áudio dublado PT-BR:', bestAudio.label || bestAudio.language);
              for (var m = 0; m < v.audioTracks.length; m++) {
                v.audioTracks[m].enabled = false;
              }
              bestAudio.enabled = true;
            }
          }
        } catch(e) {}
      }

      // 4. Suporte a Vidstack Player (<media-player>)
      function autoConfigureVidstack(doc) {
        try {
          var players = doc.querySelectorAll('media-player');
          for (var p = 0; p < players.length; p++) {
            var mp = players[p];
            if (mp.textTracks && mp.textTracks.length > 0) {
              var best = null, maxS = 0;
              for (var i = 0; i < mp.textTracks.length; i++) {
                var t = mp.textTracks[i];
                var s = Math.max(getPtScore(t.label), getPtScore(t.language));
                if (s > maxS) { maxS = s; best = t; }
              }
              if (best && best.mode !== 'showing') {
                best.mode = 'showing';
                if (typeof best.select === 'function') best.select();
                console.log('[Movixs Auto-PT-BR] 🇧🇷 Vidstack legenda ativada:', best.label);
              }
            }
            if (mp.audioTracks && mp.audioTracks.length > 0) {
              var bestA = null, maxAS = 0;
              for (var j = 0; j < mp.audioTracks.length; j++) {
                var a = mp.audioTracks[j];
                var as = Math.max(getPtScore(a.label), getPtScore(a.language));
                if (as > maxAS) { maxAS = as; bestA = a; }
              }
              if (bestA && !bestA.selected) {
                bestA.selected = true;
                if (typeof bestA.select === 'function') bestA.select();
                console.log('[Movixs Auto-PT-BR] 🇧🇷 Vidstack áudio dublado ativado:', bestA.label);
              }
            }
          }
        } catch(e) {}
      }

      // 5. Suporte a JWPlayer (window.jwplayer)
      function autoConfigureJwPlayer(win) {
        try {
          if (typeof win.jwplayer === 'function') {
            var jw = win.jwplayer();
            if (jw && typeof jw.getCaptionsList === 'function') {
              var captions = jw.getCaptionsList() || [];
              var bestIdx = -1, maxScore = 0;
              for (var i = 0; i < captions.length; i++) {
                var c = captions[i];
                var s = Math.max(getPtScore(c.label), getPtScore(c.name), getPtScore(c.id));
                if (s > maxScore) { maxScore = s; bestIdx = i; }
              }
              if (bestIdx >= 0 && jw.getCurrentCaptions() !== bestIdx) {
                jw.setCurrentCaptions(bestIdx);
                console.log('[Movixs Auto-PT-BR] 🇧🇷 JWPlayer legenda ativada:', captions[bestIdx].label);
              }
            }
            if (jw && typeof jw.getAudioTracks === 'function') {
              var tracks = jw.getAudioTracks() || [];
              var bestAIdx = -1, maxAScore = 0;
              for (var j = 0; j < tracks.length; j++) {
                var a = tracks[j];
                var as = Math.max(getPtScore(a.label), getPtScore(a.name));
                if (as > maxAScore) { maxAScore = as; bestAIdx = j; }
              }
              if (bestAIdx >= 0 && jw.getCurrentAudioTrack() !== bestAIdx) {
                jw.setCurrentAudioTrack(bestAIdx);
                console.log('[Movixs Auto-PT-BR] 🇧🇷 JWPlayer áudio dublado ativado:', tracks[bestAIdx].label);
              }
            }
          }
        } catch(e) {}
      }

      // 6. Suporte a Video.js (window.videojs)
      function autoConfigureVideoJs(win) {
        try {
          if (win.videojs && typeof win.videojs.getAllPlayers === 'function') {
            var players = win.videojs.getAllPlayers() || [];
            for (var p = 0; p < players.length; p++) {
              var pl = players[p];
              if (pl.textTracks) {
                var tt = pl.textTracks();
                var bestT = null, maxS = 0;
                for (var i = 0; i < tt.length; i++) {
                  var s = Math.max(getPtScore(tt[i].label), getPtScore(tt[i].language));
                  if (s > maxS) { maxS = s; bestT = tt[i]; }
                }
                if (bestT && bestT.mode !== 'showing') {
                  for (var j = 0; j < tt.length; j++) tt[j].mode = 'disabled';
                  bestT.mode = 'showing';
                }
              }
              if (pl.audioTracks) {
                var at = pl.audioTracks();
                var bestA = null, maxAS = 0;
                for (var k = 0; k < at.length; k++) {
                  var as = Math.max(getPtScore(at[k].label), getPtScore(at[k].language));
                  if (as > maxAS) { maxAS = as; bestA = at[k]; }
                }
                if (bestA && !bestA.enabled) {
                  for (var m = 0; m < at.length; m++) at[m].enabled = false;
                  bestA.enabled = true;
                }
              }
            }
          }
        } catch(e) {}
      }

      // 7. Suporte a HLS.js (window.hls)
      function autoConfigureHls(win) {
        try {
          if (win.hls) {
            if (win.hls.subtitleTracks && win.hls.subtitleTracks.length > 0) {
              var bestIdx = -1, maxS = 0;
              for (var i = 0; i < win.hls.subtitleTracks.length; i++) {
                var st = win.hls.subtitleTracks[i];
                var s = Math.max(getPtScore(st.name), getPtScore(st.lang));
                if (s > maxS) { maxS = s; bestIdx = i; }
              }
              if (bestIdx >= 0 && win.hls.subtitleTrack !== bestIdx) {
                win.hls.subtitleTrack = bestIdx;
              }
            }
            if (win.hls.audioTracks && win.hls.audioTracks.length > 0) {
              var bestAIdx = -1, maxAS = 0;
              for (var j = 0; j < win.hls.audioTracks.length; j++) {
                var at = win.hls.audioTracks[j];
                var as = Math.max(getPtScore(at.name), getPtScore(at.lang));
                if (as > maxAS) { maxAS = as; bestAIdx = j; }
              }
              if (bestAIdx >= 0 && win.hls.audioTrack !== bestAIdx) {
                win.hls.audioTrack = bestAIdx;
              }
            }
          }
        } catch(e) {}
      }

      // 8. Automação de Seletores e Menus na Interface Web (Selects e Botões)
      function autoConfigureDomUI(doc) {
        try {
          var selects = doc.querySelectorAll('select');
          for (var s = 0; s < selects.length; s++) {
            var sel = selects[s];
            for (var i = 0; i < sel.options.length; i++) {
              var opt = sel.options[i];
              if (isPt(opt.text) || isPt(opt.value) || isPt(opt.label)) {
                if (sel.selectedIndex !== i) {
                  sel.selectedIndex = i;
                  sel.dispatchEvent(new Event('change', { bubbles: true }));
                  sel.dispatchEvent(new Event('input', { bubbles: true }));
                  console.log('[Movixs Auto-PT-BR] 🇧🇷 Selecionado no menu select:', opt.text);
                }
                break;
              }
            }
          }

          var candidateElements = doc.querySelectorAll(
            '[role="menuitem"], [role="option"], [data-lang], button, li, .vjs-menu-item, [class*="track-item"], [class*="subtitle-item"]'
          );
          for (var c = 0; c < candidateElements.length; c++) {
            var el = candidateElements[c];
            var text = el.textContent || '';
            if (isPt(text)) {
              var isSelected = el.classList.contains('active') ||
                               el.classList.contains('selected') ||
                               el.getAttribute('aria-checked') === 'true' ||
                               el.getAttribute('aria-selected') === 'true';
              if (!isSelected) {
                el.click();
                console.log('[Movixs Auto-PT-BR] 🇧🇷 Clicado item PT-BR no player:', text.trim());
              }
            }
          }
        } catch(e) {}
      }

      // 9. Varredura recursiva da árvore de frames
      function scanTree(win) {
        try {
          if (!win || !win.document) return;
          var doc = win.document;
          var vids = doc.querySelectorAll('video');
          for (var i = 0; i < vids.length; i++) {
            autoConfigureVideo(vids[i]);
          }
          autoConfigureVidstack(doc);
          autoConfigureJwPlayer(win);
          autoConfigureVideoJs(win);
          autoConfigureHls(win);
          autoConfigureDomUI(doc);

          for (var j = 0; j < win.frames.length; j++) {
            scanTree(win.frames[j]);
          }
        } catch(e) {}
      }

      // 10. Exposição global para chamadas nativas do Flutter
      window.movixsForceAutoPtBr = function() {
        applyStoragePrefs();
        scanTree(window);
        return true;
      };

      // 11. Agendamento contínuo resiliente
      scanTree(window);
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
          applyStoragePrefs();
          scanTree(window);
        });
      }
      window.addEventListener('load', function() {
        applyStoragePrefs();
        scanTree(window);
      });

      setInterval(function() {
        scanTree(window);
      }, 1200);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _startHideControlsTimer();
    _startLoadingTimeout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant InAppEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.url != widget.server.url) {
      _loadServerUrl(widget.server.url);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _loadingTimeoutTimer?.cancel();
    _keyboardFocusNode.dispose();
    _webViewController = null;
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 3800), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _startLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
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

  void _loadServerUrl(String url) {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
      _isPlaying = true;
    });
    _startLoadingTimeout();
    try {
      _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    } catch (e) {
      debugPrint('[InAppEmbedPlayer] Erro ao carregar URL: $e');
    }
  }

  // ==========================================
  // DEEP JS VIDEO BRIDGE (CONTROLES NATIVOS)
  // ==========================================

  Future<dynamic> _evaluateDeepVideoJs(String jsBody) async {
    if (_webViewController == null) return null;
    final wrappedCode = '''
      (function() {
        function findVideo(win) {
          try {
            var v = win.document.querySelector('video');
            if (v) return v;
            for (var i = 0; i < win.frames.length; i++) {
              var fv = findVideo(win.frames[i]);
              if (fv) return fv;
            }
          } catch(e) {}
          return null;
        }
        var vid = findVideo(window);
        $jsBody
      })()
    ''';
    try {
      return await _webViewController?.evaluateJavascript(source: wrappedCode);
    } catch (e) {
      debugPrint('[InAppEmbedPlayer] Erro no bridge JS do vídeo: $e');
      return null;
    }
  }

  Future<void> _togglePlayPause() async {
    final res = await _evaluateDeepVideoJs('''
      if (vid) {
        if (vid.paused) {
          vid.play().catch(function() {});
          return true;
        } else {
          vid.pause();
          return false;
        }
      }
      return null;
    ''');

    if (mounted) {
      setState(() {
        if (res is bool) {
          _isPlaying = res;
        } else {
          _isPlaying = !_isPlaying;
        }
      });
      _startHideControlsTimer();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    await _evaluateDeepVideoJs('''
      if (vid) {
        vid.currentTime = Math.max(0, vid.currentTime + ($seconds));
        return vid.currentTime;
      }
    ''');
    _startHideControlsTimer();
  }

  Future<void> _toggleMute() async {
    final res = await _evaluateDeepVideoJs('''
      if (vid) {
        vid.muted = !vid.muted;
        return vid.muted;
      }
      return null;
    ''');

    if (mounted) {
      setState(() {
        if (res is bool) {
          _isMuted = res;
        } else {
          _isMuted = !_isMuted;
        }
      });
      _startHideControlsTimer();
    }
  }

  Future<void> _setPlaybackSpeed(double rate) async {
    await _evaluateDeepVideoJs('''
      if (vid) {
        vid.playbackRate = $rate;
        return vid.playbackRate;
      }
    ''');

    if (mounted) {
      setState(() => _playbackSpeed = rate);
      _startHideControlsTimer();
    }
  }

  Future<void> _cycleAspectRatio() async {
    String nextMode;
    if (_aspectRatioMode == 'contain') {
      nextMode = 'cover';
    } else if (_aspectRatioMode == 'cover') {
      nextMode = 'fill';
    } else {
      nextMode = 'contain';
    }

    await _evaluateDeepVideoJs('''
      function applyFit(win) {
        try {
          var vids = win.document.querySelectorAll('video');
          for (var i = 0; i < vids.length; i++) {
            vids[i].style.objectFit = '$nextMode';
          }
          for (var j = 0; j < win.frames.length; j++) {
            applyFit(win.frames[j]);
          }
        } catch(e) {}
      }
      applyFit(window);
    ''');

    if (mounted) {
      setState(() => _aspectRatioMode = nextMode);
      _startHideControlsTimer();
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    _startHideControlsTimer();
  }

  /// Força a re-sincronização e seleção de Áudio Dublado e Legendas em PT-BR
  Future<void> _forceSelectPtBr({bool showToast = false}) async {
    try {
      await _webViewController?.evaluateJavascript(source: '''
        (function() {
          if (typeof window.movixsForceAutoPtBr === 'function') {
            return window.movixsForceAutoPtBr();
          }
          return false;
        })()
      ''');
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Text('🇧🇷 ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text(
                    'Sincronização de Áudio Dublado e Legendas PT-BR executada!',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF161622),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('[InAppEmbedPlayer] Erro ao forçar seleção PT-BR: $e');
    }
  }

  // ==========================================
  // ATALHOS DE TECLADO (WINDOWS DESKTOP)
  // ==========================================

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePlayPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyL) {
      _forceSelectPtBr(showToast: true);
    } else if (key == LogicalKeyboardKey.keyN) {
      _tryNextServer();
    } else if (key == LogicalKeyboardKey.keyR) {
      _webViewController?.reload();
    } else if (key == LogicalKeyboardKey.escape && _isFullscreen) {
      setState(() => _isFullscreen = false);
    }
  }

  Future<void> _openInExternalBrowser() async {
    try {
      final uri = Uri.parse(widget.server.url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[InAppEmbedPlayer] Erro ao abrir navegador externo: $e');
    }
  }

  void _tryNextServer() {
    final currentIndex = widget.allServers.indexWhere((s) => s.url == widget.server.url);
    if (currentIndex != -1 && currentIndex + 1 < widget.allServers.length) {
      widget.onServerSelected(widget.allServers[currentIndex + 1]);
    } else if (widget.allServers.isNotEmpty) {
      widget.onServerSelected(widget.allServers.first);
    }
  }

  // Dialog de Telemetria e Informações do NextDNS DoH
  void _showNextDnsInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161622),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF009C3B).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded, color: Color(0xFF009C3B), size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Proteção NextDNS DoH',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Resolvedor DNS:', 'NextDNS Encrypted DoH'),
            _buildInfoRow('Endpoint:', DohService.instance.nextDnsEndpointUrl),
            _buildInfoRow('Status Criptografia:', 'Ativa (HTTPS / TLS 1.3)'),
            _buildInfoRow('Popups / Ads Neutralizados:', '$_blockedPopupsCount eventos'),
            _buildInfoRow('Aceleração GPU:', 'Direct3D11 / Chromium Raster Ativa'),
            _buildInfoRow('Sandbox Web:', 'Ativo (Frames isoladas)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                'O NextDNS resolve consultas com criptografia de ponta a ponta e bloqueia ad-servers e rastreadores antes mesmo do download de dados.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Entendi', style: GoogleFonts.inter(color: const Color(0xFFE50914), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white60, fontSize: 12)),
          Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) {
            if (!_showControls) {
              setState(() => _showControls = true);
            }
            _startHideControlsTimer();
          },
          child: GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Camada WebView Nativo Protegido (PERMANECE SEMPRE MONTADO NO WIDGET TREE)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.server.url)),
                  webViewEnvironment: globalWebViewEnvironment,
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    supportMultipleWindows: false,
                    javaScriptCanOpenWindowsAutomatically: false,
                    transparentBackground: false,
                    useShouldOverrideUrlLoading: true,
                    userAgent:
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    isInspectable: false,
                  ),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    // Injeta sandbox JS em todas as frames e iframes antes do DOM carregar
                    UserScript(
                      source: _antiAdSandboxJs,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: false,
                    ),
                    // Injeta script de seleção automática de Áudio Dublado e Legendas PT-BR
                    UserScript(
                      source: _autoSelectPtBrJs,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: false,
                    ),
                    // Injeta CSS anti-anúncios
                    UserScript(
                      source: '''
                        (function() {
                          var style = document.createElement('style');
                          style.textContent = `$_antiAdCss`;
                          (document.head || document.documentElement).appendChild(style);
                        })();
                      ''',
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: false,
                    ),
                  ]),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    if (mounted) setState(() => _isLoading = true);
                    _startLoadingTimeout();
                  },
                  onLoadStop: (controller, url) {
                    _loadingTimeoutTimer?.cancel();
                    if (mounted) setState(() => _isLoading = false);
                    _forceSelectPtBr();
                  },
                  onCreateWindow: (controller, createWindowAction) async {
                    if (mounted) {
                      setState(() => _blockedPopupsCount++);
                    }
                    debugPrint(
                      '[InAppEmbedPlayer] 🛡️ Sandbox interceptou janela/popup: ${createWindowAction.request.url}',
                    );
                    return true;
                  },
                  onReceivedError: (controller, request, error) {
                    final desc = error.description.toLowerCase();
                    final typeStr = error.type.toString().toLowerCase();

                    if (desc.contains('stopped') ||
                        desc.contains('aborted') ||
                        desc.contains('cancelled') ||
                        desc.contains('canceled') ||
                        desc.contains('blocked') ||
                        desc.contains('redirect failed') ||
                        desc.contains('connection was reset') ||
                        desc.contains('unexpected error') ||
                        desc.contains('operation was canceled') ||
                        typeStr.contains('abort') ||
                        typeStr.contains('cancel')) {
                      return;
                    }

                    if (request.isForMainFrame == false) {
                      return;
                    }

                    debugPrint('[InAppEmbedPlayer] ℹ️ Frame status: ${error.description}');
                  },
                  onReceivedHttpError: (controller, request, errorResponse) {
                    if (request.isForMainFrame == false) return;
                    final status = errorResponse.statusCode ?? 0;
                    if (status >= 500) {
                      debugPrint('[InAppEmbedPlayer] ⚠️ Servidor retornou HTTP $status');
                    }
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    if (uri == null) return NavigationActionPolicy.CANCEL;

                    final urlStr = uri.toString().toLowerCase();

                    // Permite esquemas internos (blob:, data:, about:blank)
                    if (urlStr.startsWith('blob:') ||
                        urlStr.startsWith('data:') ||
                        urlStr.startsWith('about:')) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    // Se for o mesmo domínio do servidor inicial ou subdomínio
                    final currentHost = WebUri(widget.server.url).host.toLowerCase();
                    final requestHost = uri.host.toLowerCase();
                    if (requestHost.isNotEmpty &&
                        (requestHost == currentHost ||
                         requestHost.endsWith('.$currentHost') ||
                         currentHost.endsWith('.$requestHost'))) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    // Lista de palavras-chave permitidas para provedores e CDNs de vídeo
                    const allowedKeywords = [
                      'vidsrc',
                      'vidlink',
                      '2embed',
                      'rivestream',
                      'smashystream',
                      'multiembed',
                      'vsembed',
                      'cloudstream',
                      'rabbitstream',
                      'megacloud',
                      'streamtape',
                      'mixdrop',
                      'filemoon',
                      'doodstream',
                      '.m3u8',
                      '.mp4',
                      '.mpd',
                      'google',
                      'gstatic',
                      'cloudflare',
                      'bunnycdn',
                      'fastly',
                      'akamai',
                      'tmdb',
                    ];

                    for (final keyword in allowedKeywords) {
                      if (urlStr.contains(keyword)) {
                        return NavigationActionPolicy.ALLOW;
                      }
                    }

                    // Bloqueia qualquer outro redirecionamento ou anúncio externo
                    if (mounted) {
                      setState(() => _blockedPopupsCount++);
                    }
                    debugPrint('[InAppEmbedPlayer] 🛡️ Sandbox bloqueou redirecionamento externo: $uri');
                    return NavigationActionPolicy.CANCEL;
                  },
                ),

                // 2. Indicador de Carregamento (Overlay não-bloqueante)
                if (_isLoading && !_hasError)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black54,
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
                              'Carregando ${widget.server.name} com NextDNS DoH...',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 3. Fallback defensivo com opções de recuperação
                if (_hasError)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161622),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 56),
                              const SizedBox(height: 16),
                              Text(
                                'Instabilidade no Servidor',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage != null
                                    ? 'O servidor "${widget.server.name}" apresentou um erro ($_errorMessage). Você pode alternar para outro servidor da lista ou tentar novamente.'
                                    : 'O servidor "${widget.server.name}" não pôde ser carregado. Você pode alternar para outro servidor da lista ou abrir diretamente.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _tryNextServer,
                                    icon: const Icon(Icons.skip_next_rounded),
                                    label: const Text('Próximo Servidor'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE50914),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _loadServerUrl(widget.server.url),
                                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                    label: const Text('Recarregar', style: TextStyle(color: Colors.white)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _openInExternalBrowser,
                                    icon: const Icon(Icons.open_in_browser_rounded, color: Colors.white70),
                                    label: const Text('Navegador Externo', style: TextStyle(color: Colors.white70)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // 4. Barra Superior Flutuante
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  top: _showControls ? 0 : -85,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.95),
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Voltar',
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
                                  widget.seasonNumber != null && widget.episodeNumber != null
                                      ? '${widget.movie.title} • T${widget.seasonNumber}:E${widget.episodeNumber}${widget.episodeTitle != null ? ' "${widget.episodeTitle}"' : ''}'
                                      : widget.movie.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      widget.server.name,
                                      style: GoogleFonts.inter(
                                        color: widget.server.lang == 'PT-BR'
                                            ? const Color(0xFF009C3B)
                                            : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Badge Interativo de Proteção NextDNS DoH
                                    InkWell(
                                      onTap: _showNextDnsInfoDialog,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF009C3B).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF009C3B).withValues(alpha: 0.6)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.shield_rounded, color: Color(0xFF009C3B), size: 11),
                                            const SizedBox(width: 3),
                                            Text(
                                              _blockedPopupsCount > 0
                                                  ? 'NextDNS ($_blockedPopupsCount bloqueados)'
                                                  : 'NextDNS DoH Ativo',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF009C3B),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Badge de Seleção Automática PT-BR (Dublado & Legendas)
                                    InkWell(
                                      onTap: () => _forceSelectPtBr(showToast: true),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF009C3B).withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF009C3B).withValues(alpha: 0.7)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('🇧🇷', style: TextStyle(fontSize: 11)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'PT-BR Auto',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF009C3B),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Botão de Recarregar
                          IconButton(
                            tooltip: 'Recarregar Player (R)',
                            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                            onPressed: () => _webViewController?.reload(),
                          ),
                          // Botão Abrir no Navegador Externo
                          IconButton(
                            tooltip: 'Abrir no Navegador Externo',
                            icon: const Icon(Icons.open_in_browser_rounded, color: Colors.white70, size: 20),
                            onPressed: _openInExternalBrowser,
                          ),
                          const SizedBox(width: 4),
                          // Menu de Troca de Servidores
                          TextButton.icon(
                            onPressed: _showServersMenu,
                            icon: const Icon(Icons.dns_rounded, color: Colors.white, size: 16),
                            label: Text(
                              'Servidores (${widget.allServers.length})',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF1F1F2C),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                ),

                // 5. Barra Inferior Flutuante com Controles de Vídeo Nativos (Aprimoramento do Player)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  bottom: _showControls ? 20 : -85,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 620),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14141E).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Botão Retroceder 10s
                          IconButton(
                            tooltip: 'Retroceder 10s (Seta Esquerda)',
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 22),
                            onPressed: () => _seekRelative(-10),
                          ),

                          // Botão Play / Pause Central
                          IconButton(
                            tooltip: _isPlaying ? 'Pausar (Espaço)' : 'Reproduzir (Espaço)',
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE50914),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            onPressed: _togglePlayPause,
                          ),

                          // Botão Avançar 10s
                          IconButton(
                            tooltip: 'Avançar 10s (Seta Direita)',
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 22),
                            onPressed: () => _seekRelative(10),
                          ),

                          // Botão Próximo Episódio (Séries)
                          if (widget.onNextEpisode != null)
                            IconButton(
                              tooltip: 'Próximo Episódio',
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                              onPressed: widget.onNextEpisode,
                            ),

                          // Botão Mudo / Volume
                          IconButton(
                            tooltip: _isMuted ? 'Desmutar (M)' : 'Mutar (M)',
                            icon: Icon(
                              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: _isMuted ? const Color(0xFFE50914) : Colors.white70,
                              size: 22,
                            ),
                            onPressed: _toggleMute,
                          ),

                          // Botão Legendas e Áudio PT-BR Automático
                          IconButton(
                            tooltip: 'Auto PT-BR: Áudio Dublado & Legendas (L)',
                            icon: const Icon(
                              Icons.subtitles_rounded,
                              color: Color(0xFF009C3B),
                              size: 22,
                            ),
                            onPressed: () => _forceSelectPtBr(showToast: true),
                          ),

                          // Seletor de Velocidade (0.5x, 1x, 1.25x, 1.5x, 2x)
                          PopupMenuButton<double>(
                            tooltip: 'Velocidade de Reprodução',
                            initialValue: _playbackSpeed,
                            onSelected: _setPlaybackSpeed,
                            color: const Color(0xFF1E1E2A),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 0.5, child: Text('0.5x')),
                              const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                              const PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                              const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                              const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                              const PopupMenuItem(value: 2.0, child: Text('2.0x')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_playbackSpeed}x',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),

                          // Botão Aspect Ratio (Contain / Cover / Fill)
                          IconButton(
                            tooltip: 'Aspect Ratio: $_aspectRatioMode',
                            icon: Icon(
                              _aspectRatioMode == 'cover'
                                  ? Icons.crop_free_rounded
                                  : (_aspectRatioMode == 'fill'
                                      ? Icons.aspect_ratio_rounded
                                      : Icons.fit_screen_rounded),
                              color: _aspectRatioMode != 'contain' ? const Color(0xFFE50914) : Colors.white70,
                              size: 20,
                            ),
                            onPressed: _cycleAspectRatio,
                          ),

                          // Botão Alternar Tela Cheia
                          IconButton(
                            tooltip: _isFullscreen ? 'Sair da Tela Cheia (Esc)' : 'Tela Cheia (F)',
                            icon: Icon(
                              _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: _toggleFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Menu de Troca de Servidores
  void _showServersMenu() {
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
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Servidores Disponíveis (${widget.allServers.length})',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.allServers.length,
                    itemBuilder: (context, index) {
                      final s = widget.allServers[index];
                      final isCurrent = widget.server.url == s.url;
                      final isPtBr = s.lang == 'PT-BR';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFFE50914).withValues(alpha: 0.15)
                              : const Color(0xFF1E1E2A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFFE50914)
                                : (isPtBr
                                    ? const Color(0xFF009C3B).withValues(alpha: 0.4)
                                    : Colors.white12),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isPtBr ? Icons.translate_rounded : Icons.play_circle_fill_rounded,
                            color: isCurrent
                                ? const Color(0xFFE50914)
                                : (isPtBr ? const Color(0xFF009C3B) : Colors.white70),
                          ),
                          title: Text(
                            s.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            isPtBr ? 'Áudio Dublado / Legendas PT-BR' : 'Servidor Web em Sandbox com NextDNS',
                            style: GoogleFonts.inter(
                              color: isPtBr ? const Color(0xFF009C3B) : Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFFE50914))
                              : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onServerSelected(s);
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
}
