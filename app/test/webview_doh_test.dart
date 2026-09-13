import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:app/core/services/doh_service.dart';

void main() {
  group('NextDNS DoH no WebView & App', () {
    test('DohService utiliza NextDNS como provedor padrão', () {
      final doh = DohService.instance;
      expect(doh.provider, equals(DohProvider.nextDns));
      expect(doh.currentEndpointUrl, contains('dns.nextdns.io'));
    });

    test('DohService suporta configuração de ID de perfil customizado NextDNS', () {
      final doh = DohService.instance;
      doh.setNextDnsProfileId('movixs123');
      expect(doh.nextDnsProfileId, equals('movixs123'));
      expect(doh.nextDnsEndpointUrl, equals('https://dns.nextdns.io/movixs123'));
      expect(doh.currentEndpointUrl, equals('https://dns.nextdns.io/movixs123/dns-query'));

      // Reseta para padrão
      doh.setNextDnsProfileId(null);
      expect(doh.nextDnsEndpointUrl, equals('https://dns.nextdns.io'));
    });

    test('DohService.getNextDnsChromiumArgs gera switches corretos do Chromium para WebView2', () {
      final defaultArgs = DohService.getNextDnsChromiumArgs();
      expect(defaultArgs, contains('--enable-features=DnsOverHttps'));
      expect(defaultArgs, contains('--dns-over-https-templates=https://dns.nextdns.io/{?dns}'));
      expect(defaultArgs, contains('--autoplay-policy=no-user-gesture-required'));
      expect(defaultArgs, contains('--enable-gpu-rasterization'));
      expect(defaultArgs, contains('--enable-zero-copy'));

      final customArgs = DohService.getNextDnsChromiumArgs(profileId: 'secure789');
      expect(customArgs, contains('https://dns.nextdns.io/secure789/{?dns}'));
    });

    test('WebViewEnvironmentSettings aceita os argumentos do NextDNS DoH', () {
      final args = DohService.getNextDnsChromiumArgs();
      final settings = WebViewEnvironmentSettings(
        additionalBrowserArguments: args,
      );

      expect(settings.additionalBrowserArguments, isNotNull);
      expect(settings.additionalBrowserArguments?.toLowerCase(), contains('nextdns'));
      expect(settings.additionalBrowserArguments, contains('--enable-features=DnsOverHttps'));
    });
  });
}
