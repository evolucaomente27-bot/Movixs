import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum DohProvider {
  nextDns,
  cloudflare,
  google,
  adguard,
}

class DnsRecord {
  final String ip;
  final int ttl;
  final DateTime createdAt;

  DnsRecord({
    required this.ip,
    required this.ttl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpired {
    final validTtl = ttl > 0 ? ttl : 300;
    return DateTime.now().difference(createdAt).inSeconds > validTtl;
  }
}

class DohService extends ChangeNotifier {
  static final DohService instance = DohService();

  bool _isEnabled = true;
  DohProvider _provider = DohProvider.nextDns;
  String? _nextDnsProfileId;

  final Map<String, List<DnsRecord>> _cache = {};

  static const Map<String, List<String>> _bootstrapIps = {
    'dns.nextdns.io': ['45.90.28.0', '45.90.30.0'],
    'chromium.dns.nextdns.io': ['45.90.28.0', '45.90.30.0'],
    'cloudflare-dns.com': ['1.1.1.1', '1.0.0.1'],
    'dns.google': ['8.8.8.8', '8.8.4.4'],
    'dns.adguard-dns.com': ['94.140.14.14', '94.140.15.15'],
  };

  bool get isEnabled => _isEnabled;
  DohProvider get provider => _provider;
  String? get nextDnsProfileId => _nextDnsProfileId;

  /// Retorna o endpoint DoH do NextDNS (público ou com perfil customizado)
  String get nextDnsEndpointUrl {
    if (_nextDnsProfileId != null && _nextDnsProfileId!.trim().isNotEmpty) {
      return 'https://dns.nextdns.io/${_nextDnsProfileId!.trim()}';
    }
    return 'https://dns.nextdns.io';
  }

  String get currentEndpointUrl {
    switch (_provider) {
      case DohProvider.nextDns:
        return '$nextDnsEndpointUrl/dns-query';
      case DohProvider.cloudflare:
        return 'https://cloudflare-dns.com/dns-query';
      case DohProvider.google:
        return 'https://dns.google/resolve';
      case DohProvider.adguard:
        return 'https://dns.adguard-dns.com/dns-query';
    }
  }

  /// Gera os argumentos de linha de comando do Chromium / WebView2 para NextDNS DoH e Aceleração de Hardware
  static String getNextDnsChromiumArgs({String? profileId}) {
    final endpoint = (profileId != null && profileId.trim().isNotEmpty)
        ? 'https://dns.nextdns.io/${profileId.trim()}'
        : 'https://dns.nextdns.io';

    final encodedServer = Uri.encodeComponent('$endpoint/');

    return [
      '--enable-features=DnsOverHttps,PlatformHEVCDecoderSupport,VaapiVideoDecoder',
      '--force-fieldtrials=DnsOverHttps/Enabled',
      '--force-fieldtrial-params=DnsOverHttps.Enabled:server/$encodedServer/method/POST',
      '--dns-over-https-templates=$endpoint/{?dns}',
      '--autoplay-policy=no-user-gesture-required',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--enable-gpu-rasterization',
      '--enable-zero-copy',
      '--ignore-gpu-blocklist',
    ].join(' ');
  }

  void setEnabled(bool value) {
    _isEnabled = value;
    notifyListeners();
  }

  void setProvider(DohProvider value) {
    _provider = value;
    clearCache();
    notifyListeners();
  }

  void setNextDnsProfileId(String? profileId) {
    _nextDnsProfileId = profileId;
    clearCache();
    notifyListeners();
  }

  void clearCache() {
    _cache.clear();
  }

  static bool isIpAddress(String host) {
    return InternetAddress.tryParse(host) != null;
  }

  bool isDohHost(String host) {
    final lower = host.toLowerCase();
    return lower.contains('nextdns.io') ||
        lower.contains('cloudflare-dns.com') ||
        lower.contains('dns.google') ||
        lower.contains('adguard-dns.com');
  }

  /// Resolve hostname to IP using DoH
  Future<String?> resolveHost(String host) async {
    if (!_isEnabled) return null;
    if (isIpAddress(host)) return host;

    for (final entry in _bootstrapIps.entries) {
      if (host.toLowerCase() == entry.key) {
        return entry.value.first;
      }
    }

    final cached = _cache[host];
    if (cached != null && cached.isNotEmpty) {
      final valid = cached.where((r) => !r.isExpired).toList();
      if (valid.isNotEmpty) {
        return valid.first.ip;
      }
    }

    try {
      final endpoint = currentEndpointUrl;
      final uri = Uri.parse(endpoint).replace(
        queryParameters: {
          'name': host,
          'type': 'A',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/dns-json',
          'User-Agent': 'Movixs-DoH/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final answers = data['Answer'] as List?;
        if (answers != null && answers.isNotEmpty) {
          final List<DnsRecord> records = [];
          for (final item in answers) {
            final type = item['type'];
            if (type == 1 && item['data'] != null) {
              final ip = item['data'].toString().trim();
              if (isIpAddress(ip)) {
                final ttl = item['TTL'] is int ? item['TTL'] as int : 300;
                records.add(DnsRecord(ip: ip, ttl: ttl));
              }
            }
          }

          if (records.isNotEmpty) {
            _cache[host] = records;
            return records.first.ip;
          }
        }
      }
    } catch (e) {
      debugPrint('[DoH] Resolution fallback for $host: $e');
    }

    return null;
  }
}

/// Global HttpOverrides that routes Dart HttpClient connections through DoH
class DohHttpOverrides extends HttpOverrides {
  final DohService dohService;

  DohHttpOverrides(this.dohService);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final host = uri.host;
      final port = uri.port;

      if (!dohService.isEnabled ||
          DohService.isIpAddress(host) ||
          dohService.isDohHost(host) ||
          host.isEmpty) {
        return Socket.startConnect(host, port);
      }

      final resolvedIp = await dohService.resolveHost(host);
      if (resolvedIp != null && resolvedIp.isNotEmpty) {
        return Socket.startConnect(resolvedIp, port);
      }

      return Socket.startConnect(host, port);
    };

    return client;
  }
}
