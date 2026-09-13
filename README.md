# 🎬 MOVIXS — O seu streaming definitivo de filmes e séries

<div align="center">
  <img src="app/assets/images/logo.png" alt="Movixs Logo" width="120" />
  <p><strong>Filmes, Séries de TV e Animações com resolução automática de fontes, proteção Sandbox NextDNS DoH e seleção inteligente de áudio e legendas em PT-BR.</strong></p>
</div>

---

## ✨ Principais Funcionalidades

- 🎥 **Catálogo Completo TMDB**:
  - Em Alta, Mais Populares e Top 10 Brasil para Filmes e Séries.
  - Busca unificada e inteligente com filtro por popularidade e relevância.
- 📺 **Séries de TV Nativas**:
  - Seletor visual de Temporadas e Episódios com sinopses, duração e miniaturas.
  - Transição instantânea com botão "Próximo Episódio".
- 🇧🇷 **Automação de Áudio Dublado e Legendas PT-BR**:
  - Auto-seleção inteligente de faixas de áudio dublado e legendas em português nos reprodutores.
  - Pre-seed de preferências no armazenamento do player (`localStorage`/`sessionStorage`).
  - Compatibilidade com Vidstack, JWPlayer, Video.js, HLS.js e elementos HTML5.
- 🛡️ **Player Seguro com NextDNS DoH**:
  - WebView protegido em Sandbox com bloqueio nativo de popups e anúncios maliciosos.
  - Criptografia DNS over HTTPS (DoH) via NextDNS.
- ⚡ **Multi-Servidores com Prioridade VidSrc.to**:
  - Suporte a VidSrc.to (#1), VidLink, MultiEmbed, 2Embed, Rivestream, SmashyStream e Stremio HTTP.
- 🖥️ **Multiplataforma**:
  - Windows Desktop nativo (atalhos de teclado, aceleração por hardware GPU DirectX/Direct3D11).
  - Android (suporte a múltiplas resoluções de tela).

---

## 🛠️ Tecnologias Utilizadas

- **Framework**: [Flutter](https://flutter.dev) (Dart 3.x)
- **Gerenciamento de Estado**: [Riverpod](https://riverpod.dev)
- **Reprodutores de Vídeo**:
  - [MediaKit](https://github.com/media-kit/media-kit) (Direct Streams .m3u8/.mp4)
  - [Flutter InAppWebView](https://inappwebview.dev/) (Embed Players protegidos com DoH)
- **DNS Seguro**: NextDNS Criptografado (DoH)

---

## 🚀 Como Executar

### Pré-requisitos
- Flutter SDK 3.x instalado
- Git configurado
- Para Windows: C++ Build Tools instalados

### Instalação

```bash
# Clone o repositório
git clone https://github.com/evolucaomente27-bot/Movixs.git
cd Movixs/app

# Instale as dependências
flutter pub get

# Execute no Windows
flutter run -d windows

# Ou execute no dispositivo Android
flutter run -d android
```

### Testes Automatizados

```bash
cd app
flutter test
```

---

## 📄 Licença
Distribuído sob licença de código aberto. Veja `LICENSE` para mais detalhes.
