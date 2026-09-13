import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'core/services/doh_service.dart';
import 'presentation/home_screen.dart';

/// Ambiente global do WebView2 configurado com NextDNS DoH e aceleração GPU
WebViewEnvironment? globalWebViewEnvironment;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carrega as variáveis de ambiente com fallback caso o arquivo falhe
  try {
    await dotenv.load(fileName: ".env");
    final customNextDns = dotenv.env['NEXTDNS_PROFILE_ID'];
    if (customNextDns != null && customNextDns.trim().isNotEmpty) {
      DohService.instance.setNextDnsProfileId(customNextDns.trim());
    }
  } catch (e) {
    debugPrint('Nota: arquivo .env não carregado, usando configurações padrão.');
  }

  // Inicialização do media_kit
  MediaKit.ensureInitialized();

  // Inicialização do WebViewEnvironment no Windows com NextDNS DoH nativo
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion != null) {
        globalWebViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            additionalBrowserArguments: DohService.getNextDnsChromiumArgs(
              profileId: DohService.instance.nextDnsProfileId,
            ),
          ),
        );
        debugPrint('[NextDNS] 🚀 WebView2 inicializado com sucesso usando DoH NextDNS.');
      }
    } catch (e) {
      debugPrint('[NextDNS] ⚠️ Erro ao criar WebViewEnvironment no Windows: $e');
    }
  }

  runApp(
    const ProviderScope(
      child: MovixsApp(),
    ),
  );
}

class MovixsApp extends StatelessWidget {
  const MovixsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movixs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0C12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          surface: Color(0xFF161622),
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}
